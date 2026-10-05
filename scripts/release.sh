#!/usr/bin/env bash
# One-command Sparkle release: build, zip, sign, add an appcast item, publish a GitHub Release, push the appcast.
#
#   scripts/release.sh <version> --notes <file> [--beta] [--dry-run]
#
# <version> is SemVer (betas are X.Y.Z-beta.N and need --beta; --beta needs one) and must be newer than every version in
# appcast.xml. <file> holds the release notes as Markdown; it feeds both the appcast item and the GitHub Release.
# --dry-run builds, zips and signs, then prints the new appcast item. It skips the branch and sync checks and every
# publish step (gh release, commit, push), and leaves appcast.xml and git untouched. The zip stays in dist/.
#
# Run it on your Mac, in a logged-in session: build-app.sh signs with the keychain identity, and sign_update reads
# the Sparkle EdDSA private key from the same login keychain (it may prompt). Needs xcodegen, python3, xmllint,
# and gh (authenticated) unless --dry-run.
set -euo pipefail

REPO="prabeshbhetwal/tessera"
# Dedicated derived data: the build resolves Sparkle here, which also provides bin/sign_update.
DERIVED="$HOME/Library/Caches/tessera-build/dd-release"

usage() { echo "usage: scripts/release.sh <version> --notes <file> [--beta] [--dry-run]" >&2; exit 2; }
die() { echo "release: $*" >&2; exit 1; }
step() { echo "==> $*"; }

VERSION="" NOTES="" BETA=0 DRY=0
while (( $# )); do
  case "$1" in
    --notes) (( $# >= 2 )) || usage; NOTES="$2"; shift 2 ;;
    --beta) BETA=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -*) usage ;;
    *) [[ -z "$VERSION" ]] || usage; VERSION="$1"; shift ;;
  esac
done
[[ -n "$VERSION" && -n "$NOTES" ]] || usage
[[ -s "$NOTES" ]] || die "notes file missing or empty: $NOTES"
NOTES="$(realpath "$NOTES")"

cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step "Checking working tree and branch"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean; commit or stash first"
if (( ! DRY )); then
  BRANCH="$(git branch --show-current)"
  [[ "$BRANCH" == main ]] || die "releases are cut from main (on '$BRANCH'); use --dry-run to rehearse elsewhere"
  # The release tag lands on origin's main, so what is built must be exactly what is pushed.
  git fetch --quiet origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "local main differs from origin/main; push or pull first"
  command -v gh >/dev/null || die "gh (GitHub CLI) is not installed"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"
  # gh release create would reuse an existing tag wherever it points. ls-remote exits 2 when no ref matches.
  rc=0; git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null || rc=$?
  (( rc == 2 )) || die "tag v$VERSION already exists on origin (or origin is unreachable); pick a new version"
fi

step "Checking version $VERSION"
# Exits non-zero with a message unless it is SemVer and newer than everything in the appcast.
python3 scripts/appcast_add_item.py --appcast appcast.xml --version "$VERSION" --check-newer
if [[ "$VERSION" == *-* ]] && (( ! BETA )); then
  die "pre-release $VERSION needs --beta, otherwise it would reach every user"
fi
if [[ "$VERSION" != *-* ]] && (( BETA )); then
  die "--beta needs a pre-release version such as $VERSION-beta.1; stable $VERSION would reach only beta users"
fi

step "Building Tessera $VERSION (Release)"
# build-app.sh prints the .app path on its last line; show the rest only if the build fails.
if ! CONFIGURATION=Release TESSERA_DERIVED_DATA="$DERIVED" TESSERA_VERSION="$VERSION" \
    scripts/build-app.sh >"$WORK/build.out"; then
  cat "$WORK/build.out" >&2
  die "build failed"
fi
APP="$(tail -1 "$WORK/build.out")"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
[[ "$(plist CFBundleShortVersionString)" == "$VERSION" ]] \
  || die "built app reports version $(plist CFBundleShortVersionString), expected $VERSION"
BUILD="$(plist CFBundleVersion)"
MIN_SYSTEM="$(plist LSMinimumSystemVersion)"
# build-app.sh falls back to ad-hoc signing without a word, and Sparkle would still install that build: everyone
# who updated would lose Tessera's Accessibility grant. (No grep -q: exiting early could SIGPIPE codesign.)
IDENTITY="${TESSERA_SIGN_IDENTITY:-Tessera Local Signing}"
codesign -dvv "$APP" 2>&1 | grep -x "Authority=$IDENTITY" >/dev/null \
  || die "the build is not signed by \"$IDENTITY\" (ad-hoc fallback?), so updating would cost every user the" \
    "Accessibility grant; run this in a logged-in session whose login keychain has that identity"

step "Archiving $APP"
mkdir -p dist
ZIP="dist/Tessera-$VERSION.zip"
rm -f "$ZIP"
# --sequesterRsrc (as Sparkle's docs recommend) puts extended attributes under __MACOSX/ instead of ._ files inside
# the bundle, which a plain unzip would otherwise leave next to the signed code.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

step "Signing $ZIP"
SIGN_UPDATE="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || die "sign_update not found at $SIGN_UPDATE; the build should have resolved Sparkle there"
SIGNED="$("$SIGN_UPDATE" "$ZIP")" || die "sign_update failed; is the Sparkle EdDSA key in the login keychain?"
# Output looks like: sparkle:edSignature="..." length="1234"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNED")"
LENGTH="$(sed -n 's/.* length="\([0-9]*\)".*/\1/p' <<<"$SIGNED")"
[[ -n "$SIGNATURE" && -n "$LENGTH" ]] || die "could not parse sign_update output: $SIGNED"

step "Adding appcast item"
# Work on a copy: appcast.xml only changes once the release exists.
cp appcast.xml "$WORK/appcast.xml"
ITEM_ARGS=(--appcast "$WORK/appcast.xml" --version "$VERSION" --build "$BUILD" --min-system "$MIN_SYSTEM"
  --url "https://github.com/$REPO/releases/download/v$VERSION/Tessera-$VERSION.zip"
  --length "$LENGTH" --signature "$SIGNATURE" --notes-file "$NOTES")
if (( BETA )); then ITEM_ARGS+=(--channel beta); fi
python3 scripts/appcast_add_item.py "${ITEM_ARGS[@]}"
xmllint --noout "$WORK/appcast.xml"

if (( DRY )); then
  step "Dry run: new appcast item (appcast.xml and git untouched; archive left at $ZIP)"
  xmllint --xpath '(//item)[1]' "$WORK/appcast.xml"
  echo
  exit 0
fi

step "Publishing GitHub release v$VERSION"
# --target: the tag lands on the commit that was built, not on whatever main is when GitHub creates it.
RELEASE_ARGS=(--repo "$REPO" --target "$(git rev-parse HEAD)" --title "Tessera $VERSION" --notes-file "$NOTES")
if (( BETA )); then RELEASE_ARGS+=(--prerelease); fi
gh release create "v$VERSION" "$ZIP" "${RELEASE_ARGS[@]}"

step "Committing and pushing appcast.xml"
cp "$WORK/appcast.xml" appcast.xml
RECOVER="release v$VERSION is live, but appcast.xml has not reached origin/main, so no one is offered it yet."
RECOVER+=" To finish: commit appcast.xml (if git status shows it modified), then run: git push origin main"
git commit -m "chore(release): Tessera $VERSION appcast" appcast.xml || die "$RECOVER"
git push origin main || die "$RECOVER"

step "Released Tessera $VERSION: https://github.com/$REPO/releases/tag/v$VERSION"
