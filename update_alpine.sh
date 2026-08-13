#!/usr/bin/env bash
# Updates the vendored Alpine JS bundle in assets/ and the imports in the pages.
#
# Usage:
#   ./update_alpine.sh          -> latest stable version (npm "latest" tag)
#   ./update_alpine.sh 3.15.2   -> specific version
#
# The download goes through npm, which verifies sha512 integrity against the
# registry and records the version in package.json (so "npm audit" covers
# Alpine). This script commits nothing: run the QUnit suite and commit manually.

set -euo pipefail

cd "$(dirname "$0")"

REQUESTED="${1:-latest}"

echo "Instalando alpinejs@${REQUESTED} via npm..."
npm install --save-dev --save-exact "alpinejs@${REQUESTED}"

NEW_VERSION=$(node -p "require('./node_modules/alpinejs/package.json').version")
NEW_FILE="alpinejs-${NEW_VERSION}.min.js"

cp node_modules/alpinejs/dist/cdn.min.js "assets/${NEW_FILE}"

# Sanity check: the bundle declares its own version
if ! grep -q "${NEW_VERSION}" "assets/${NEW_FILE}"; then
    echo "ERROR: assets/${NEW_FILE} no contiene la version ${NEW_VERSION}; abortando." >&2
    rm -f "assets/${NEW_FILE}"
    exit 1
fi

# Update the import and the version comment in the page that uses Alpine
FILES=(index.html)
for f in "${FILES[@]}"; do
    sed -i -E "s/alpinejs-[0-9]+\.[0-9]+\.[0-9]+\.min\.js/${NEW_FILE}/g" "$f"
    sed -i -E "s/v[0-9]+\.[0-9]+\.[0-9]+ pinned/v${NEW_VERSION} pinned/g" "$f"
done

# Delete old bundles (git keeps the history)
find assets -maxdepth 1 -name 'alpinejs-*.min.js' ! -name "${NEW_FILE}" -delete

echo
echo "Alpine ${NEW_VERSION} vendoreado en assets/${NEW_FILE} ($(du -h "assets/${NEW_FILE}" | cut -f1))"
echo "Imports resultantes:"
grep -n "alpinejs-" "${FILES[@]}"
echo
echo "Antes de commitear, correr la suite: ./run_tests.sh"
