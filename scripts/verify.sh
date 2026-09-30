#!/usr/bin/env bash
#
# verify.sh - the single verification entry point. The same commands run on a
# developer machine, in CI, and before a release.
#
#   scripts/verify.sh                  full run: every area
#   scripts/verify.sh --changed        only the areas changed against main (guards always run)
#   scripts/verify.sh --area <name>    one area: server | panel | image | app | contract | guards
#   scripts/verify.sh --changed --print-areas   print the changed areas as JSON, run nothing (CI)
#
# Areas:
#   server    ruff, and pytest against a throwaway PostgreSQL
#   panel     panel lint, type checks, and the static build
#   image     the server runtime image (with the panel) builds and runs as non-root
#   app       Dart format, flutter analyze, tests with golden images, debug APK
#   contract  server/openapi.json and app/packages/tildeck_api match the server code
#   guards    text (locales, Hebrew, dashes), Compose, secrets, line endings,
#             file modes, the repository root, shellcheck, shfmt
#
# Everything runs in containers: the host needs Docker and nothing else. The
# test database is a throwaway PostgreSQL on a private network with a unique
# name, never the development database and never .env. Temporary containers,
# networks, and files are removed on exit, also on failure.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT"

AREAS_ALL="server panel image app contract guards"
RUN_ID="verify-$$-$(date +%s)"
NET="tildeck-$RUN_ID"
PG_CONTAINER="tildeck-$RUN_ID-db"
CONTRACT_DIR="out/$RUN_ID-contract"
SSH_NET="tildeck-$RUN_ID-ssh"
SSH_CONTAINER="tildeck-$RUN_ID-sshd"
SERVER_TEST_IMAGE="tildeck-server:verify"
SERVER_RUNTIME_IMAGE="tildeck-server:verify-runtime"

section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

cleanup() {
  # -v: the postgres image declares a data volume; without it every run
  # would leave an anonymous volume behind.
  docker rm -f -v "$PG_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  docker rm -f -v "$SSH_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$SSH_NET" >/dev/null 2>&1 || true
  rm -rf "${ROOT:?}/$CONTRACT_DIR"
}
trap cleanup EXIT

# --- Area selection ----------------------------------------------------------

changed_files() {
  local base
  if git rev-parse --verify -q origin/main >/dev/null; then
    base="$(git merge-base origin/main HEAD)"
  elif git rev-parse --verify -q main >/dev/null; then
    base="$(git merge-base main HEAD)"
  else
    warn "No main branch to compare against; running everything."
    printf 'VERIFY_ALL\n'
    return
  fi
  {
    git diff --name-only "$base" HEAD
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | sort -u
}

# The areas a list of changed paths touches. Shared tooling (this script, the
# script library, the toolchain pins, the CI workflows) touches every area.
areas_for() {
  local files="$1" areas="" shared='^(scripts/verify\.sh|scripts/lib/|scripts/toolchain/|\.github/workflows/|VERIFY_ALL)'
  if grep -qE "^server/|$shared" <<<"$files"; then areas+=" server"; fi
  if grep -qE "^panel/|$shared" <<<"$files"; then areas+=" panel"; fi
  if grep -qE "^(server/|panel/|VERSION$)|$shared" <<<"$files"; then areas+=" image"; fi
  if grep -qE "^app/|$shared" <<<"$files"; then areas+=" app"; fi
  if grep -qE "^(server/|app/packages/tildeck_api/)|$shared" <<<"$files"; then areas+=" contract"; fi
  printf '%s guards\n' "$areas"
}

select_areas() {
  case "$1" in
    full) printf '%s\n' "$AREAS_ALL" ;;
    area)
      if ! grep -qw -- "$2" <<<"$AREAS_ALL" || [[ -z "$2" ]]; then
        err "Unknown area: ${2:-<none>} (expected one of: $AREAS_ALL)"
        exit 2
      fi
      printf '%s\n' "$2"
      ;;
    changed) areas_for "$(changed_files)" ;;
  esac
}

# --- Areas -------------------------------------------------------------------

# Every step ends with "|| return 1": the area functions run inside an "if",
# where "set -e" is suspended, so a failing step would otherwise be masked by
# a later step that succeeds.

verify_server() {
  section "server: build the test image"
  docker build --target test -t "$SERVER_TEST_IMAGE" ./server || return 1

  section "server: ruff"
  docker run --rm "$SERVER_TEST_IMAGE" ruff check app tests || return 1
  docker run --rm "$SERVER_TEST_IMAGE" ruff format --check app tests || return 1

  section "server: pytest against a throwaway PostgreSQL"
  docker network create "$NET" >/dev/null || return 1
  docker run -d --name "$PG_CONTAINER" --network "$NET" \
    -e POSTGRES_USER=tildeck -e POSTGRES_PASSWORD=tildeck -e POSTGRES_DB=tildeck_test \
    "$(toolchain_image postgres)" >/dev/null || return 1
  local waited=0
  until docker exec "$PG_CONTAINER" pg_isready -U tildeck -d tildeck_test >/dev/null 2>&1; do
    sleep 1
    waited=$((waited + 1))
    if ((waited >= 60)); then
      err "PostgreSQL did not become ready within 60s."
      docker logs "$PG_CONTAINER" >&2 || true
      return 1
    fi
  done
  docker run --rm --network "$NET" \
    -e "TEST_DATABASE_URL=postgresql+asyncpg://tildeck:tildeck@$PG_CONTAINER:5432/tildeck_test" \
    "$SERVER_TEST_IMAGE" pytest -q || return 1
}

verify_panel() {
  section "panel: lint and type checks"
  docker build --build-context panel=./panel -f server/Dockerfile --target panel-check ./server || return 1

  section "panel: static build"
  docker build --build-context panel=./panel -f server/Dockerfile --target panel-build \
    --build-arg "APP_VERSION=$(version)" ./server || return 1
}

verify_image() {
  section "image: server runtime image with the panel"
  docker build --build-context panel=./panel -f server/Dockerfile --target runtime \
    --build-arg "APP_VERSION=$(version)" -t "$SERVER_RUNTIME_IMAGE" ./server || return 1

  section "image: non-root runtime user and a real health check"
  local user uid health
  user="$(docker image inspect --format '{{.Config.User}}' "$SERVER_RUNTIME_IMAGE")" || return 1
  uid="$(docker run --rm --entrypoint id "$SERVER_RUNTIME_IMAGE" -u)" || return 1
  health="$(docker image inspect --format '{{if .Config.Healthcheck}}{{join .Config.Healthcheck.Test " "}}{{end}}' "$SERVER_RUNTIME_IMAGE")" || return 1
  if [[ -z "$user" || "$user" == root || "$uid" == 0 ]]; then
    err "The runtime image runs as root (USER '${user:-unset}', UID $uid)."
    return 1
  fi
  if [[ "$health" != *"/api/health/ready"* ]]; then
    err "The runtime image's health check does not call /api/health/ready: '$health'"
    return 1
  fi
  if ! docker run --rm --entrypoint test "$SERVER_RUNTIME_IMAGE" -f /app/panel/index.html; then
    err "The runtime image does not contain the built panel."
    return 1
  fi
  log "runtime image: user $user (UID $uid), panel included, health check calls /api/health/ready"
}

# A throwaway OpenSSH server for the client's SSH tests, with a password,
# a plain Ed25519 key, and a passphrase-protected one. Everything it holds is
# generated here for this run and removed with the container.
start_test_sshd() {
  local password key_pass waited=0
  password="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  key_pass="$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')"
  docker network create "$SSH_NET" >/dev/null || return 1
  docker run -d --name "$SSH_CONTAINER" --network "$SSH_NET" \
    -e PUID=1000 -e PGID=1000 -e USER_NAME=tildeck -e "USER_PASSWORD=$password" -e PASSWORD_ACCESS=true \
    "$(toolchain_image openssh)" >/dev/null || return 1
  until docker exec "$SSH_CONTAINER" nc -z 127.0.0.1 2222 >/dev/null 2>&1; do
    sleep 1
    waited=$((waited + 1))
    if ((waited >= 90)); then
      err "The test SSH server did not start within 90s."
      docker logs --tail 20 "$SSH_CONTAINER" >&2 || true
      return 1
    fi
  done
  # Keys are generated as the account's user, so authorized_keys has the
  # owner and mode sshd insists on.
  docker exec -u tildeck -e "KEY_PASS=$key_pass" "$SSH_CONTAINER" sh -c '
    ssh-keygen -q -t ed25519 -N "" -f /tmp/plain &&
    ssh-keygen -q -t ed25519 -N "$KEY_PASS" -f /tmp/encrypted &&
    cat /tmp/plain.pub /tmp/encrypted.pub >> /config/.ssh/authorized_keys &&
    chmod 600 /config/.ssh/authorized_keys' || return 1
  FLUTTER_DOCKER_ARGS=(
    --network "$SSH_NET"
    -e TILDECK_REQUIRE_SSH_TESTS=1
    -e "TILDECK_TEST_SSH_HOST=$SSH_CONTAINER"
    -e TILDECK_TEST_SSH_PORT=2222
    -e TILDECK_TEST_SSH_USER=tildeck
    -e "TILDECK_TEST_SSH_PASSWORD=$password"
    -e "TILDECK_TEST_SSH_KEY=$(docker exec "$SSH_CONTAINER" cat /tmp/plain)"
    -e "TILDECK_TEST_SSH_KEY_ENCRYPTED=$(docker exec "$SSH_CONTAINER" cat /tmp/encrypted)"
    -e "TILDECK_TEST_SSH_KEY_PASSPHRASE=$key_pass"
  )
}

verify_app() {
  section "app: a throwaway OpenSSH server for the SSH tests"
  start_test_sshd || return 1

  section "app: format, analyze, tests and golden images, debug APK"
  # Formatting covers the code this repository owns; generated code (the API
  # client, gen-l10n output) is excluded. Single quotes on purpose: the
  # command substitution runs inside the container, not here.
  # shellcheck disable=SC2016
  flutter_run '
    echo "-- flutter pub get (the committed pubspec.lock must be current)"
    flutter pub get --enforce-lockfile
    echo "-- dart format"
    dart format --output none --set-exit-if-changed $(find lib test -name "*.dart" ! -name "app_localizations*")
    echo "-- flutter analyze"
    flutter analyze
    echo "-- flutter test"
    flutter test
    echo "-- flutter build apk --debug"
    flutter build apk --debug --build-name='"$(version)"'
  ' || return 1
  FLUTTER_DOCKER_ARGS=()
}

verify_contract() {
  section "contract: server/openapi.json matches the server code"
  local spec
  spec="$(export_openapi)" || return 1
  if ! diff -u server/openapi.json <(printf '%s\n' "$spec"); then
    err "server/openapi.json is out of date. Run: scripts/local.sh contract"
    return 1
  fi
  log "server/openapi.json is current"

  section "contract: the generated Dart client matches server/openapi.json"
  generate_api_client server/openapi.json "$CONTRACT_DIR/tildeck_api" || return 1
  if ! diff -r -x pubspec.lock -x .dart_tool app/packages/tildeck_api "$CONTRACT_DIR/tildeck_api"; then
    err "app/packages/tildeck_api is out of date or edited by hand. Run: scripts/local.sh contract"
    return 1
  fi
  log "app/packages/tildeck_api is current"
}

# The files allowed at the repository root (docs/project-foundation.md,
# "Planned repository root").
ROOT_FILES=".env.example .gitattributes .gitignore AGENTS.md CHANGELOG.md LICENSE README.md VERSION docker-compose.yml"

verify_guards() {
  local ok=0 f

  section "guards: locales, Hebrew, and Unicode dashes"
  git ls-files -z | docker run --rm -i -v "$ROOT:/repo:ro" -w /repo "$(toolchain_image python)" \
    python3 scripts/check-text.py --stdin || ok=1

  section "guards: no build: in Compose files"
  local compose_files=(docker-compose.yml docs/development/docker-compose-dev.example.yml)
  [[ -f docker-compose-dev.yml ]] && compose_files+=(docker-compose-dev.yml)
  if grep -nE '^\s*build:' "${compose_files[@]}"; then
    err "Compose files must not build images. The scripts and the publish workflow build them."
    ok=1
  else
    log "no build: in ${compose_files[*]}"
  fi

  section "guards: nothing machine-local or secret is tracked"
  for f in .env docker-compose-dev.yml; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      err "$f is tracked by Git. Remove it from the index."
      ok=1
    fi
  done
  if git ls-files | grep -E '\.(jks|keystore)$|(^|/)key\.properties$'; then
    err "Signing material is tracked by Git."
    ok=1
  fi

  section "guards: the repository root holds only the listed files"
  local extra
  extra="$(git ls-files | grep -v / | grep -vxF -f <(tr ' ' '\n' <<<"$ROOT_FILES") || true)"
  if [[ -n "$extra" ]]; then
    err "Unlisted files at the repository root (add them to the plan or move them): $extra"
    ok=1
  fi

  section "guards: line endings"
  local crlf=0
  while IFS= read -r f; do
    if grep -q $'\r' "$f"; then
      err "CRLF line ending in $f"
      crlf=1
    fi
  done < <(git ls-files -- '*.sh' '*.py' '*Dockerfile' '*.yml' '*.yaml')
  if ((crlf == 0)); then log "scripts, Dockerfiles, and YAML files are LF"; else ok=1; fi

  section "guards: workflow scripts are executable"
  while read -r mode f; do
    if [[ "$mode" != 100755 ]]; then
      err "$f is not executable in Git (fix: git update-index --chmod=+x $f)"
      ok=1
    fi
  done < <(git ls-files -s -- ':(glob)scripts/*.sh' ':(glob)scripts/*.py' | awk '{ print $1, $4 }')

  section "guards: GitHub Actions workflows"
  if [[ -d .github/workflows ]]; then
    docker run --rm -v "$ROOT:/repo:ro" -w /repo "$(toolchain_image actionlint)" -color || ok=1
  fi

  section "guards: shellcheck and shfmt"
  # Paths are resolved here and passed one by one: a glob would expand on
  # the host, not in the container.
  local sh_files=()
  while IFS= read -r f; do sh_files+=("/repo/$f"); done < <(git ls-files -- 'scripts/*.sh')
  docker run --rm -v "$ROOT:/repo:ro" -w /repo "$(toolchain_image shellcheck)" -x -S style "${sh_files[@]}" || ok=1
  if ! docker run --rm -v "$ROOT:/repo:ro" "$(toolchain_image shfmt)" -d -i 2 -ci -bn "${sh_files[@]}"; then
    err "shfmt found formatting differences. Fix: docker run --rm -v \"\$PWD:/repo\" $(toolchain_image shfmt) -w -i 2 -ci -bn /repo/scripts"
    ok=1
  fi

  return "$ok"
}

# --- Main --------------------------------------------------------------------

MODE="full"
AREA=""
PRINT_ONLY=false
while (($# > 0)); do
  case "$1" in
    --changed) MODE="changed" ;;
    --print-areas) PRINT_ONLY=true ;;
    --area)
      MODE="area"
      AREA="${2:-}"
      shift
      ;;
    -h | --help)
      sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      exit 2
      ;;
  esac
  shift
done

AREAS="$(select_areas "$MODE" "$AREA")"

# CI asks which areas a change touches, so the path-to-area mapping lives
# only here. Printed as a JSON array for a job matrix; nothing runs.
if [[ "$PRINT_ONLY" == true ]]; then
  # shellcheck disable=SC2086
  printf '%s\n' $AREAS | awk 'BEGIN { printf "[" } { printf "%s\"%s\"", (NR > 1 ? "," : ""), $0 } END { print "]" }'
  exit 0
fi

log "verify: mode=$MODE areas=[${AREAS# }]"

PASSED=()
FAILED=()
SKIPPED=()
for area in $AREAS_ALL; do
  if grep -qw "$area" <<<"$AREAS"; then
    if "verify_$area"; then PASSED+=("$area"); else FAILED+=("$area"); fi
  else
    SKIPPED+=("$area")
  fi
done

section "summary"
if ((${#PASSED[@]} > 0)); then log "passed:  ${PASSED[*]}"; fi
if ((${#SKIPPED[@]} > 0)); then warn "skipped: ${SKIPPED[*]}"; fi
if ((${#FAILED[@]} > 0)); then
  err "FAILED:  ${FAILED[*]}"
  exit 1
fi
log "verify passed"
