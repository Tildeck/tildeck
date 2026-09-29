#!/usr/bin/env bash
#
# try-pr.sh - try a pull request against the local development stack, then
# put the stack back on your working tree.
#
#   scripts/try-pr.sh <PR-number>      preview an open pull request
#   scripts/try-pr.sh --ref <git-ref>  preview any branch or commit the same way
#   scripts/try-pr.sh status           what the development stack runs now
#   scripts/try-pr.sh restore          back to your working tree and database
#
# The change is checked out into a disposable worktree outside this checkout
# (under ~/.cache/tildeck-try-pr), and only the affected areas are rebuilt:
#   server/ or panel/  the server image is rebuilt and only the server
#                      container restarts, against the existing development
#                      database. When server/ changes, the database is
#                      snapshotted first (pg_dump), because the change may
#                      migrate it; restore puts that snapshot back.
#   app/               a debug APK is built and its path is reported.
#
# Never merges, never pushes, never edits your working tree.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT"

STATE_DIR="${TILDECK_TRY_PR_DIR:-$HOME/.cache/tildeck-try-pr}"
WT_DIR="$STATE_DIR/wt"
ACTIVE_FILE="$STATE_DIR/active"
SNAPSHOT_FILE="$STATE_DIR/db-before-preview.dump"

usage() {
  sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

remove_worktree() {
  git worktree remove --force "$WT_DIR" >/dev/null 2>&1 || true
  git worktree prune
  rm -rf "$WT_DIR"
}

db_revision() {
  # shellcheck disable=SC2016
  docker exec "$DEV_DB_CONTAINER" sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select version_num from alembic_version"' 2>/dev/null \
    | tr -d '[:space:]' || true
}

snapshot_database() {
  log "Snapshotting the development database (migration $(db_revision)) ..."
  # shellcheck disable=SC2016
  docker exec "$DEV_DB_CONTAINER" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' >"$SNAPSHOT_FILE.tmp"
  mv "$SNAPSHOT_FILE.tmp" "$SNAPSHOT_FILE"
  log "Snapshot: $SNAPSHOT_FILE ($(du -h "$SNAPSHOT_FILE" | cut -f1))"
}

# Replace the database with the snapshot. The server is stopped first so
# nothing holds a connection or writes in between.
restore_database() {
  log "Restoring the development database from the snapshot ..."
  dev_compose stop server
  # shellcheck disable=SC2016
  docker exec "$DEV_DB_CONTAINER" sh -c \
    'dropdb -U "$POSTGRES_USER" --force "$POSTGRES_DB" && createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
  # shellcheck disable=SC2016
  docker exec -i "$DEV_DB_CONTAINER" sh -c \
    'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --exit-on-error' <"$SNAPSHOT_FILE"
  log "Database restored (migration $(db_revision))."
}

# Rebuild the server image from a tree, restart only the server container
# (--no-deps leaves the database running), and verify it.
deploy_server() {
  local src="$1"
  build_server_image "$src" "$DEV_SERVER_IMAGE"
  dev_compose up -d --no-deps --force-recreate server
  wait_healthy "$DEV_SERVER_CONTAINER"
  verify_container_image "$DEV_SERVER_CONTAINER" "$DEV_SERVER_IMAGE"
}

cmd_status() {
  if [[ -f "$ACTIVE_FILE" ]]; then
    warn "The development stack runs $(cat "$ACTIVE_FILE"), not your working tree."
    warn "Run 'scripts/try-pr.sh restore' to put it back."
  else
    log "The development stack runs your working tree (no preview active)."
  fi
  if [[ -f "$SNAPSHOT_FILE" ]]; then
    log "A database snapshot from before the preview is kept: $SNAPSHOT_FILE"
  fi
  if docker inspect "$DEV_SERVER_CONTAINER" >/dev/null 2>&1; then
    log "Server: $(docker inspect --format '{{.Config.Image}} ({{slice .Image 7 19}})' "$DEV_SERVER_CONTAINER"), health $(health_of "$DEV_SERVER_CONTAINER"), database migration $(db_revision)"
  fi
}

cmd_restore() {
  require_dev_stack
  if [[ ! -f "$ACTIVE_FILE" && ! -f "$SNAPSHOT_FILE" ]]; then
    log "No preview is active. Nothing to restore."
    remove_worktree
    return 0
  fi
  log "Restoring the development stack to your working tree ..."
  if [[ -f "$SNAPSHOT_FILE" ]]; then
    restore_database
  fi
  deploy_server "$ROOT"
  remove_worktree
  rm -f "$ACTIVE_FILE" "$SNAPSHOT_FILE"
  log "Done. The development stack runs your working tree and its database is as it was."
}

# $1: a git ref to preview. $2: a label for messages and status.
cmd_preview() {
  local ref="$1" label="$2" base changed server panel app
  require_dev_stack
  if [[ -f "$ACTIVE_FILE" ]]; then
    warn "The development stack already runs $(cat "$ACTIVE_FILE"). Restoring first ..."
    cmd_restore
  fi
  if ! docker inspect "$DEV_DB_CONTAINER" >/dev/null 2>&1; then
    err "The development stack is not running. Start it first: scripts/local.sh up -d"
    exit 1
  fi

  base="$(git merge-base "$ref" "$(git rev-parse --verify -q origin/main >/dev/null && echo origin/main || echo main)")"
  changed="$(git diff --name-only "$base" "$ref")"
  server="$(grep -c '^server/' <<<"$changed" || true)"
  panel="$(grep -c '^panel/' <<<"$changed" || true)"
  app="$(grep -c '^app/' <<<"$changed" || true)"
  log "$label: $(wc -l <<<"$changed" | tr -d ' ') changed files (server: $server, panel: $panel, app: $app)"
  if ((server == 0 && panel == 0 && app == 0)); then
    warn "This change touches neither server/, panel/, nor app/. Nothing to run."
    return 0
  fi

  mkdir -p "$STATE_DIR"
  remove_worktree
  git worktree add --detach "$WT_DIR" "$ref" >/dev/null
  log "Checked out into $WT_DIR (your working tree is untouched)."

  if ((server > 0 || panel > 0)); then
    printf '%s\n' "$label" >"$ACTIVE_FILE"
    if ((server > 0)); then snapshot_database; fi
    deploy_server "$WT_DIR"
    log "The server now runs $label at $DEV_URL"
  fi
  if ((app > 0)); then
    log "Building the debug APK of $label ..."
    FLUTTER_SRC="$WT_DIR" flutter_run "flutter pub get --enforce-lockfile >/dev/null && flutter build apk --debug"
    cp "$WT_DIR/app/build/app/outputs/flutter-apk/app-debug.apk" "$STATE_DIR/tildeck-preview-debug.apk"
    log "APK: $STATE_DIR/tildeck-preview-debug.apk"
  fi
  if [[ -f "$ACTIVE_FILE" ]]; then
    log "When done: scripts/try-pr.sh restore"
  else
    remove_worktree
  fi
}

case "${1:-}" in
  "" | -h | --help | help) usage 0 ;;
  status) cmd_status ;;
  restore) cmd_restore ;;
  --ref)
    [[ -n "${2:-}" ]] || usage 2
    ref="$(git rev-parse --verify "$2^{commit}")"
    cmd_preview "$ref" "ref $2 (${ref:0:12})"
    ;;
  *)
    if [[ ! "$1" =~ ^[0-9]+$ ]]; then
      err "Unknown argument: $1"
      usage 2
    fi
    if ! git remote get-url origin >/dev/null 2>&1; then
      err "This checkout has no origin remote to fetch pull requests from."
      exit 1
    fi
    # The pull request's head, forks included, into a private ref.
    git fetch --quiet origin "+refs/pull/$1/head:refs/try-pr/$1"
    git fetch --quiet origin main
    cmd_preview "refs/try-pr/$1" "PR #$1"
    ;;
esac
