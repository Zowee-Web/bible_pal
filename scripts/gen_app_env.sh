#!/usr/bin/env bash
#
# gen_app_env.sh — Generate the bundled client config from the dev .env.
#
# The Flutter app must NEVER bundle pipeline secrets. This writes
# assets/config/app.env containing ONLY the env keys the app reads at runtime
# (the allowlist below). Everything else in .env — ANTHROPIC_API_KEY,
# CLOUDFLARE_API_TOKEN, and the VOICE_* render ids — stays out of the binary.
#
# Runs automatically before `flutter build` in build_play_bundle.sh and
# build_ios_bundle.sh. Run it by hand after editing .env so a local
# `flutter run` picks up the change. Output is gitignored (**/*.env).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.env"
OUT="$ROOT/assets/config/app.env"

# The ONLY keys lib/ reads via dotenv. Keep this list minimal — adding a key
# here ships it to every user. Verified runtime reads:
#   AUDIO_BASE_URL      -> R2 base url (catalog + parable audio services)
#   ELEVENLABS_API_KEY  -> runtime name-tts (service_providers.dart:134)
ALLOW=(AUDIO_BASE_URL ELEVENLABS_API_KEY)

mkdir -p "$(dirname "$OUT")"

if [ ! -f "$SRC" ]; then
  echo "gen_app_env: WARNING — $SRC not found; writing empty $OUT" >&2
  : > "$OUT"
  exit 0
fi

tmp="$(mktemp)"
for key in "${ALLOW[@]}"; do
  line="$(grep -E "^${key}=" "$SRC" || true)"
  if [ -n "$line" ]; then
    printf '%s\n' "$line" >> "$tmp"
  else
    echo "gen_app_env: WARNING — $key not present in .env" >&2
  fi
done
mv "$tmp" "$OUT"

echo "gen_app_env: wrote $OUT with ${#ALLOW[@]} allowlisted client key(s); pipeline secrets excluded."
