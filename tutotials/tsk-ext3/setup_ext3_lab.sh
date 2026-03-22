#!/usr/bin/env bash
# setup_ext3_lab.sh — Create a 128M forensic practice image (two partitions)
# Usage: sudo bash setup_ext3_lab.sh
set -euo pipefail

IMG="ext3_lab.dd"
MNT1="/mnt/ext3_lab_p1"
MNT2="/mnt/ext3_lab_p2"

echo "[*] Creating 128 MiB raw image..."
dd if=/dev/zero of="$IMG" bs=1M count=128 status=none

echo "[*] Writing partition table (two Linux partitions)..."
sfdisk --quiet "$IMG" <<EOF
label: dos
start=2048, size=129024, type=83
start=131072, type=83
EOF

echo "[*] Setting up loop devices..."
LOOP1=$(losetup --find --show --offset $((2048 * 512)) --sizelimit $((129024 * 512)) "$IMG")
LOOP2=$(losetup --find --show --offset $((131072 * 512)) "$IMG")

echo "[*] Formatting partition 1 as ext3 (evidence_vol)..."
mkfs.ext3 -L "evidence_vol" -q "$LOOP1"

echo "[*] Formatting partition 2 as ext3 (usb_backup)..."
mkfs.ext3 -L "usb_backup" -q "$LOOP2"

mkdir -p "$MNT1" "$MNT2"
mount "$LOOP1" "$MNT1"
mount "$LOOP2" "$MNT2"

# ── Phase 1: Initial documents (morning activity) ──────────────────
echo "[*] Phase 1: Creating initial documents..."
echo "The quick brown fox jumps over the lazy dog." > "$MNT1/readme.txt"
mkdir "$MNT1/documents"
echo "SSN: 078-05-1120 (this is the original SS-5 sample number)" \
  > "$MNT1/documents/pii_sample.txt"
echo "Contract value: \$4,500,000. Effective date: 2025-03-01." \
  > "$MNT1/documents/contract.txt"
sync
sleep 2

# ── Phase 2: Project files (midday activity) ───────────────────────
echo "[*] Phase 2: Creating project files..."
mkdir "$MNT1/projects"
echo "Project ATLAS: Phase 2 approved. Budget: \$1.2M. Lead: J. Chen." \
  > "$MNT1/projects/atlas_status.txt"
echo "Meeting notes 06/15: discussed merger timeline with legal. NDA expires July 1." \
  > "$MNT1/projects/meeting_notes.txt"
sync
sleep 2

# ── Phase 3: Personal files (afternoon activity) ───────────────────
echo "[*] Phase 3: Creating personal files..."
mkdir "$MNT1/personal"
echo "Flight confirmation: LAX to JFK, March 15, 2025, seat 12A, conf# BK7942" \
  > "$MNT1/personal/travel.txt"
echo "Password reminder: bank pin 4421, email backup code XKCD-9371" \
  > "$MNT1/personal/passwords.txt"
echo "Reminder: pick up prescription at Walgreens on Tuesday" \
  > "$MNT1/personal/todo.txt"
sync
sleep 2

# ── Phase 4: Copy sensitive files to USB backup partition ──────────
echo "[*] Phase 4: Copying files to USB backup partition..."
cp "$MNT1/documents/contract.txt" "$MNT2/contract_backup.txt"
cp "$MNT1/projects/atlas_status.txt" "$MNT2/atlas_backup.txt"
echo "Backup created $(date -u +%Y-%m-%d). Contents: contract.txt, atlas_status.txt" \
  > "$MNT2/backup_manifest.txt"
echo "Sensitive files copied to USB backup drive (partition 2)." \
  > "$MNT1/documents/transfer_log.txt"
sync
sleep 2

# ── Phase 5: Create and then delete sensitive files ────────────────
echo "[*] Phase 5: Deleting files (cover tracks)..."
echo "SECRET: The meeting is at midnight, east dock." > "$MNT1/deleted_note.txt"
sync
sleep 1

# Record inodes and hashes before deletion
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              RECOVERY CHALLENGE REFERENCE                   ║"
echo "║  Save this output — you will need it for Tasks 9 and 11.   ║"
echo "╠══════════════════════════════════════════════════════════════╣"

record_file() {
  local path="$1"
  local label="$2"
  local inode hash
  inode=$(stat -c '%i' "$path")
  hash=$(md5sum "$path" | awk '{print $1}')
  printf "║  %-22s inode: %-5s md5: %s ║\n" "$label" "$inode" "$hash"
}

record_file "$MNT1/deleted_note.txt"          "deleted_note.txt"
record_file "$MNT1/personal/passwords.txt"    "passwords.txt"
record_file "$MNT1/projects/atlas_status.txt" "atlas_status.txt"
record_file "$MNT1/projects/meeting_notes.txt" "meeting_notes.txt"

echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

rm "$MNT1/deleted_note.txt"
rm "$MNT1/personal/passwords.txt"
rm "$MNT1/projects/atlas_status.txt"
rm "$MNT1/projects/meeting_notes.txt"
sync

echo "[*] Cleaning up mounts..."
umount "$MNT1"
umount "$MNT2"
losetup -d "$LOOP1"
losetup -d "$LOOP2"
rmdir "$MNT1" "$MNT2"

echo ""
echo "[+] Done. Practice image ready: $IMG (128 MiB)"
echo "[+] Partition 1 (evidence_vol): offset 2048 sectors"
echo "[+] Partition 2 (usb_backup):   offset 131072 sectors"
echo "[+] Four files were deleted from partition 1."
