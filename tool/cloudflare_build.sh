#!/usr/bin/env bash
#
# Cloudflare build for the SPD console.
#
# The build image ships Node and Python but no Flutter SDK, so this fetches a
# pinned one, builds the web bundle, and leaves it in build/web.
#
# This is the *build* half only. The deploy is `npx wrangler deploy`, and which
# directory it ships is decided by wrangler.jsonc at the repo root — not by
# anything here and not by the dashboard. Left to auto-detect, wrangler picks
# the source `web/` folder and deploys the Flutter template with no app in it.
#
#   Build command    bash tool/cloudflare_build.sh
#   Deploy command   npx wrangler deploy
#
# SPD_API is the full API root the bundle is compiled against. Flutter resolves
# --dart-define at build time, not at runtime, so changing where the API lives
# means a fresh deploy — it cannot be flipped from the dashboard without one.
# It defaults to the CRM host, where SPD is mounted as the `spd` module.

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.7}"
SPD_API="${SPD_API:-https://api.vistarlogitek.com/api/v1/spd}"
FLUTTER_DIR="${PWD}/.flutter-sdk"

echo "==> SPD console"
echo "    flutter   ${FLUTTER_VERSION}"
echo "    api root  ${SPD_API}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "==> fetching Flutter ${FLUTTER_VERSION}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

# The SDK lands in a container that has never seen this checkout, and Flutter
# shells out to git on every command; without this it aborts on git's
# dubious-ownership check before it builds anything.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --web
flutter pub get

# --no-web-resources-cdn is not optional here, and it is not sticky: without it
# the engine fetches CanvasKit from www.gstatic.com at runtime and the console
# does not start on a table device with no route off the LAN. The mirrored
# fonts in web/fallback-fonts/ exist for the same reason. See "Running offline"
# in README.md.
flutter build web --release --no-web-resources-cdn --dart-define=SPD_API="${SPD_API}"

echo "==> build/web"
ls -la build/web
