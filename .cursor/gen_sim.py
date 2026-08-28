#!/usr/bin/env python3
"""Generate a genmon ModbusFile simulation register dump.

Cloud Agent dev-environment only. The Cloud Agent VM has no physical generator
attached, so genmon is run in "simulation" mode where genmonlib/modbus_file.py
serves register values from a JSON file instead of a serial/modbus link.

This builds a believable "generator running on utility" snapshot for the
Evolution Liquid Cooled custom-controller definition that ships in
data/controller/Evolution_Liquid_Cooled.json.

Usage: gen_sim.py [output.json]
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CTRL = os.path.join(REPO, "data", "controller", "Evolution_Liquid_Cooled.json")

DEST = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, "rundata", "sim", "evolution_lc_sim.json"
)

with open(CTRL) as f:
    ctrl = json.load(f)

holding = ctrl["holding_registers"]

# Meaningful "generator running" snapshot. Values are decoded by the custom
# controller per the register definitions in the controller JSON (masks,
# multipliers, bit fields). reg -> integer value (big-endian into length bytes).
values = {
    "0001": 0x0003,   # Engine State: Running
    "0002": 0x0000,   # Switch State: Auto (no alarm)
    "0007": 1800,     # RPM
    "0008": 6000,     # Frequency raw (gauge x0.01 -> 60.00 Hz)
    "0009": 245,      # Utility Voltage
    "000a": 132,      # Battery Voltage raw (x0.1 -> 13.2 V)
    "000b": 1234,     # Run Hours
    "000e": 0x0E1E,   # Generator Time: 14:30 (hi=hours, lo=minutes)
    "000f": 0x081C,   # Generator Date: Aug (08) 28 (hi=month, lo=day)
    "0010": 0x051A,   # Day-of-week (5=Fri) / year (0x1a=26 -> 2026)
    "0011": 143,      # Threshold Voltage
    "0012": 240,      # Output Voltage
    "001a": 21,       # Hours Until Service A Due
    "001e": 189,      # Hours Until Service B Due
    "002a": 0x0203,   # Firmware / Hardware Version
    "002c": 0x0900,   # Exercise Time (09:00)
    "0052": 0x0040,   # Digital Inputs: E-Stop bit set = NOT activated (healthy)
    "0053": 0x0008,   # Digital Outputs: Fuel Relay On
    "0054": 512,      # Hours of Protection
    "005d": 78,       # Tank Fuel Level %
    "005e": 1289,     # Total Run Hours
    "023a": 0x0001,   # Activation Status: Activated
    "023b": 200,      # Pickup Voltage
    "023e": 20,       # Exercise Duration (min)
    "0238": 30,       # Warm Up Time
    "0239": 15,       # Start Up Delay
}

serial_text = "SIMEVOLC01"  # simulated serial number (reg 01f4, ascii)

registers = collections.OrderedDict()
for reg, meta in holding.items():
    length_bytes = int(meta["length"])
    hex_len = length_bytes * 2
    if reg == "01f4":
        text = serial_text[:length_bytes].ljust(length_bytes, "\x00")
        registers[reg] = "".join("%02x" % ord(c) for c in text)
        continue
    val = values.get(reg, 0)
    registers[reg] = ("%0*x" % (hex_len, val))[-hex_len:]

out = collections.OrderedDict()
out["Registers"] = registers
out["Strings"] = {}
out["FileData"] = {}

os.makedirs(os.path.dirname(DEST), exist_ok=True)
with open(DEST, "w") as f:
    json.dump(out, f, indent=2)
print("wrote", DEST, "with", len(registers), "registers")
