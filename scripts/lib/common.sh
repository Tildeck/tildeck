# shellcheck shell=bash
#
# Shared by the workflow scripts: sourced, never run. Sets ROOT to the
# repository root and provides logging, the pinned toolchain images, and the
# steps more than one script needs (Flutter in a container, the API contract).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }

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

# Run a shell command in the Flutter toolchain container, in app/. Caches
# survive between runs in named volumes: pub packages, Gradle, and the NDK
# and CMake that the Android build installs into the SDK on first use.
flutter_run() {
  local image
  image="$(toolchain_image flutter)"
  docker run --rm \
    -v "$ROOT:/work" -w /work/app \
    -v tildeck-pub-cache:/root/.pub-cache \
    -v tildeck-gradle-cache:/root/.gradle \
    -v tildeck-android-ndk:/opt/android-sdk-linux/ndk \
    -v tildeck-android-cmake:/opt/android-sdk-linux/cmake \
    -e PUB_CACHE=/root/.pub-cache \
    "$image" bash -c "flutter config --no-analytics >/dev/null 2>&1; set -e; $1"
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
  docker run --rm -v "$ROOT:/work" "$image" generate \
    -i "/work/$spec" -g dart -o "/work/$out" \
    --additional-properties=pubName=tildeck_api,pubDescription="Tildeck server API client generated from server/openapi.json",pubAuthor=Tildeck,pubHomepage=https://tildeck.com \
    --global-property=apiTests=false,modelTests=false,apiDocs=false,modelDocs=false \
    >/dev/null
  # On a Windows drive under WSL, replacing a directory tree that a
  # container just wrote leaves this shell's working directory handle stale
  # ("Unable to read current working directory"). Re-enter it by path.
  cd "$ROOT"
}
