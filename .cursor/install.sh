#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Cloud Agent install script for genmon.
#
# Idempotent: safe to run repeatedly. Prepares a Python virtual environment
# with all runtime dependencies and generates a writable runtime configuration
# that runs genmon in "simulation" mode (no physical generator hardware is
# attached in the Cloud Agent VM).
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$REPO/genenv"
PY="$VENV/bin/python"
RUNDATA="$REPO/.cursor/rundata"
CONF="$RUNDATA/conf"
LOGS="$RUNDATA/logs"
SIM="$RUNDATA/sim"

echo "==> genmon install: repo=$REPO"

# 1. System build dependencies (needed to compile the native wheels in
#    requirements.txt: crcmod, RPi.GPIO, spidev, smbus, cryptography, ...).
echo "==> Installing system packages"
sudo apt-get -yqq update
sudo apt-get -yqq install \
    python3-venv python3-dev build-essential \
    libssl-dev libffi-dev swig liblgpio-dev libi2c-dev cmake \
    git curl

# 2. Python virtual environment (Ubuntu's system Python is externally managed).
if [ ! -x "$PY" ]; then
    echo "==> Creating virtual environment at $VENV"
    python3 -m venv "$VENV"
fi
echo "==> Installing Python requirements"
"$PY" -m pip install --upgrade pip setuptools wheel
"$PY" -m pip install --prefer-binary -r "$REPO/requirements.txt"

# 3. Writable runtime configuration (the repo's conf/ stays pristine; genmon
#    writes generated values such as secret_key into its config directory).
echo "==> Preparing runtime config at $CONF"
mkdir -p "$CONF" "$LOGS" "$SIM"
cp "$REPO"/conf/*.conf "$CONF"/

# 4. Generate the simulation register dump consumed by genmonlib/modbus_file.py.
echo "==> Generating simulation register data"
"$PY" "$REPO/.cursor/gen_sim.py" "$SIM/evolution_lc_sim.json"

# 5. Patch the runtime genmon.conf for headless simulation on this VM.
echo "==> Patching runtime genmon.conf for simulation mode"
"$PY" - "$CONF/genmon.conf" "$LOGS" "$SIM/evolution_lc_sim.json" <<'PYEOF'
import re, sys
conf_path, logs, simfile = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf_path) as f:
    text = f.read()

def set_option(text, key, value):
    pattern = re.compile(r"(?m)^\s*#?\s*" + re.escape(key) + r"\s*=.*$")
    line = "%s = %s" % (key, value)
    if pattern.search(text):
        return pattern.sub(line, text, count=1)
    # insert into the [GenMon] section (append after the header)
    return re.sub(r"(?m)^(\[GenMon\]\s*)$", r"\1\n" + line, text, count=1)

text = set_option(text, "loglocation", logs.rstrip("/") + "/")
text = set_option(text, "controllertype", "custom")
text = set_option(text, "simulation", "True")
text = set_option(text, "simulationfile", simfile)
with open(conf_path, "w") as f:
    f.write(text)
print("patched", conf_path)
PYEOF

echo "==> genmon install complete"
