#!/usr/bin/env bash
# setup_blockhash_lab.sh — Create a controlled environment for block hash exercises
# CSCI 4623 — Digital Forensics
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────
IMG="blockhash_lab.img"
IMG_SIZE=64     # MB
BLOCK_SIZE=4096
MNT="/mnt/bhlab"
REF_DIR="reference"

echo "=== Block Hash Lab Setup ==="
echo "Creating ${IMG_SIZE}M ext4 image: ${IMG}"

# ── Create and format image ───────────────────────────────────────
dd if=/dev/zero of="$IMG" bs=1M count="$IMG_SIZE" status=progress 2>&1
mkfs.ext4 -b "$BLOCK_SIZE" -q "$IMG"
echo "[+] ext4 image created (block size = ${BLOCK_SIZE})"

# ── Find an available loop device (skip snap-occupied ones) ───────
LOOP=$(losetup --find --show "$IMG")
echo "[+] Attached to ${LOOP}"

# ── Mount ─────────────────────────────────────────────────────────
sudo mkdir -p "$MNT"
sudo mount "$LOOP" "$MNT"
echo "[+] Mounted at ${MNT}"

# ── Create reference directory ────────────────────────────────────
mkdir -p "$REF_DIR"

# ── Plant known reference files ───────────────────────────────────
# File 1: a recognizable text document
cat > /tmp/bh_memo.txt << 'MEMO'
CONFIDENTIAL MEMORANDUM
Date: 2025-01-15
Subject: Quarterly Revenue Projections

The projected revenue for Q1 2025 is $4.2M, representing a 12%
increase over the previous quarter. Key growth areas include the
enterprise licensing division and the newly launched cloud platform.

Action items:
1. Finalize pricing model by January 31
2. Submit revised forecasts to CFO by February 7
3. Schedule board presentation for February 15

This document is classified INTERNAL USE ONLY.
MEMO
sudo cp /tmp/bh_memo.txt "$MNT/memo.txt"
cp /tmp/bh_memo.txt "$REF_DIR/memo.txt"
echo "[+] Planted memo.txt"

# File 2: a small binary-like file (simulated known application fragment)
python3 -c "
import struct, os
# Deterministic pseudo-binary content (simulated executable header + data)
header = b'BHLAB\x00\x01\x00' + b'\x89PNG' + bytes(range(256)) * 16
with open('/tmp/bh_known_app.bin', 'wb') as f:
    f.write(header)
"
sudo cp /tmp/bh_known_app.bin "$MNT/known_app.bin"
cp /tmp/bh_known_app.bin "$REF_DIR/known_app.bin"
echo "[+] Planted known_app.bin"

# File 3: a configuration file (will be DELETED later — the payoff)
cat > /tmp/bh_secret_config.conf << 'CONF'
# Database connection parameters — SENSITIVE
[database]
host = 10.0.42.7
port = 5432
name = production_core
user = svc_readonly
password = EXAMPLE_PASSWORD_PLACEHOLDER

[api_keys]
stripe_live = EXAMPLE_STRIPE_KEY_PLACEHOLDER
sendgrid = EXAMPLE_SENDGRID_KEY_PLACEHOLDER

# WARNING: This file should never appear on removable media
CONF
sudo cp /tmp/bh_secret_config.conf "$MNT/secret_config.conf"
cp /tmp/bh_secret_config.conf "$REF_DIR/secret_config.conf"
echo "[+] Planted secret_config.conf (will be deleted)"

# ── Plant unknown (decoy) files ───────────────────────────────────
sudo bash -c "echo 'This is just a normal README for the project.' > $MNT/README.txt"
sudo bash -c "dd if=/dev/urandom of=$MNT/random_data.bin bs=4096 count=4 2>/dev/null"
sudo bash -c "printf 'Log entry: system boot at 2025-01-15 08:00:00\nLog entry: service started\n' > $MNT/system.log"
echo "[+] Planted decoy files"

# ── Sync and delete the secret config ─────────────────────────────
sudo sync
sudo rm "$MNT/secret_config.conf"
sudo sync
echo "[+] Deleted secret_config.conf (blocks remain in unallocated space)"

# ── Unmount and detach ────────────────────────────────────────────
sudo umount "$MNT"
sudo losetup -d "$LOOP"
echo ""
echo "=== Setup Complete ==="
echo "  Image file:      ${IMG}"
echo "  Reference files:  ${REF_DIR}/"
echo "    - memo.txt"
echo "    - known_app.bin"
echo "    - secret_config.conf"
echo ""
echo "The image contains:"
echo "  - memo.txt (allocated, known)"
echo "  - known_app.bin (allocated, known)"
echo "  - secret_config.conf (DELETED, known — your target)"
echo "  - README.txt, random_data.bin, system.log (allocated, unknown decoys)"
echo ""
echo "Your goal: use block hashing to find the deleted file."
