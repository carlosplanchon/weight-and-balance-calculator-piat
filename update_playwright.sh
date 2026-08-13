#!/usr/bin/env bash
# Updates the pinned Playwright version, which defines the Chromium that
# run_tests.sh uses in CI. It does not touch the published site: it is only
# the verification tooling.
#
# Usage:
#   ./update_playwright.sh          -> latest stable version (npm "latest" tag)
#   ./update_playwright.sh 1.62.0   -> specific version
#
# The Chromium cache key in the workflows is derived from this version, so a
# bump rotates the cache by itself and the next CI job downloads, caches and
# tests with the new Chromium. This script commits nothing.

set -euo pipefail

cd "$(dirname "$0")"

REQUESTED="${1:-latest}"

echo "Instalando playwright@${REQUESTED} via npm..."
npm install --save-dev --save-exact "playwright@${REQUESTED}"

NEW_VERSION=$(node -p "require('./node_modules/playwright/package.json').version")

echo
echo "Playwright ${NEW_VERSION} pinneado en package.json."
echo "Nota: run_tests.sh local usa el chrome del sistema; el Chromium de esta"
echo "version lo usa CI. Para probarlo local: npx playwright install chromium"
echo "Antes de commitear, correr la suite: ./run_tests.sh"
