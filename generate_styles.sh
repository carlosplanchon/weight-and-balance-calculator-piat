#!/usr/bin/env bash
# Generate the minified Tailwind CSS at assets/tailwind.css.
# Scans index.html per tailwind.config.js.

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d node_modules ]; then
    echo "node_modules missing - running npm install..."
    npm install
fi

npx tailwindcss -i ./input.css -o ./assets/tailwind.css --minify

# Cache busting: stamp the build's content hash as a query string on the page
# that links the stylesheet. Static servers usually send no Cache-Control, so
# browsers cache heuristically; a new URL forces a fresh fetch after each
# rebuild. Idempotent: same CSS, same hash, no diff.
HASH=$(sha256sum assets/tailwind.css | cut -c1-8)
for page in index.html; do
    sed -i -E "s|(href=\"assets/tailwind\.css)[^\"]*\"|\1?v=${HASH}\"|" "$page"
done

echo "Done - $(du -h assets/tailwind.css | cut -f1) at assets/tailwind.css (v=${HASH})"
