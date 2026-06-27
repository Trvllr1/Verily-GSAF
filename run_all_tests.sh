#!/bin/bash
set -e

SRC="/mnt/c/Users/Esther Akintoye/Desktop/Verily/Verily-GSAF"
DST="/tmp/gsaf"
PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin:$PATH"
export COCOTB_MAKEFILES="$HOME/.local/lib/python3.14/site-packages/cocotb_tools/makefiles"

echo "=== Syncing files ==="
rsync -a --delete "$SRC/rtl/" "$DST/rtl/"
rsync -a --delete "$SRC/tb/" "$DST/tb/"
rsync -a --delete "$SRC/model/" "$DST/model/"
chown -R $(whoami):$(whoami) "$DST"

echo "=== Golden models ==="
python3 "$DST/model/golden_model.py"
python3 "$DST/model/pqc_ntt_model.py"
python3 "$DST/model/rsa_crt_model.py"

echo "=== PQC simulation ==="
cd "$DST/tb/dynos"
make clean
make test-pqc SIM=verilator

echo "=== RSA-CRT simulation ==="
make clean
make test-rsa-crt SIM=verilator

echo "=== All tests done ==="
