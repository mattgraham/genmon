#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Launch a genmon service in the Cloud Agent VM.
#
#   run.sh genmon    -> the monitor process (talks to the simulated controller)
#   run.sh genserv   -> the Flask web dashboard (http://localhost:8000)
#
# Both processes require root (they check os.geteuid()==0), so they are launched
# via passwordless sudo using the project virtual environment's interpreter.
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$REPO/genenv/bin/python"
CONF="$REPO/.cursor/rundata/conf"

if [ ! -x "$PY" ]; then
    echo "Virtual environment missing; run .cursor/install.sh first." >&2
    exit 1
fi

case "${1:-}" in
    genmon)
        exec sudo "$PY" "$REPO/genmon.py" -c "$CONF"
        ;;
    genserv)
        # genserv queries the monitor's client interface (server_port 9082) on
        # startup and exits if it is not reachable, so wait for it to come up.
        echo "Waiting for genmon monitor on 127.0.0.1:9082 ..."
        for _ in $(seq 1 90); do
            if (exec 3<>/dev/tcp/127.0.0.1/9082) 2>/dev/null; then
                exec 3>&-
                break
            fi
            sleep 1
        done
        exec sudo "$PY" "$REPO/genserv.py" -c "$CONF"
        ;;
    *)
        echo "usage: run.sh genmon|genserv" >&2
        exit 1
        ;;
esac
