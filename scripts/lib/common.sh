# shellcheck shell=bash
# Variables defined here are used by the scripts that source this file.
# shellcheck disable=SC2034
#
# Shared by the workflow scripts: sourced, never run. Sets ROOT to the
# repository root and provides logging, the pinned toolchain images, and the
# steps more than one script needs (Flutter in a container, the API contract).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# The development stack (scripts/local.sh, scripts/try-pr.sh). The Compose
# file is machine-local and never falls back to the production file.
DEV_COMPOSE_FILE="docker-compose-dev.yml"
DEV_COMPOSE_TEMPLATE="docs/development/docker-compose-dev.example.yml"
DEV_ENV_FILE=".env"
DEV_PROJECT="tildeck-dev"
DEV_SERVER_IMAGE="tildeck-server:dev"
DEV_SERVER_CONTAINER="tildeck-server-dev"
DEV_DB_CONTAINER="tildeck-postgres-dev"
DEV_DB_VOLUME="tildeck-db-data"
DEV_URL="http://localhost:8280"

require_dev_compose_file() {
  if [[ ! -f "$ROOT/$DEV_COMPOSE_FILE" ]]; then
    err "$DEV_COMPOSE_FILE is missing. It is machine-local; create it from the template:"
    err "  cp $DEV_COMPOSE_TEMPLATE $DEV_COMPOSE_FILE"
    exit 1
  fi
}

require_dev_stack() {
  require_dev_compose_file
  if [[ ! -f "$ROOT/$DEV_ENV_FILE" ]]; then
    err "$DEV_ENV_FILE is missing. scripts/local.sh up creates it with generated secrets."
    err "Every checkout on this machine shares one development stack: if it already exists,"
    err "copy the $DEV_ENV_FILE of the checkout that created it."
    exit 1
  fi
}

# The ignored .env of the development stack, created once with generated
# secrets (scripts/local.sh up). An existing file is never overwritten.
ensure_dev_env() {
  local env="$ROOT/$DEV_ENV_FILE" volumes password key
  if [[ -L "$env" || (-e "$env" && ! -f "$env") ]]; then
    err "$DEV_ENV_FILE is not a regular file. Move it away and run this again."
    exit 1
  fi
  [[ -f "$env" ]] && return 0

  # docker volume ls fails when Docker is unreachable, so an error is never
  # taken for a missing volume.
  if ! volumes="$(docker volume ls -q --filter "name=^${DEV_DB_VOLUME}\$")"; then
    err "Docker is not reachable."
    exit 1
  fi
  if [[ -n "$volumes" ]]; then
    err "$DEV_ENV_FILE is missing, but the development database ($DEV_DB_VOLUME) exists."
    err "It was set up with another $DEV_ENV_FILE: copy that file here, from the checkout that created it."
    err "Or delete the development data, which cannot be undone:"
    err "  docker rm -f $DEV_SERVER_CONTAINER $DEV_DB_CONTAINER && docker volume rm $DEV_DB_VOLUME"
    exit 1
  fi

  log "Creating $DEV_ENV_FILE with generated secrets ..."
  # Written completely into a private temporary file, then published with
  # a hard link, which fails instead of replacing an existing file. The
  # trap removes the temporary file on any exit, also an interrupted one.
  DEV_ENV_TMP="$(mktemp "$env.new.XXXXXX")" || exit 1
  trap 'rm -f -- "$DEV_ENV_TMP"' EXIT
  trap 'exit 130' INT TERM HUP
  ensure_owner_only "$DEV_ENV_TMP" || exit 1
  password="$(random_hex 32)" || exit 1
  key="$(random_hex 32)" || exit 1
  {
    printf '# Created by scripts/local.sh with generated secrets. Never commit it.\n'
    # The values reach awk through its environment, not its command line.
    PASSWORD="$password" KEY="$key" awk '
      /^POSTGRES_PASSWORD=/ { print "POSTGRES_PASSWORD=" ENVIRON["PASSWORD"]; next }
      /^DATABASE_URL=/ { sub(/:change-me@/, ":" ENVIRON["PASSWORD"] "@"); print; next }
      /^CONFIG_ENCRYPTION_KEY=/ { print "CONFIG_ENCRYPTION_KEY=" ENVIRON["KEY"]; next }
      { print }
    ' "$ROOT/.env.example"
  } >>"$DEV_ENV_TMP" || exit 1
  if grep -E '^(POSTGRES_PASSWORD|DATABASE_URL|CONFIG_ENCRYPTION_KEY)=' "$DEV_ENV_TMP" | grep -q 'change-me' \
    || (($(grep -cE '^(POSTGRES_PASSWORD|DATABASE_URL|CONFIG_ENCRYPTION_KEY)=' "$DEV_ENV_TMP") != 3)); then
    err ".env.example no longer has the expected POSTGRES_PASSWORD, DATABASE_URL, and CONFIG_ENCRYPTION_KEY lines."
    exit 1
  fi
  if ! ln -T -- "$DEV_ENV_TMP" "$env"; then
    err "$DEV_ENV_FILE appeared while it was being created. Nothing was overwritten."
    exit 1
  fi
  rm -f -- "$DEV_ENV_TMP"
  trap - EXIT INT TERM HUP
  log "Created $DEV_ENV_FILE. Keep it: the development database needs these values."
}

# The current Windows user's SID and a file's owner and access list (SDDL),
# separated by a space. The path reaches PowerShell through WSLENV, which
# translates it, not through the command string.
# shellcheck disable=SC2016 # the command is PowerShell code, expanded there
windows_acl() {
  TILDECK_ACL_PATH="$1" WSLENV="TILDECK_ACL_PATH/p${WSLENV:+:$WSLENV}" powershell.exe -NoProfile -NonInteractive -Command \
    '[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value + " " + [System.IO.File]::GetAccessControl($env:TILDECK_ACL_PATH).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]"Owner, Access")' \
    2>/dev/null | tr -d '\r'
}

# True when the SDDL says: owned by the SID, inheritance off, and one entry,
# full control for the SID. $1: "SID SDDL" from windows_acl.
windows_owner_only() {
  local sid="${1%% *}" sddl="${1#* }" want
  want="^O:${sid}D:P[A-Z]*\\(A;;FA;;;${sid}\\)\$"
  [[ -n "$sid" && "$sddl" =~ $want ]]
}

# Make a file readable by its owner only, and verify it. On a Windows drive
# under WSL, chmod has no effect and the Windows access list decides; it is
# tightened in one icacls command (never widened on the way) and checked.
ensure_owner_only() {
  local file="$1" win state sid
  # A Windows drive gives C:\...; a WSL path gives \\wsl.localhost\...
  if win="$(wslpath -w "$file" 2>/dev/null)" && [[ "$win" =~ ^[A-Za-z]: ]]; then
    state="$(windows_acl "$file")"
    windows_owner_only "$state" && return 0
    sid="${state%% *}"
    if [[ -z "$sid" || "${state#* }" != "O:${sid}D:"* ]]; then
      err "$file must belong to your Windows account, and its permissions could not be checked."
      return 1
    fi
    icacls.exe "$win" /inheritance:r /grant:r "*$sid:F" >/dev/null 2>&1 || true
    windows_owner_only "$(windows_acl "$file")" && return 0
    err "$file must be readable only by you. Remove the other accounts' access to it (Properties, Security) and run this again."
    return 1
  fi
  chmod 600 "$file" 2>/dev/null || true
  if [[ "$(stat -c '%a %u' "$file" 2>/dev/null)" != "600 $(id -u)" ]]; then
    err "$file must be yours and readable only by you (mode 600), and could not be made so."
    return 1
  fi
}

# Refuse to start the development stack unless the values Compose resolves
# (from .env, or exported in this shell) are present, generated, and agree.
# The check runs in the server's dependency image with this checkout's code
# (app/dev_env_check.py) and prints names, never values; Compose's own error
# output, which can quote a .env line, is not shown.
#
# Known limits: the files are read again when the stack starts, so a change
# to .env between this check and the start is not seen; and a checkout
# whose .env differs from the one that set up the shared database passes
# this check but its server cannot sign in to PostgreSQL (copy the right
# .env and start again; no data is written or lost).
require_dev_secrets() {
  local env="$ROOT/$DEV_ENV_FILE" config image
  if [[ -L "$env" || ! -f "$env" ]]; then
    err "$DEV_ENV_FILE is missing or not a regular file."
    exit 1
  fi
  ensure_owner_only "$env" || exit 1
  if ! config="$(dev_compose config --format json 2>/dev/null)"; then
    err "docker compose could not read $DEV_COMPOSE_FILE or $DEV_ENV_FILE. Check the syntax of both, and that"
    err "$DEV_ENV_FILE sets POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD, DATABASE_URL, and CONFIG_ENCRYPTION_KEY."
    exit 1
  fi
  if ! image="$(server_deps_image)"; then
    err "Could not build the server's dependency image to check $DEV_ENV_FILE."
    exit 1
  fi
  if ! printf '%s' "$config" | docker run --rm -i -v "$ROOT/server/app:/app/app:ro" -w /app "$image" \
    /opt/venv/bin/python -m app.dev_env_check; then
    err "The development stack does not start with these values (from $DEV_ENV_FILE, or exported in this shell)."
    err "To start over with generated secrets, which DELETES the development data:"
    err "  scripts/local.sh nuke              (with this $DEV_ENV_FILE still in place)"
    err "  mv $DEV_ENV_FILE $DEV_ENV_FILE.old"
    err "  scripts/local.sh up -b -d"
    exit 1
  fi
}

dev_compose() {
  docker compose -p "$DEV_PROJECT" --env-file "$ROOT/$DEV_ENV_FILE" -f "$ROOT/$DEV_COMPOSE_FILE" "$@"
}

# The image reference of a stage in scripts/toolchain/Dockerfile.
toolchain_image() {
  local image
  image="$(awk -v stage="$1" '$1 == "FROM" && $3 == "AS" && $4 == stage { print $2 }' "$ROOT/scripts/toolchain/Dockerfile")"
  if [[ -z "$image" ]]; then
    err "No toolchain image named $1 in scripts/toolchain/Dockerfile."
    return 1
  fi
  printf '%s\n' "$image"
}

version() {
  tr -d '[:space:]' <"$ROOT/VERSION"
}

# $1 random bytes from the kernel's CSPRNG, as lowercase hex. Used for every
# secret the scripts generate. -v: od must not collapse repeated lines.
random_hex() {
  local hex
  hex="$(od -An -v -tx1 -N"$1" /dev/urandom | tr -d ' \n')" || return 1
  if ((${#hex} != $1 * 2)); then
    err "Could not read $1 random bytes."
    return 1
  fi
  printf '%s\n' "$hex"
}

# Run a shell command in the Flutter toolchain container, in app/ of the
# source tree $FLUTTER_SRC (default: this checkout). Caches survive between
# runs in named volumes: pub packages, Gradle, and the NDK and CMake that the
# Android build installs into the SDK on first use. The image runs as root,
# so whatever it wrote under app/ is handed back to the calling user. The
# release signing variables pass through when set (the publish workflow
# only; app/android/app/build.gradle.kts reads them).
#
# FLUTTER_DOCKER_ARGS, an array, adds docker run options (a network, test
# environment variables) for one call.
FLUTTER_DOCKER_ARGS=()
# FLUTTER_CACHE names the cache volumes (default tildeck): code that is not
# trusted builds with caches of its own, so it cannot leave anything behind
# for the trusted builds.
flutter_run() {
  local image src="${FLUTTER_SRC:-$ROOT}" cache="${FLUTTER_CACHE:-tildeck}"
  image="$(toolchain_image flutter)"
  docker run --rm "${FLUTTER_DOCKER_ARGS[@]}" \
    -v "$src:/work" -w /work/app \
    -v "$cache-pub-cache:/root/.pub-cache" \
    -v "$cache-gradle-cache:/root/.gradle" \
    -v "$cache-android-ndk:/opt/android-sdk-linux/ndk" \
    -v "$cache-android-cmake:/opt/android-sdk-linux/cmake" \
    -e PUB_CACHE=/root/.pub-cache \
    -e TILDECK_KEYSTORE_FILE -e TILDECK_KEYSTORE_PASSWORD -e TILDECK_KEY_ALIAS -e TILDECK_KEY_PASSWORD \
    "$image" bash -c "trap 'chown -R $(id -u):$(id -g) /work/app' EXIT
      flutter config --no-analytics >/dev/null 2>&1; set -e; $1"
}

# Build the server runtime image, with the panel, from a source tree.
# $1: the tree (a checkout or a worktree). $2: the image tag.
build_server_image() {
  local src="$1" tag="$2"
  docker build \
    --build-context "panel=$src/panel" \
    --build-arg "APP_VERSION=$(tr -d '[:space:]' <"$src/VERSION")" \
    --target runtime \
    -f "$src/server/Dockerfile" \
    -t "$tag" \
    "$src/server"
}

# Health of a container as Docker reports it: healthy, unhealthy, starting,
# or "none" when it has no health check or does not exist.
health_of() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "none"
}

# Wait until a container is healthy. $1: the container. $2: seconds.
wait_healthy() {
  local name="$1" limit="${2:-120}" waited=0 status
  while ((waited < limit)); do
    status="$(health_of "$name")"
    case "$status" in
      healthy) return 0 ;;
      unhealthy)
        err "$name is unhealthy. Last log lines:"
        docker logs --tail 30 "$name" >&2 || true
        return 1
        ;;
    esac
    sleep 2
    waited=$((waited + 2))
  done
  err "$name did not become healthy within ${limit}s (status: $(health_of "$name"))."
  docker logs --tail 30 "$name" >&2 || true
  return 1
}

# The effective UID of a container's main process (PID 1). Not `id -u`
# through docker exec, which reports the exec session's user: the postgres
# image starts as root and drops to postgres, so only PID 1 tells the truth.
process_uid() {
  docker exec "$1" cat /proc/1/status 2>/dev/null | awk '/^Uid:/ { print $3; found = 1 } END { if (!found) print "unknown" }'
}

# A container must run exactly the image built for it (by id), and its main
# process must not be root. $1: the container. $2: the image tag.
verify_container_image() {
  local name="$1" image="$2" built running uid
  built="$(docker inspect --format '{{.Id}}' "$image" 2>/dev/null || true)"
  running="$(docker inspect --format '{{.Image}}' "$name" 2>/dev/null || true)"
  if [[ -z "$built" || "$built" != "$running" ]]; then
    err "$name does not run the current $image (built: ${built:0:19}, running: ${running:0:19})."
    return 1
  fi
  uid="$(process_uid "$name")"
  if [[ "$uid" == "0" || "$uid" == "unknown" ]]; then
    err "$name runs as UID $uid. Application containers must not run as root."
    return 1
  fi
  log "verified: $name runs $image (${built:7:12}) as UID $uid"
}

# Build the server's dependency stage, used to run server code outside the
# runtime image.
server_deps_image() {
  docker build -q --target deps -t tildeck-server:deps "$ROOT/server" >/dev/null || return 1
  printf 'tildeck-server:deps\n'
}

# Print the OpenAPI document the server code describes. Building the app
# needs the bootstrap values but never connects or encrypts, so it gets a
# one-time key and a database URL without credentials.
export_openapi() {
  local image key
  image="$(server_deps_image)" || return 1
  key="$(random_hex 32)" || return 1
  DATABASE_URL="postgresql+asyncpg://export@localhost:5432/export" CONFIG_ENCRYPTION_KEY="$key" \
    docker run --rm -e DATABASE_URL -e CONFIG_ENCRYPTION_KEY \
    -v "$ROOT/server/app:/app/app:ro" -w /app "$image" \
    /opt/venv/bin/python -m app.openapi_export
}

# Generate the Dart API client from an OpenAPI document into a directory.
# $1: the document, relative to the repository root. $2: the output
# directory, relative to the repository root; it is replaced.
generate_api_client() {
  local spec="$1" out="$2" image ignore
  image="$(toolchain_image openapi-generator)"
  # The ignore rules live in the committed package; read them before the
  # output directory (which may be that package) is replaced.
  ignore="$(cat "$ROOT/app/packages/tildeck_api/.openapi-generator-ignore")"
  rm -rf "${ROOT:?}/$out"
  mkdir -p "$ROOT/$out"
  printf '%s\n' "$ignore" >"$ROOT/$out/.openapi-generator-ignore"
  docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT:/work" "$image" generate \
    -i "/work/$spec" -g dart -o "/work/$out" \
    --additional-properties=pubName=tildeck_api,pubDescription="Tildeck server API client generated from server/openapi.json",pubAuthor=Tildeck,pubHomepage=https://tildeck.com \
    --global-property=apiTests=false,modelTests=false,apiDocs=false,modelDocs=false \
    >/dev/null
  # On a Windows drive under WSL, replacing a directory tree that a
  # container just wrote leaves this shell's working directory handle stale
  # ("Unable to read current working directory"). Re-enter it by path.
  cd "$ROOT" || return 1
}
