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

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

cmd_build() {
  log "Building $DEV_SERVER_IMAGE (version $(version), with the panel) ..."
  build_server_image "$ROOT" "$DEV_SERVER_IMAGE"
  log "Built $DEV_SERVER_IMAGE."
}

verify_stack() {
  local ok=0
  wait_healthy "$DEV_DB_CONTAINER" || ok=1
  wait_healthy "$DEV_SERVER_CONTAINER" || ok=1
  verify_container_image "$DEV_SERVER_CONTAINER" "$DEV_SERVER_IMAGE" || ok=1
  if ((ok != 0)); then
    err "The stack is up but verification failed. See above."
    exit 1
  fi
  log "Stack is healthy. Panel and API: $DEV_URL"
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
  require_dev_stack
  if [[ "$build" == true ]]; then
    cmd_build
  fi
  if ! docker image inspect "$DEV_SERVER_IMAGE" >/dev/null 2>&1; then
    err "$DEV_SERVER_IMAGE does not exist. Run: scripts/local.sh up -b"
    exit 1
  fi
  log "Starting $DEV_PROJECT from $DEV_COMPOSE_FILE ..."
  if [[ "$detach" == true ]]; then
    dev_compose up -d --remove-orphans
    verify_stack
  else
    warn "Foreground mode: health and image verification run only with -d."
    dev_compose up --remove-orphans
  fi
}

cmd_down() {
  require_dev_stack
  dev_compose down --remove-orphans
  log "Containers removed. The database volume $DEV_DB_VOLUME is kept."
}

cmd_status() {
  require_dev_stack
  dev_compose ps
  echo
  local name
  for name in "$DEV_SERVER_CONTAINER" "$DEV_DB_CONTAINER"; do
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
  require_dev_stack
  if ! docker volume inspect "$DEV_DB_VOLUME" >/dev/null 2>&1; then
    warn "Volume $DEV_DB_VOLUME does not exist. Removing containers only."
    dev_compose down --remove-orphans
    exit 0
  fi
  warn "This stops the stack and DELETES the development database volume $DEV_DB_VOLUME."
  local confirm
  read -r -p "Type nuke to confirm: " confirm
  if [[ "$confirm" != "nuke" ]]; then
    log "Cancelled. Nothing changed."
    exit 0
  fi
  dev_compose down --remove-orphans --volumes
  if docker volume inspect "$DEV_DB_VOLUME" >/dev/null 2>&1; then
    err "$DEV_DB_VOLUME still exists after the delete."
    exit 1
  fi
  log "Deleted $DEV_DB_VOLUME. The next start creates a fresh database."
}

# A debug APK of the client, for a phone or an emulator. Debug builds are
# signed with the SDK's debug key; release signing lives in CI only.
cmd_apk() {
  log "Building the debug APK (version $(version)) ..."
  flutter_run "flutter pub get --enforce-lockfile >/dev/null && flutter build apk --debug --build-name=$(version)"
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
