#!/usr/bin/env bash
# Runs the calculator's QUnit suite in headless Chromium and fails
# (exit != 0) if any assertion fails or the page never reports results.
# Meant to be chained with the update_*.sh scripts before committing:
#
#   ./update_alpine.sh && ./run_tests.sh
#
# No new dependencies needed: it uses the system chrome/chromium (or the one
# in the Playwright cache as a fallback) plus a python http.server on an
# ephemeral port picked by the OS (avoids collisions with other services).
# In CI the browser binary can be forced with the CHROME_BIN variable.

set -euo pipefail

cd "$(dirname "$0")"

find_chrome() {
    local c
    if [ -n "${CHROME_BIN:-}" ]; then
        echo "${CHROME_BIN}"
        return
    fi
    for c in chromium google-chrome-stable google-chrome chromium-browser; do
        if command -v "$c" >/dev/null 2>&1; then
            command -v "$c"
            return
        fi
    done
    ls -1 "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | sort | tail -1
}

CHROME=$(find_chrome)
if [ -z "${CHROME}" ]; then
    echo "ERROR: no encontre chromium/chrome (ni en PATH ni en ~/.cache/ms-playwright)." >&2
    exit 1
fi

# Static server on an ephemeral port (0 = the OS picks it); shuts down on exit
SERVER_LOG=$(mktemp)
python3 -u -m http.server 0 --bind 127.0.0.1 >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null; rm -f "$SERVER_LOG"' EXIT

PORT=""
for _ in $(seq 1 50); do
    PORT=$(sed -nE 's/.*port ([0-9]+).*/\1/p' "$SERVER_LOG" | head -1)
    [ -n "$PORT" ] && break
    sleep 0.1
done
if [ -z "$PORT" ]; then
    echo "ERROR: el http.server local no arranco." >&2
    exit 1
fi

CHROME_FLAGS=(--headless --disable-gpu --no-first-run --virtual-time-budget=15000 --dump-dom)
# Chrome refuses to run sandboxed as root (typical case: CI container)
if [ "$(id -u)" = "0" ]; then
    CHROME_FLAGS+=(--no-sandbox --disable-dev-shm-usage)
fi

# Loads the page, waits via virtual-time-budget and extracts the QUnit summary
# from the DOM (tags stripped: the numbers come wrapped in <span>).
#
# The browser call is wrapped in a hard timeout. --virtual-time-budget bounds
# the page's own clock, not the process: a chrome that never reaches the point
# of printing the DOM hangs forever, and in CI that means a job that burns its
# whole allowance instead of failing. A run that takes this long has failed
# either way, so the timeout reports it as one.
run_suite() {
    local name="$1" url="$2"
    local dom summary passed errlog
    errlog=$(mktemp)
    dom=$(timeout "${SUITE_TIMEOUT:-90}" "$CHROME" "${CHROME_FLAGS[@]}" "$url" 2>"$errlog" || true)
    summary=$(printf '%s' "$dom" | sed -e 's/<[^>]*>/ /g' | tr -s ' \n' '  ' \
        | grep -oE '[0-9]+ assertions of [0-9]+ passed, [0-9]+ failed' | head -1)

    if [ -z "$summary" ]; then
        echo "FALLO  ${name}: QUnit no reporto resultados (pagina rota, asset faltante o timeout)."
        if [ -s "$errlog" ]; then
            echo "  stderr de chrome (ultimas lineas):"
            tail -n 5 "$errlog" | sed 's/^/    /'
        fi
        rm -f "$errlog"
        return 1
    fi
    rm -f "$errlog"

    passed="${summary%% *}"
    if [ "${summary##*, }" != "0 failed" ] || [ "$passed" = "0" ]; then
        echo "FALLO  ${name}: ${summary}"
        return 1
    fi
    echo "OK     ${name}: ${summary}"
}

FAIL=0
run_suite "W&B" "http://127.0.0.1:${PORT}/index.html?test=true" || FAIL=1

echo
if [ "$FAIL" -ne 0 ]; then
    echo "Resultado: HAY FALLAS. No commitear."
else
    echo "Resultado: todo verde."
fi
exit "$FAIL"
