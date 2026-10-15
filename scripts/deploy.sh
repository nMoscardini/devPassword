#!/bin/bash
# devPassword deploy: build the signed Release app and install it in /Applications.
# Refuses unless the smoke test passes and everything is committed, so the installed app
# is always a known commit. The vault is not touched: it lives in Application Support.
# Keeps the previous app in dist/previous so a bad deploy can be rolled back.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APPS=/Applications
DIST="$ROOT/dist"
mkdir -p logs "$DIST"
LOG=logs/deploy-latest.log
: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
fail() { say "DEPLOY FAILED - $*"; exit 1; }

say "== $(date '+%Y-%m-%d %H:%M:%S') deploy"
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes. Commit first, so the installed app matches a commit."
COMMIT=$(git rev-parse --short HEAD)

say "== smoke"
scripts/smoke.sh > /dev/null 2>&1
[ "$(tail -1 logs/smoke-latest.log)" = "SMOKE PASSED" ] || fail "smoke test did not pass. See logs/smoke-latest.log"

say "== build Release ($COMMIT)"
BUILD=$(mktemp -d /tmp/devpassword-build.XXXXXX)
xcodebuild -project App/devPassword/devPassword.xcodeproj -scheme devPassword \
    -configuration Release -derivedDataPath "$BUILD" build >> "$LOG" 2>&1 \
    || fail "xcodebuild failed. See $LOG"
APP="$BUILD/Build/Products/Release/devPassword.app"
[ -d "$APP" ] || fail "no app at $APP"

say "== check signature"
codesign --verify --deep --strict "$APP" >> "$LOG" 2>&1 || fail "signature does not verify"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "keychain-access-groups" \
    || fail "keychain entitlement missing: Touch ID would not work"
codesign -dv "$APP" 2>&1 | grep -E "Authority=|TeamIdentifier=" | tee -a "$LOG"

say "== install"
osascript -e 'tell application id "com.nino.devPassword" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq devPassword || break; sleep 0.5; done
pgrep -xq devPassword && fail "devPassword is still running (maybe from Xcode). Quit it and run again."
if [ -d "$APPS/devPassword.app" ]; then
    rm -rf "$DIST/previous"
    mkdir -p "$DIST/previous"
    ditto "$APPS/devPassword.app" "$DIST/previous/devPassword.app" || fail "could not keep the previous app"
    rm -rf "$APPS/devPassword.app"
fi
ditto "$APP" "$APPS/devPassword.app" || fail "could not copy to $APPS"
echo "$COMMIT $(date '+%Y-%m-%d %H:%M:%S')" > "$DIST/DEPLOYED"
rm -rf "$BUILD"
# Register the installed copy so Launch Services stops opening Xcode's build.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APPS/devPassword.app" >/dev/null 2>&1 || true
open "$APPS/devPassword.app"
say "DEPLOYED $COMMIT to $APPS/devPassword.app"
