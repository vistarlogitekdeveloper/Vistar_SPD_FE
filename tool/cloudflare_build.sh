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
#
# It defaults to UAT. Production only ever runs a commit that has already run on
# UAT (docs/PROMOTION.md in the CRM), and a console pointed at production while
# its backend changes are still being signed off tests nothing — it exercises
# code that is not the code under review. Set SPD_API in the Cloudflare
# environment to point a build at production:
#
#   SPD_API=https://api.vistarlogitek.com/api/v1/spd

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.7}"
SPD_API="${SPD_API:-https://uat-api.vistarlogitek.com/api/v1/spd}"
FLUTTER_DIR="${PWD}/.flutter-sdk"

echo "==> SPD console"
echo "    flutter   ${FLUTTER_VERSION}"
echo "    api root  ${SPD_API}"

# The API root is checked before anything is compiled, because getting it wrong
# is both easy and invisible until nobody can sign in.
#
# This default was `https://uat-api.vistarlogitek.com/v1/spd` for several
# deploys — the `/api` dropped out of it — and the console went out with every
# request 404ing. Nothing failed: the build was green, the bundle was valid,
# wrangler shipped it, and the first sign of trouble was a supervisor being
# told "Request failed (404)". A wrong URL that fails at build time costs
# minutes; one that fails at run time costs a shift.
#
# The CRM mounts SPD at /api/v1/spd (SPD_MOUNT_PATH in src/modules/spd/config.js),
# so that is the shape required here. Set SPD_API_ALLOW_UNUSUAL=1 for a genuinely
# different mount — a reverse proxy that strips the prefix, say — which keeps
# this a guard rather than a cage.
#
# A trailing slash is trimmed rather than refused: normalizeApiRoot() in
# lib/core/api.dart trims it too, so the build would have worked and refusing
# it would be this guard inventing a rule the app does not have.
SPD_API="${SPD_API%/}"

if [ "${SPD_API_ALLOW_UNUSUAL:-0}" != "1" ]; then
  case "${SPD_API}" in
    https://*/api/v1/spd | http://*/api/v1/spd) ;;
    *)
      echo "" >&2
      echo "ERROR: SPD_API does not look like an SPD API root." >&2
      echo "  got      ${SPD_API}" >&2
      echo "  expected https://<host>/api/v1/spd" >&2
      echo "" >&2
      echo "The CRM mounts this module at /api/v1/spd. A root without it compiles" >&2
      echo "and deploys cleanly, then 404s on every call — which is how this" >&2
      echo "console last shipped unusable." >&2
      echo "" >&2
      echo "Set SPD_API_ALLOW_UNUSUAL=1 if the mount really is different." >&2
      exit 1
      ;;
  esac
fi

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
