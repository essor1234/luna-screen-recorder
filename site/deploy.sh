#!/usr/bin/env bash
# Deploy site/ to the Cloudflare Pages project "luna" (luna.nimit.dev, luna-cnb.pages.dev).
# Copies only the public files to a temp dir first, so dotfiles, video/ sources
# and this script never get uploaded.
set -euo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
rsync -a --exclude '.*' --exclude 'video' --exclude 'deploy.sh' --exclude 'README.md' ./ "$OUT/"
cd "$OUT"
# Cloudflare sometimes fails with "Unknown internal error"; a retry usually works.
for attempt in 1 2 3; do
  if npx wrangler pages deploy . --project-name luna --branch main --commit-dirty=true; then exit 0; fi
  echo "Deploy attempt $attempt failed, retrying..." >&2
  sleep 5
done
exit 1
