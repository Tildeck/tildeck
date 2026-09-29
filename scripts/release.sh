#!/usr/bin/env bash
#
# release.sh - cut a release: verify, set the version, close the changelog,
# commit, and tag. Publication happens in CI, from the tag.
#
#   scripts/release.sh [--dry-run]                     show every step, change nothing (default)
#   scripts/release.sh --bump patch|minor|major        release the next version
#
# VERSION holds the last released version between releases; pull requests do
# not touch it. The bump is the explicit target of a real run: without it
# nothing is released. The version is written to VERSION and to
# app/pubspec.yaml (with an Android build number derived from it, so it
# always increases), and CHANGELOG.md's Unreleased section becomes the new
# version's section.
#
# The tag vX.Y.Z triggers .github/workflows/publish.yml, which verifies again
# and publishes the server image to GHCR, the Android APK, and the Windows
# package as a GitHub Release with that version's changelog section. Nothing
# is built or published from this machine. Never force-pushes, never stages
# anything but the release files, never rewrites a published version.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$ROOT"

step() { printf '\033[1m-> %s\033[0m\n' "$*"; }

# A stdlib Python snippet from stdin with arguments. The host needs only
# Docker, so an installed python3 is used when present, else the pinned
# image, as the calling user so written files are not owned by root.
python_run() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$@"
  else
    docker run --rm -i -v "$ROOT:/repo" -w /repo --user "$(id -u):$(id -g)" \
      "$(toolchain_image python)" python3 - "$@"
  fi
}

DRY_RUN=true
BUMP=""
while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --bump)
      BUMP="${2:-}"
      DRY_RUN=false
      shift
      ;;
    -h | --help)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      exit 2
      ;;
  esac
  shift
done
if [[ "$DRY_RUN" == false && ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  err "--bump must be patch, minor, or major (got: '$BUMP')."
  exit 2
fi

# --- Preflight ---------------------------------------------------------------
# Every problem is collected. A dry run reports them and still shows the
# plan; a real run stops.

step "preflight"
PROBLEMS=()
branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == main ]] || PROBLEMS+=("Releases are cut from main (current branch: $branch).")
[[ -z "$(git status --porcelain)" ]] || PROBLEMS+=("The working tree is not clean. Commit or stash first.")
if git remote get-url origin >/dev/null 2>&1; then
  if git fetch --quiet origin main --tags; then
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
      || PROBLEMS+=("Local main differs from origin/main. Pull or push first.")
  else
    PROBLEMS+=("Could not fetch origin.")
  fi
else
  PROBLEMS+=("This checkout has no origin remote to push the release to.")
fi
gh auth status >/dev/null 2>&1 || PROBLEMS+=("gh is not authenticated (gh auth status failed).")

current="$(version)"
if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  err "VERSION does not hold a semantic version: '$current'"
  exit 1
fi
IFS=. read -r major minor patch <<<"$current"
case "${BUMP:-patch}" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  patch) next="$major.$minor.$((patch + 1))" ;;
esac
IFS=. read -r nmajor nminor npatch <<<"$next"
# Android needs an integer that grows with every release.
build_number="$((nmajor * 1000000 + nminor * 1000 + npatch))"
tag="v$next"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null \
  || { git remote get-url origin >/dev/null 2>&1 && git ls-remote --exit-code --tags origin "$tag" >/dev/null 2>&1; }; then
  PROBLEMS+=("Tag $tag already exists. A published version is never rewritten.")
fi
unreleased="$(awk '/^## Unreleased/ { on = 1; next } /^## / { on = 0 } on && NF' CHANGELOG.md)"
[[ -n "$unreleased" ]] || PROBLEMS+=("CHANGELOG.md has nothing under '## Unreleased' to release.")

if ((${#PROBLEMS[@]} > 0)); then
  for p in "${PROBLEMS[@]}"; do
    if [[ "$DRY_RUN" == true ]]; then warn "  would stop: $p"; else err "  $p"; fi
  done
  [[ "$DRY_RUN" == true ]] || exit 1
else
  log "on main, clean, in sync with origin, gh authenticated, $tag is free"
fi

# --- Plan --------------------------------------------------------------------

today="$(date +%F)"
step "plan${BUMP:+ ($BUMP)}"
cat <<PLAN
  1. scripts/verify.sh                          full verification
  2. VERSION: $current -> $next
  3. app/pubspec.yaml: version $next+$build_number
  4. CHANGELOG.md: '## Unreleased' becomes '## $next ($today)', a new empty Unreleased above it
  5. git commit -m "Release version $next"      (VERSION, app/pubspec.yaml, CHANGELOG.md only)
  6. git tag -a $tag -m "Release version $next"
  7. git push origin main, then git push origin $tag   (no force)
  8. CI (publish.yml): verify, server image to GHCR, APK and Windows package to a GitHub Release
PLAN

if [[ "$DRY_RUN" == true ]]; then
  if [[ -z "$BUMP" ]]; then
    warn "Dry run: nothing changed. The patch bump is shown; pass --bump patch|minor|major to release."
  else
    warn "Dry run: nothing changed."
  fi
  exit 0
fi

# --- Execute -----------------------------------------------------------------

step "1/7 verify"
bash scripts/verify.sh

step "2/7 VERSION"
printf '%s\n' "$next" >VERSION

step "3/7 app/pubspec.yaml and 4/7 CHANGELOG.md"
python_run "$next" "$build_number" "$today" <<'PY'
import re
import sys

version, build, today = sys.argv[1:4]

path = "app/pubspec.yaml"
text = open(path, encoding="utf-8").read()
text, n = re.subn(r"^version: .*$", f"version: {version}+{build}", text, count=1, flags=re.M)
if n != 1:
    sys.exit("app/pubspec.yaml has no version line")
open(path, "w", encoding="utf-8", newline="\n").write(text)

path = "CHANGELOG.md"
text = open(path, encoding="utf-8").read()
text, n = re.subn(r"^## Unreleased\s*$", f"## Unreleased\n\n## {version} ({today})", text, count=1, flags=re.M)
if n != 1:
    sys.exit("CHANGELOG.md has no Unreleased heading")
open(path, "w", encoding="utf-8", newline="\n").write(text)
PY

step "5/7 commit"
git add VERSION app/pubspec.yaml CHANGELOG.md
git commit -m "Release version $next"

step "6/7 tag"
git tag -a "$tag" -m "Release version $next"

step "7/7 push"
git push origin main
git push origin "$tag"

log "Pushed $tag. The release is complete when the publish workflow succeeds:"
log "  gh run list --workflow publish.yml"
log "  gh release view $tag"
