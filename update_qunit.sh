#!/usr/bin/env bash
# Updates the vendored QUnit bundle in assets/ (js + css) and the references
# in the calculator's test loader.
#
# Usage:
#   ./update_qunit.sh          -> latest stable version (npm "latest" tag)
#   ./update_qunit.sh 2.21.0   -> specific version
#
# Same as update_alpine.sh: the download goes through npm, which verifies
# sha512 integrity against the registry and records the version in
# package.json (covered by "npm audit"). This script commits nothing:
# run the QUnit suite and commit manually.

set -euo pipefail

cd "$(dirname "$0")"

REQUESTED="${1:-latest}"

echo "Instalando qunit@${REQUESTED} via npm..."
npm install --save-dev --save-exact "qunit@${REQUESTED}"

NEW_VERSION=$(node -p "require('./node_modules/qunit/package.json').version")
NEW_JS="qunit-${NEW_VERSION}.js"
NEW_CSS="qunit-${NEW_VERSION}.css"

SRC_JS="node_modules/qunit/qunit/qunit.js"
SRC_CSS="node_modules/qunit/qunit/qunit.css"
if [ ! -f "$SRC_JS" ] || [ ! -f "$SRC_CSS" ]; then
    echo "ERROR: no encuentro ${SRC_JS} o ${SRC_CSS}; cambio el layout del paquete qunit?" >&2
    exit 1
fi

cp "$SRC_JS" "assets/${NEW_JS}"
cp "$SRC_CSS" "assets/${NEW_CSS}"

# Sanity check: the bundle declares its own version
if ! grep -q "${NEW_VERSION}" "assets/${NEW_JS}"; then
    echo "ERROR: assets/${NEW_JS} no contiene la version ${NEW_VERSION}; abortando." >&2
    rm -f "assets/${NEW_JS}" "assets/${NEW_CSS}"
    exit 1
fi

# Update the references in the test loader
FILES=(index.html)
for f in "${FILES[@]}"; do
    sed -i -E "s/qunit-[0-9]+\.[0-9]+\.[0-9]+\.js/${NEW_JS}/g" "$f"
    sed -i -E "s/qunit-[0-9]+\.[0-9]+\.[0-9]+\.css/${NEW_CSS}/g" "$f"
done

# Delete old versions (git keeps the history)
find assets -maxdepth 1 -name 'qunit-*.js' ! -name "${NEW_JS}" -delete
find assets -maxdepth 1 -name 'qunit-*.css' ! -name "${NEW_CSS}" -delete

echo
echo "QUnit ${NEW_VERSION} vendoreado: assets/${NEW_JS} ($(du -h "assets/${NEW_JS}" | cut -f1)) + assets/${NEW_CSS} ($(du -h "assets/${NEW_CSS}" | cut -f1))"
echo "Referencias resultantes:"
grep -n "assets/qunit-" "${FILES[@]}"
echo
echo "Antes de commitear, correr la suite: ./run_tests.sh"
