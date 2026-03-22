#!/usr/bin/env bash
# setup_ntfs_lab.sh — CSCI 4623 NTFS Forensics Lab
# Creates a 128 MiB NTFS image with forensic artifacts for case 2024-0311.
# Requirements: ntfs-3g, ntfs-3g-dev (mkntfs), python3, util-linux
# Usage: sudo bash setup_ntfs_lab.sh
set -euo pipefail

IMAGE="ntfs_lab.img"
MNT="/mnt/ntfs_lab"
SIZE_MB=128

# ── 1. Create and format image ─────────────────────────────────────────────────
echo "[*] Creating ${SIZE_MB}M image: ${IMAGE}"
dd if=/dev/zero of="${IMAGE}" bs=1M count="${SIZE_MB}" status=none

echo "[*] Formatting NTFS (volume label: WS042-JSMITH)"
mkntfs -F -L "WS042-JSMITH" -s 512 "${IMAGE}" > /dev/null

# ── 2. Mount ───────────────────────────────────────────────────────────────────
echo "[*] Mounting at ${MNT}"
mkdir -p "${MNT}"
mount -t ntfs-3g -o loop "${IMAGE}" "${MNT}"

# ── 3. Directory structure ─────────────────────────────────────────────────────
mkdir -p "${MNT}/Users/jsmith/Documents"
mkdir -p "${MNT}/Users/jsmith/Desktop"
mkdir -p "${MNT}/Users/jsmith/AppData/Roaming/Microsoft/Windows/Recent"
mkdir -p "${MNT}/Users/jsmith/Downloads"
mkdir -p "${MNT}/System/Logs"

# ── 4. Resident $DATA: incident_summary.txt (< 700 bytes — stays in MFT) ──────
cat > "${MNT}/Users/jsmith/Documents/incident_summary.txt" << 'EOF'
INTERNAL — RESTRICTED
Case: 2024-0311
Subject: J. Smith, contractor, badge C-1847
Access revoked: 2024-03-11 03:00 UTC
Summary: Three files confirmed copied to unregistered host 192.168.1.88
between 02:14 and 02:31 UTC on 2024-03-11. No malware identified.
Assigned analyst: review this workstation image for corroborating evidence.
EOF

# ── 5. Non-resident $DATA: payroll_export.csv (~834 KiB — forces run list) ────
python3 - << 'PYEOF'
import csv, random, os

mnt = "/mnt/ntfs_lab"
out = f"{mnt}/Users/jsmith/Documents/payroll_export.csv"

names = [
    ("Alice","Nguyen"),("Bob","Patel"),("Carol","Kim"),("David","Osei"),
    ("Eve","Santos"),("Frank","Mueller"),("Grace","Chen"),("Henry","Adeyemi"),
    ("Iris","Kowalski"),("James","Rivera"),
]
depts = ["Engineering","Finance","Legal","Operations","HR"]
random.seed(4623)

rows = []
for i in range(1, 18000):  # 17,999 rows → ~834 KiB → forces non-resident $DATA
    fn, ln = names[i % len(names)]
    rows.append({
        "EmployeeID": f"E{i:05d}",
        "FirstName": fn,
        "LastName": ln,
        "Department": depts[i % len(depts)],
        "Salary": round(random.uniform(45000, 145000), 2),
        "SSN_Last4": f"{random.randint(1000,9999)}",
        "BankRoutingLast4": f"{random.randint(1000,9999)}",
    })

with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys())
    w.writeheader()
    w.writerows(rows)
print(f"[*] Wrote {out} ({os.path.getsize(out)//1024} KiB)")
PYEOF

# ── 6. ADS artifacts ───────────────────────────────────────────────────────────

# 6a. Zone.Identifier on a downloaded file (realistic Windows provenance stream)
echo "MZ placeholder — not a real executable" \
    > "${MNT}/Users/jsmith/Downloads/VPN_client_setup.exe"
printf '[ZoneTransfer]\r\nZoneId=3\r\nReferrerUrl=http://transfer.sh/upload\r\nHostUrl=http://transfer.sh/VPN_client_setup.exe\r\n' \
    > "${MNT}/Users/jsmith/Downloads/VPN_client_setup.exe:Zone.Identifier"

# 6b. Credential hidden in an innocuous config file
cat > "${MNT}/Users/jsmith/AppData/Roaming/sync_config.ini" << 'EOF'
[SyncTool v2.1]
server=backup.internal.corp
interval=3600
compression=true
EOF
printf 'api_key=sk-4623-EXFIL-a7f3c9d1e2b8\nremote=sftp://192.168.1.88/drop\n' \
    > "${MNT}/Users/jsmith/AppData/Roaming/sync_config.ini:credentials"

# ── 7. Timestomped files ───────────────────────────────────────────────────────

# 7a. SI Modified + Accessed stomped to 2001 (touch -t sets mtime/atime only;
#     SI Created unchanged, SI MFT Modified set to wall-clock time of this call)
cp "${MNT}/Users/jsmith/Documents/incident_summary.txt" \
   "${MNT}/Users/jsmith/Desktop/project_notes.txt"
sleep 1
touch -t 200101010000 "${MNT}/Users/jsmith/Desktop/project_notes.txt"

# 7b. Only SI Modified stomped — subtler, requires comparing individual fields
cat > "${MNT}/Users/jsmith/Documents/contracts_index.txt" << 'EOF'
Q1 contracts filed: 14
Q2 contracts filed: 11
Status: complete
EOF
sleep 1
touch -m -t 201506150900 "${MNT}/Users/jsmith/Documents/contracts_index.txt"

# ── 8. Files to delete ────────────────────────────────────────────────────────
sync

# 8a. access.log — fully recoverable
cat > "${MNT}/System/Logs/access.log" << 'EOF'
2024-03-11 02:14:03 WS-042 user=jsmith src=192.168.1.88 action=READ  file=payroll_export.csv
2024-03-11 02:19:45 WS-042 user=jsmith src=192.168.1.88 action=COPY  file=contracts_q1.docx
2024-03-11 02:28:07 WS-042 user=jsmith src=192.168.1.88 action=READ  file=keys.pem
2024-03-11 02:31:12 WS-042 user=jsmith src=192.168.1.88 action=COPY  file=payroll_export.csv
EOF
sync
rm "${MNT}/System/Logs/access.log"

# 8b. Renamed then deleted — ffind returns final name; rename visible in $UsnJrnl
cat > "${MNT}/Users/jsmith/Documents/temp_export.csv" << 'EOF'
id,value
1,test
EOF
sync
mv "${MNT}/Users/jsmith/Documents/temp_export.csv" \
   "${MNT}/Users/jsmith/Documents/final_export.csv"
sync
rm "${MNT}/Users/jsmith/Documents/final_export.csv"

# 8c. Moved between directories then deleted — parent MFT entry mismatch
echo "staging file" > "${MNT}/Users/jsmith/Downloads/staging.txt"
sync
mv "${MNT}/Users/jsmith/Downloads/staging.txt" \
   "${MNT}/Users/jsmith/Desktop/staging.txt"
sync
rm "${MNT}/Users/jsmith/Desktop/staging.txt"

# 8d. Small resident deleted file — MFT entry survives, no cluster allocation
echo "draft" > "${MNT}/Users/jsmith/Desktop/draft_note.txt"
sync
rm "${MNT}/Users/jsmith/Desktop/draft_note.txt"

# ── 9. Additional journal activity ────────────────────────────────────────────
cp "${MNT}/Users/jsmith/Documents/payroll_export.csv" \
   "${MNT}/Users/jsmith/Desktop/payroll_export.csv"
sync
mv "${MNT}/Users/jsmith/Desktop/payroll_export.csv" \
   "${MNT}/Users/jsmith/Documents/payroll_export_backup.csv"
sync
rm "${MNT}/Users/jsmith/Documents/payroll_export_backup.csv"

# ── 10. Unmount ────────────────────────────────────────────────────────────────
sync
umount "${MNT}"

# ── 11. Verify ────────────────────────────────────────────────────────────────
echo "[*] Verifying image"
fsstat "${IMAGE}" | grep -E "^(File System Type|Volume Name|Version|Range)"
echo ""
echo "[+] Done.  Image: ${IMAGE}"
echo "    Work read-only:  cp ${IMAGE} ${IMAGE}.bak"
echo "    Mount read-only: mount -t ntfs-3g -o loop,ro ${IMAGE} /mnt/ntfs_lab"
