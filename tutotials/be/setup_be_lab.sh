#!/usr/bin/env bash
# setup_be_lab.sh — Create a 128M ext3 image with planted forensic artifacts
# for the CSCI 4623 bulk_extractor tutorial.
#
# Usage: sudo bash setup_be_lab.sh
#
# Creates: be_lab.dd (128 MiB raw image, single ext3 partition)
#
# Planted artifacts:
#   - Text files containing emails, phone numbers, credit card numbers, URLs
#   - JPEG with EXIF/GPS metadata
#   - .gz archive containing PII (tests recursive decompression)
#   - BASE64-encoded file with hidden email addresses
#   - A file deleted after creation (content persists in unallocated space)
#   - Simulated swap region (urandom + planted artifacts in raw blocks)
#
set -euo pipefail

IMG="be_lab.dd"
MNT="/mnt/be_lab"
SIZE_MB=128

# ── Colors for output ──
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

# ── Preflight checks ──
if [[ $EUID -ne 0 ]]; then
  echo "Error: run with sudo" >&2; exit 1
fi
for cmd in dd fdisk mkfs.ext3 losetup mount exiftool gzip base64; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: $cmd not found. Install it first." >&2; exit 1
  }
done

green "[*] Creating ${SIZE_MB} MiB raw image..."
dd if=/dev/zero of="$IMG" bs=1M count=$SIZE_MB status=none

green "[*] Writing MBR partition table..."
printf 'o\nn\np\n1\n2048\n\nt\n83\nw\n' | fdisk "$IMG" >/dev/null 2>&1

green "[*] Attaching loop device and formatting ext3..."
LOOP=$(losetup -fP --show "$IMG")
PART="${LOOP}p1"

# Wait for partition device to appear
sleep 1
if [[ ! -b "$PART" ]]; then
  # Fallback: manual offset
  losetup -d "$LOOP"
  LOOP=$(losetup --find --show --offset $((2048 * 512)) "$IMG")
  PART="$LOOP"
fi

mkfs.ext3 -L "suspect_drive" -q "$PART"

green "[*] Mounting filesystem..."
mkdir -p "$MNT"
mount "$PART" "$MNT"

# ════════════════════════════════════════════════════════════════════
# Phase 1: Planted text files with scannable artifacts
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 1: Creating text files with forensic artifacts..."

mkdir -p "$MNT/documents" "$MNT/web_cache" "$MNT/personal"

# File with email addresses and phone numbers
cat > "$MNT/documents/contacts.txt" << 'CONTACTS'
Team Contact List — Project Nightfall
======================================

Lead analyst:    jsmith@forensiclab.org        (555) 234-5678
Field tech:      maria.garcia@evidence.net     +1-555-876-5432
Legal counsel:   bob.chen@lawfirm.com          555.111.2233
External:        darkweb_dealer99@protonmail.ch

Meeting notes: Suspect communicated via suspect_alias@tutanota.com
and was also seen using throwaway_42@guerrillamail.com.
CONTACTS

# File with credit card numbers and SSNs
cat > "$MNT/documents/financial_records.txt" << 'FINANCE'
Transaction Log — CONFIDENTIAL
================================

Purchase 1: Visa 4532-0151-1283-0442  exp 08/27  CVV 319  $2,450.00
Purchase 2: MC   5425-2334-1009-8873  exp 11/26  CVV 542  $890.00
Purchase 3: Amex 3782-822463-10005    exp 03/28  CVV 4421 $15,200.00

Employee SSN on file: 219-09-9999
Backup SSN record:    078-05-1120
FINANCE

# File with URLs
cat > "$MNT/web_cache/browser_history.txt" << 'URLS'
Recovered Browser History Fragment
===================================
2025-09-14 08:12:03  https://www.bankofamerica.com/login
2025-09-14 09:45:11  https://drive.google.com/file/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/view
2025-09-14 11:02:33  http://192.168.1.105:8080/upload
2025-09-14 14:17:22  https://www.amazon.com/gp/product/B09V3KXJPB
2025-09-14 16:33:01  https://paste.debian.net/hidden/abcd1234/
2025-09-14 22:55:48  http://ftp.suspect-server.ru/drops/package_v2.tar.gz
URLS

# Personal file with mix of PII
cat > "$MNT/personal/diary.txt" << 'DIARY'
Oct 15 — Finally got the new phone. Ported my number 555-867-5309 over.
Called the bank at 1-800-432-1000 to update records. Account ending 8873.

Emailed the package tracking to myself: tracking_updates@gmail.com
FedEx tracking: 7489273640012345

Met with K at the usual spot. He said contact him at k_drops@darkmail.de
if anything changes. DO NOT use the old address.
DIARY

# ════════════════════════════════════════════════════════════════════
# Phase 2: JPEG with EXIF metadata
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 2: Creating JPEG with EXIF/GPS metadata..."

# Create a minimal valid JPEG (8x8 red square) via ImageMagick if available,
# otherwise create a minimal JFIF by hand
if command -v convert >/dev/null 2>&1; then
  convert -size 64x64 xc:red "$MNT/personal/meetup_photo.jpg" 2>/dev/null
else
  # Minimal JPEG: SOI + APP0 + SOF + SOS + EOI with tiny image data
  printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00' > "$MNT/personal/meetup_photo.jpg"
  printf '\xff\xd9' >> "$MNT/personal/meetup_photo.jpg"
fi

# Add EXIF metadata including GPS coordinates (downtown parking garage)
exiftool -overwrite_original \
  -Make="Samsung" \
  -Model="Galaxy S23 Ultra" \
  -DateTimeOriginal="2025:09:14 22:30:15" \
  -GPSLatitude="33.7490" \
  -GPSLatitudeRef="N" \
  -GPSLongitude="84.3880" \
  -GPSLongitudeRef="W" \
  -Artist="J. Smith" \
  -ImageDescription="Meeting location — east dock warehouse" \
  "$MNT/personal/meetup_photo.jpg" 2>/dev/null || true

# ════════════════════════════════════════════════════════════════════
# Phase 3: Compressed archive with PII (recursive decompression test)
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 3: Creating .gz archive with hidden PII..."

cat > /tmp/be_lab_hidden_pii.txt << 'HIDDEN'
--- ENCRYPTED COMMUNICATION LOG (recovered) ---

From: operator_x@securemail.onion
To:   handler99@riseup.net
Date: 2025-09-10

Wire transfer confirmed: routing 021000021, account 1234567890
Backup contact: burner_phone@signal.me  Phone: 555-999-0101

Bitcoin wallet: 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa

Drop coordinates: 33.7485 N, 84.3915 W
HIDDEN

gzip -c /tmp/be_lab_hidden_pii.txt > "$MNT/documents/archived_log.gz"
rm /tmp/be_lab_hidden_pii.txt

# ════════════════════════════════════════════════════════════════════
# Phase 4: BASE64-encoded file with hidden emails
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 4: Creating BASE64-encoded file..."

cat > /tmp/be_lab_b64_source.txt << 'B64SRC'
Internal memo: The following accounts were flagged for review:
  - insider_trade@corpmail.com (accessed restricted docs)
  - leak_source@whistleblow.org (external communication)
  - cfo_backup@gmail.com (unauthorized cloud storage)
Phone: 555-321-7654
B64SRC

base64 /tmp/be_lab_b64_source.txt > "$MNT/documents/encoded_memo.b64"
rm /tmp/be_lab_b64_source.txt

# ════════════════════════════════════════════════════════════════════
# Phase 5: File that will be deleted (unallocated space test)
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 5: Creating and deleting sensitive file..."

cat > "$MNT/documents/destroy_after_reading.txt" << 'DESTROY'
EYES ONLY — DELETE IMMEDIATELY

Meeting confirmed for 2025-09-15 at 0200 hours.
Contact: ghost_op@tutanota.com  Backup: 555-000-1234

Wire $50,000 to account 9876543210, routing 071000013.
Use reference: NIGHTFALL-FINAL

Destroy this message.
DESTROY

sync
DELETED_INODE=$(stat -c '%i' "$MNT/documents/destroy_after_reading.txt")
yellow "    deleted file inode: $DELETED_INODE (record this for Task 11)"
rm "$MNT/documents/destroy_after_reading.txt"
sync

# ════════════════════════════════════════════════════════════════════
# Phase 6: Simulated swap-like region with planted artifacts
# ════════════════════════════════════════════════════════════════════
green "[*] Phase 6: Writing artifacts into raw unallocated blocks..."

# Write some random data first, then plant artifacts within it
dd if=/dev/urandom of="$MNT/personal/.swap_fragment" bs=4096 count=16 status=none 2>/dev/null

# Overwrite middle of the "swap" with scannable content
SWAP_ARTIFACT="SWAP FRAGMENT: admin_access@rootkit.cc password:Hunt3r2! Phone:555-777-8888 CC:4111111111111111"
echo "$SWAP_ARTIFACT" | dd of="$MNT/personal/.swap_fragment" bs=1 seek=8192 conv=notrunc status=none 2>/dev/null

sync

# ════════════════════════════════════════════════════════════════════
# Cleanup
# ════════════════════════════════════════════════════════════════════
green "[*] Unmounting and detaching..."
umount "$MNT"
losetup -d "$LOOP"
rmdir "$MNT" 2>/dev/null || true

green "[+] Done. Practice image ready: $IMG"
yellow "    Image size: ${SIZE_MB} MiB"
yellow "    Partition offset: 2048 sectors (1,048,576 bytes)"
yellow "    Filesystem: ext3, label 'suspect_drive'"
echo ""
yellow "Planted artifacts summary:"
echo "  Phase 1: emails, phones, credit cards, SSNs, URLs in text files"
echo "  Phase 2: JPEG with EXIF/GPS metadata"
echo "  Phase 3: gzip archive with hidden PII (recursive decompression)"
echo "  Phase 4: BASE64-encoded memo with emails"
echo "  Phase 5: deleted file (content in unallocated) — inode $DELETED_INODE"
echo "  Phase 6: artifacts planted in pseudo-swap fragment"
