#!/usr/bin/env bash
#
# local.sh - the local development stack (server with the panel, PostgreSQL).
#
#   scripts/local.sh build          build tildeck-server:dev (includes the panel)
#   scripts/local.sh up [-b] [-d]   start (-b: build first, -d: detached and verified)
#   scripts/local.sh down           stop and remove the containers, keep the data
#   scripts/local.sh status         containers, health, running image, runtime UID
#   scripts/local.sh nuke           down, then DELETE the database volume (asks first)
#   scripts/local.sh apk            build a debug Android APK into out/
#   scripts/local.sh contract       re-export server/openapi.json, regenerate the Dart client
#
# Drives ONLY the machine-local docker-compose-dev.yml at the repository root
# and never falls back to the production docker-compose.yml. Compose never
# builds: the development image is built here, explicitly, with the version
# from the repo-root VERSION file.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT"

COMPOSE_FILE="docker-compose-dev.yml"
COMPOSE_TEMPLATE="docs/development/docker-compose-dev.example.yml"
ENV_FILE=".env"
PROJECT="tildeck-dev"
SERVER_IMAGE="tildeck-server:dev"
SERVER_CONTAINER="tildeck-server-dev"
DB_CONTAINER="tildeck-postgres-dev"
DB_VOLUME="tildeck-db-data"
HEALTH_TIMEOUT=120

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

require_files() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "$COMPOSE_FILE is missing. It is machine-local; create it from the template:"
    err "  cp $COMPOSE_TEMPLATE $COMPOSE_FILE"
    exit 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    err "$ENV_FILE is missing. Create it from the example:"
    err "  cp .env.example $ENV_FILE"
    exit 1
  fi
}

compose() {
  docker compose -p "$PROJECT" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

cmd_build() {
  local v
  v="$(version)"
  log "Building $SERVER_IMAGE (version $v, with the panel) ..."
  docker build \
    --build-context panel=./panel \
    --build-arg "APP_VERSION=$v" \
    --target runtime \
    -f server/Dockerfile \
    -t "$SERVER_IMAGE" \
    ./server
  log "Built $SERVER_IMAGE."
}

# Health of a container as Docker reports it: healthy, unhealthy, starting,
# or "none" when the container has no health check or does not exist.
health_of() {
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$1" 2>/dev/null || echo "none"
}

wait_healthy() {
  local name="$1" waited=0 status
  while ((waited < HEALTH_TIMEOUT)); do
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
  err "$name did not become healthy within ${HEALTH_TIMEOUT}s (status: $(health_of "$name"))."
  docker logs --tail 30 "$name" >&2 || true
  return 1
}

# The effective UID of the container's main process (PID 1). Not `id -u`
# through docker exec, which reports the exec session's user: the postgres
# image starts as root and drops to postgres, so only PID 1 tells the truth.
process_uid() {
  docker exec "$1" cat /proc/1/status 2>/dev/null | awk '/^Uid:/ { print $3; found = 1 } END { if (!found) print "unknown" }'
}

# The server container must run the image that was just built (by id), not a
# stale one, and its application process must not run as root.
verify_server() {
  local built running uid
  built="$(docker inspect --format '{{.Id}}' "$SERVER_IMAGE" 2>/dev/null || true)"
  running="$(docker inspect --format '{{.Image}}' "$SERVER_CONTAINER" 2>/dev/null || true)"
  if [[ -z "$built" || "$built" != "$running" ]]; then
    err "$SERVER_CONTAINER does not run the current $SERVER_IMAGE (built: ${built:0:19}, running: ${running:0:19})."
    return 1
  fi
  uid="$(process_uid "$SERVER_CONTAINER")"
  if [[ "$uid" == "0" || "$uid" == "unknown" ]]; then
    err "$SERVER_CONTAINER runs as UID $uid. Application containers must not run as root."
    return 1
  fi
  log "verified: $SERVER_CONTAINER runs $SERVER_IMAGE (${built:7:12}) as UID $uid"
}

verify_stack() {
  local ok=0
  wait_healthy "$DB_CONTAINER" || ok=1
  wait_healthy "$SERVER_CONTAINER" || ok=1
  verify_server || ok=1
  if ((ok != 0)); then
    err "The stack is up but verification failed. See above."
    exit 1
  fi
  log "Stack is healthy. Panel and API: http://localhost:8280"
}

cmd_up() {
  local build=false detach=false opt
  while getopts "bd" opt; do
    case "$opt" in
      b) build=true ;;
      d) detach=true ;;
      *) usage ;;
    esac
  done
  require_files
  if [[ "$build" == true ]]; then
    cmd_build
  fi
  if ! docker image inspect "$SERVER_IMAGE" >/dev/null 2>&1; then
    err "$SERVER_IMAGE does not exist. Run: scripts/local.sh up -b"
    exit 1
  fi
  log "Starting $PROJECT from $COMPOSE_FILE ..."
  if [[ "$detach" == true ]]; then
    compose up -d --remove-orphans
    verify_stack
  else
    warn "Foreground mode: health and image verification run only with -d."
    compose up --remove-orphans
  fi
}

cmd_down() {
  require_files
  compose down --remove-orphans
  log "Containers removed. The database volume $DB_VOLUME is kept."
}

cmd_status() {
  require_files
  compose ps
  echo
  local name
  for name in "$SERVER_CONTAINER" "$DB_CONTAINER"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      printf '  %-22s image %-60s health %-10s uid %s\n' "$name" \
        "$(docker inspect --format '{{.Config.Image}} ({{slice .Image 7 19}})' "$name")" \
        "$(health_of "$name")" \
        "$(process_uid "$name")"
    else
      printf '  %-22s not running\n' "$name"
    fi
  done
  echo
  docker images --format '  {{.Repository}}:{{.Tag}}  {{.ID}}  {{.CreatedSince}}' "tildeck-server"
}

# nuke removes exactly the development database volume, after the word
# "nuke" is typed in full.
cmd_nuke() {
  require_files
  if ! docker volume inspect "$DB_VOLUME" >/dev/null 2>&1; then
    warn "Volume $DB_VOLUME does not exist. Removing containers only."
    compose down --remove-orphans
    exit 0
  fi
  warn "This stops the stack and DELETES the development database volume $DB_VOLUME."
  local confirm
  read -r -p "Type nuke to confirm: " confirm
  if [[ "$confirm" != "nuke" ]]; then
    log "Cancelled. Nothing changed."
    exit 0
  fi
  compose down --remove-orphans --volumes
  if docker volume inspect "$DB_VOLUME" >/dev/null 2>&1; then
    err "$DB_VOLUME still exists after the delete."
    exit 1
  fi
  log "Deleted $DB_VOLUME. The next start creates a fresh database."
}

# A debug APK of the client, for a phone or an emulator. Debug builds are
# signed with the SDK's debug key; release signing lives in CI only.
cmd_apk() {
  log "Building the debug APK (version $(version)) ..."
  flutter_run "flutter pub get >/dev/null && flutter build apk --debug --build-name=$(version)"
  mkdir -p out
  cp app/build/app/outputs/flutter-apk/app-debug.apk out/tildeck-debug.apk
  log "Built out/tildeck-debug.apk"
}

# The client and server contract: the committed OpenAPI document is exported
# from the server code, and the Dart client is generated from it. Commit
# server/openapi.json and app/packages/tildeck_api together with the server
# change. scripts/verify.sh fails when either is out of date.
cmd_contract() {
  local spec
  log "Exporting server/openapi.json ..."
  spec="$(export_openapi)"
  printf '%s\n' "$spec" >server/openapi.json
  log "Generating app/packages/tildeck_api ..."
  generate_api_client server/openapi.json app/packages/tildeck_api
  git status --short -- server/openapi.json app/packages/tildeck_api
  log "Contract regenerated. Commit the changes above together with the server change."
}

COMMAND="${1:-}"
[[ -n "$COMMAND" ]] && shift
case "$COMMAND" in
  build) cmd_build ;;
  up) cmd_up "$@" ;;
  down) cmd_down ;;
  status) cmd_status ;;
  nuke) cmd_nuke ;;
  apk) cmd_apk ;;
  contract) cmd_contract ;;
  "" | -h | --help | help) usage ;;
  *)
    err "Unknown command: $COMMAND"
    usage
    ;;
esac
