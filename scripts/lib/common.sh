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

require_dev_stack() {
  if [[ ! -f "$ROOT/$DEV_COMPOSE_FILE" ]]; then
    err "$DEV_COMPOSE_FILE is missing. It is machine-local; create it from the template:"
    err "  cp $DEV_COMPOSE_TEMPLATE $DEV_COMPOSE_FILE"
    exit 1
  fi
  if [[ ! -f "$ROOT/$DEV_ENV_FILE" ]]; then
    err "$DEV_ENV_FILE is missing. Create it from the example:"
    err "  cp .env.example $DEV_ENV_FILE"
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
flutter_run() {
  local image src="${FLUTTER_SRC:-$ROOT}"
  image="$(toolchain_image flutter)"
  docker run --rm "${FLUTTER_DOCKER_ARGS[@]}" \
    -v "$src:/work" -w /work/app \
    -v tildeck-pub-cache:/root/.pub-cache \
    -v tildeck-gradle-cache:/root/.gradle \
    -v tildeck-android-ndk:/opt/android-sdk-linux/ndk \
    -v tildeck-android-cmake:/opt/android-sdk-linux/cmake \
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
  docker build -q --target deps -t tildeck-server:deps "$ROOT/server" >/dev/null
  printf 'tildeck-server:deps\n'
}

# Print the OpenAPI document the server code describes.
export_openapi() {
  local image
  image="$(server_deps_image)"
  docker run --rm -v "$ROOT/server/app:/app/app:ro" -w /app "$image" \
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
