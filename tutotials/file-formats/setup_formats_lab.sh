#!/usr/bin/env bash
# setup_formats_lab.sh — CSCI 4623 File Formats Lab
# Installs tools, creates ~/formats-lab/, fabricates sample files,
# and stages Python helper scripts.
#
# Fixes applied vs. original:
#  #1  trid removed from apt; downloaded separately (no Ubuntu apt package)
#  #2  binutils added to apt (provides readelf, required by Tasks 6.2–6.4)
#  #3  libxml2-utils added to apt (provides xmllint, required by Task 4.3)
#  #4  PE version resource added via windres .rc compilation
#  #5  photo.jpg DateTime set later than DateTimeOriginal (post-edit story)
#  #6  MP4 GPS written as native ©xyz atom via mutagen.mp4, not XMP
#  #7  MP4 CreateDate set historically (2024-09-14) so FS/container mismatch works
#  #8  ZIP entries include Unix UT extended timestamp extra field
#  #9  imagemagick added to apt (provides identify, used in Task 1.4)
# #10  inspect_jpeg.py SOI print corrected to 2 bytes
# #11  pdfid.py downloaded locally during setup rather than at lab runtime
# #12  Comment added about legacy.doc AppName divergence from report.docx

set -euo pipefail

LAB_DIR="$HOME/formats-lab"
SCRIPTS_DIR="$LAB_DIR/scripts"
PYTHON=python3

echo "[*] Creating lab directories..."
mkdir -p "$LAB_DIR" "$SCRIPTS_DIR"

# ── System tools ──────────────────────────────────────────────────────────────
# FIX #2: binutils added (readelf)
# FIX #3: libxml2-utils added (xmllint)
# FIX #9: imagemagick added (identify)
echo "[*] Installing system tools (requires sudo)..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    libimage-exiftool-perl \
    binwalk \
    pngcheck \
    mingw-w64 \
    upx-ucl \
    ffmpeg \
    libmagic1 \
    libmagic-dev \
    python3-pip \
    unzip \
    xxd \
    binutils \
    libxml2-utils \
    imagemagick \
    libreoffice-core \
    libreoffice-writer

# ── TrID: download and install manually ───────────────────────────────────────
# FIX #1: trid is not available as an Ubuntu apt package.
# Download the Linux binary from the TrID website.
echo "[*] Installing TrID..."
TRID_ZIP="/tmp/trid_linux.zip"
TRID_DEFS_ZIP="/tmp/triddefs.zip"
if wget -q "https://mark0.net/download/trid_linux.zip" -O "$TRID_ZIP" && \
   wget -q "https://mark0.net/download/triddefs.zip"   -O "$TRID_DEFS_ZIP"; then
    sudo unzip -q -o "$TRID_ZIP"      -d /usr/local/bin/
    sudo unzip -q -o "$TRID_DEFS_ZIP" -d /usr/local/bin/
    sudo chmod +x /usr/local/bin/trid
    echo "  [+] trid installed to /usr/local/bin/trid"
else
    echo "  [!] TrID download failed — Task 0.4 will not work."
    echo "      Install manually from https://mark0.net/soft-trid-e.html"
fi

# ── pdfid.py: download and stage locally ─────────────────────────────────────
# FIX #11: Fetched here during setup rather than at lab runtime, so Task 3.4
# works in isolated VM environments without outbound internet access.
echo "[*] Downloading pdfid.py..."
PDFTOOLS_DIR="$LAB_DIR/pdftools"
mkdir -p "$PDFTOOLS_DIR"
if wget -q "https://didierstevens.com/files/software/pdfid_v0_2_8.zip" \
        -O /tmp/pdfid.zip; then
    unzip -q -o /tmp/pdfid.zip -d "$PDFTOOLS_DIR"
    echo "  [+] pdfid.py staged to $PDFTOOLS_DIR"
else
    echo "  [!] pdfid.py download failed — Task 3.4 will not work."
    echo "      Download manually from https://didierstevens.com/files/software/pdfid_v0_2_8.zip"
fi

# ── Python packages ───────────────────────────────────────────────────────────
echo "[*] Installing Python packages..."
pip3 install --break-system-packages --quiet \
    Pillow \
    piexif \
    reportlab \
    python-docx \
    mutagen \
    olefile \
    pefile \
    python-magic \
    pikepdf \
    lxml

# ── Fabricate sample files ────────────────────────────────────────────────────
echo "[*] Fabricating sample files..."

$PYTHON - <<'PYEOF'
import os, struct, zlib, zipfile, io, shutil, datetime
from pathlib import Path

LAB = Path.home() / "formats-lab"

# ─── 1. photo.jpg ─────────────────────────────────────────────────────────────
# JPEG with GPS, device EXIF, and a thumbnail that differs from the main image.
# FIX #5: DateTime (last-saved-by-software) is now later than DateTimeOriginal
# (capture time), making the post-processing narrative in Task 1.2 observable.
import piexif
from PIL import Image

main_img = Image.new("RGB", (640, 480), color=(70, 130, 180))

# Thumbnail is a different color — represents the original pre-edit version
thumb_img = Image.new("RGB", (160, 120), color=(180, 70, 70))
thumb_buf = io.BytesIO()
thumb_img.save(thumb_buf, format="JPEG")
thumb_bytes = thumb_buf.getvalue()

exif_dict = {
    "0th": {
        piexif.ImageIFD.Make:     b"Canon",
        piexif.ImageIFD.Model:    b"Canon EOS 5D Mark IV",
        piexif.ImageIFD.Software: b"Adobe Photoshop 24.0",
        # FIX #5: Post-edit save timestamp — 18 days after capture
        piexif.ImageIFD.DateTime: b"2024:04:02 09:11:33",
    },
    "Exif": {
        piexif.ExifIFD.DateTimeOriginal:  b"2024:03:15 14:23:07",
        piexif.ExifIFD.DateTimeDigitized: b"2024:03:15 14:23:07",
        piexif.ExifIFD.LensModel:         b"EF 24-70mm f/2.8L II USM",
        piexif.ExifIFD.ISOSpeedRatings:   400,
    },
    "GPS": {
        piexif.GPSIFD.GPSLatitudeRef:  b"N",
        piexif.GPSIFD.GPSLatitude:     ((29, 1), (56, 1), (4823, 100)),
        piexif.GPSIFD.GPSLongitudeRef: b"W",
        piexif.GPSIFD.GPSLongitude:    ((90, 1), (4, 1), (2156, 100)),
        piexif.GPSIFD.GPSAltitudeRef:  0,
        piexif.GPSIFD.GPSAltitude:     (3, 1),
        piexif.GPSIFD.GPSDateStamp:    b"2024:03:15",
    },
    "1st": {
        piexif.ImageIFD.JPEGInterchangeFormat:       0,
        piexif.ImageIFD.JPEGInterchangeFormatLength: len(thumb_bytes),
    },
    "thumbnail": thumb_bytes,
}
exif_bytes = piexif.dump(exif_dict)
main_img.save(LAB / "photo.jpg", exif=exif_bytes)
print("  [+] photo.jpg")

# ─── 2. graphic.png ───────────────────────────────────────────────────────────
# PNG with hidden iTXt and tEXt ancillary chunks.
img = Image.new("RGB", (320, 240), color=(100, 200, 100))
buf = io.BytesIO()
img.save(buf, format="PNG")
png_data = buf.getvalue()

def make_png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    length = struct.pack(">I", len(data))
    crc    = struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
    return length + chunk_type + data + crc

keyword   = b"ForensicsNote"
text      = "Processed by LabTool v2.3 on 2024-03-15. Operator: jsmith@example.com. Case: 2024-0847."
itxt_data = keyword + b"\x00\x00\x00\x00\x00" + text.encode("utf-8")
itxt_chunk = make_png_chunk(b"iTXt", itxt_data)

software_data = b"Software\x00GIMP 2.10.36"
text_chunk    = make_png_chunk(b"tEXt", software_data)

iend_offset = png_data.rfind(b"IEND") - 4
new_png = png_data[:iend_offset] + itxt_chunk + text_chunk + png_data[iend_offset:]
(LAB / "graphic.png").write_bytes(new_png)
print("  [+] graphic.png")

# ─── 3. document.pdf ──────────────────────────────────────────────────────────
# PDF with author metadata and an appended incremental update.
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter

pdf_path = LAB / "document.pdf"
c = canvas.Canvas(str(pdf_path), pagesize=letter)
c.setTitle("Q3 Financial Summary")
c.setAuthor("Margaret Chen")
c.setSubject("Quarterly Report")
c.setCreator("Microsoft Word 16.0")
c.setProducer("Acrobat Distiller 23.0")
c.drawString(72, 720, "Q3 Financial Summary")
c.drawString(72, 700, "Prepared by: Margaret Chen")
c.drawString(72, 680, "Date: 2024-09-30")
c.drawString(72, 660, "Revenue: $4,820,000  |  Expenses: $3,210,000  |  Net: $1,610,000")
c.save()

original        = pdf_path.read_bytes()
startxref_pos   = original.rfind(b"startxref")
orig_xref_line  = original[startxref_pos + len(b"startxref"):].split(b"\n")[1].strip()
orig_xref       = int(orig_xref_line)

new_obj = (
    b"\n%% Incremental update -- reviewer annotation\n"
    b"20 0 obj\n"
    b"<< /Type /Annot /Subtype /Text\n"
    b"   /Contents (Reviewed by: D. Torres 2024-10-02. Figures verified.)\n"
    b"   /Author (D. Torres) >>\n"
    b"endobj\n"
)
new_xref_offset = len(original) + len(new_obj)
incremental  = new_obj
incremental += b"xref\n20 1\n"
incremental += f"{new_xref_offset + 44:010d} 00000 n \n".encode()
incremental += b"trailer\n<< /Size 21 /Prev " + str(orig_xref).encode() + b" >>\n"
incremental += b"startxref\n" + str(new_xref_offset).encode() + b"\n%%EOF\n"
pdf_path.write_bytes(original + incremental)
print("  [+] document.pdf")

# ─── 4. report.docx ───────────────────────────────────────────────────────────
from docx import Document

doc = Document()
doc.core_properties.author          = "James Wilson"
doc.core_properties.last_modified_by = "Sarah Okonkwo"
doc.core_properties.title           = "Project Proposal — Q2 2024"
doc.core_properties.subject         = "Internal Planning Document"
doc.core_properties.keywords        = "proposal, budget, Q2"
doc.core_properties.created         = datetime.datetime(2024, 1, 10, 9, 0, 0)
doc.core_properties.modified        = datetime.datetime(2024, 3, 22, 16, 45, 0)
doc.core_properties.revision        = 7
doc.add_heading("Project Proposal — Q2 2024", 0)
doc.add_paragraph(
    "This document outlines the proposed approach for Q2 deliverables "
    "as discussed during the January planning session."
)
doc.add_paragraph("Budget estimate: $142,000 (revised upward from initial $98,000).")
doc.add_paragraph("Primary contact: James Wilson, jwilson@meridiananalytics.com")
doc.add_paragraph("Secondary contact: Sarah Okonkwo, sokonkwo@meridiananalytics.com")
doc.save(LAB / "report.docx")
print("  [+] report.docx")

# ─── 5. archive.zip ───────────────────────────────────────────────────────────
# ZIP with EOCD comment and Unix UT extended timestamp extra fields on entries.
# FIX #8: Python's zipfile module does not write UT extra fields by default.
# We build the archive manually so each entry carries a Unix extended timestamp,
# making Task 5.2's discussion of extended timestamps observable.

def make_ut_extra(mtime_unix: int, include_atime: bool = False) -> bytes:
    """Build a Unix Extended Timestamp (UT) extra field block."""
    flags   = 0x01  # mtime present
    payload = struct.pack("<I", mtime_unix)
    if include_atime:
        flags  |= 0x02
        payload += struct.pack("<I", mtime_unix)
    data = struct.pack("B", flags) + payload
    return struct.pack("<HH", 0x5455, len(data)) + data  # tag=0x5455 ("UT")

def zip_with_ut_timestamps(entries: list, comment: bytes = b"") -> bytes:
    """Build a ZIP archive with UT extra fields on every entry."""
    buf = io.BytesIO()
    central_dir = []

    for arcname, data, mtime_unix in entries:
        dt      = datetime.datetime.utcfromtimestamp(mtime_unix)
        dostime = (dt.second // 2) | (dt.minute << 5) | (dt.hour << 11)
        dosdate = dt.day | (dt.month << 5) | ((dt.year - 1980) << 9)

        compressed   = zlib.compress(data)[2:-4]  # strip zlib header/trailer
        crc          = zlib.crc32(data) & 0xFFFFFFFF
        local_extra  = make_ut_extra(mtime_unix, include_atime=True)
        name_bytes   = arcname.encode("utf-8")
        local_offset = buf.tell()

        buf.write(struct.pack("<4s2H3H3L2H",
            b"PK\x03\x04", 20, 0, 8,
            dostime, dosdate, crc,
            len(compressed), len(data),
            len(name_bytes), len(local_extra),
        ))
        buf.write(name_bytes)
        buf.write(local_extra)
        buf.write(compressed)

        cd_extra = make_ut_extra(mtime_unix, include_atime=False)
        central_dir.append((name_bytes, cd_extra, crc, len(compressed),
                            len(data), dostime, dosdate, local_offset))

    cd_start = buf.tell()
    for (name_bytes, cd_extra, crc, comp_size, uncomp_size,
         dostime, dosdate, local_offset) in central_dir:
        buf.write(struct.pack("<4s6H3L5H2L",
            b"PK\x01\x02", 0x0314, 20, 0, 8,
            dostime, dosdate, crc, comp_size, uncomp_size,
            len(name_bytes), len(cd_extra), 0, 0, 0,
            0o100644 << 16, local_offset,
        ))
        buf.write(name_bytes)
        buf.write(cd_extra)

    cd_end  = buf.tell()
    cd_size = cd_end - cd_start
    buf.write(struct.pack("<4s4H2LH",
        b"PK\x05\x06", 0, 0,
        len(central_dir), len(central_dir),
        cd_size, cd_start, len(comment),
    ))
    buf.write(comment)
    return buf.getvalue()

t_base = int(datetime.datetime(2024, 10, 15, 9, 32, 0).timestamp())
entries = [
    ("readme.txt",
     b"Project archive \xe2\x80\x94 Q3 2024\nDo not distribute externally.\n",
     t_base),
    ("data/report.csv",
     b"date,amount,category\n2024-07-01,14200,sales\n"
     b"2024-08-01,18300,sales\n2024-09-01,21100,sales\n",
     t_base + 17),
    ("data/notes.txt",
     b"Preliminary figures \xe2\x80\x94 subject to final audit revision.\n",
     t_base + 34),
    ("internal/contacts.txt",
     b"R. Vasquez: rvasquez@example.com\nM. Chen: mchen@example.com\n",
     t_base + 51),
]
eocd_comment = (
    b"CASE-2024-0847 evidence archive. "
    b"Collected: 2024-10-15 09:32 UTC. Examiner: R. Vasquez"
)
(LAB / "archive.zip").write_bytes(
    zip_with_ut_timestamps(entries, comment=eocd_comment)
)
print("  [+] archive.zip")

# ─── 6. firmware.bin ──────────────────────────────────────────────────────────
jpeg_img = Image.new("RGB", (200, 150), color=(200, 180, 160))
jpeg_buf = io.BytesIO()
jpeg_img.save(jpeg_buf, format="JPEG")
jpeg_bytes = jpeg_buf.getvalue()

inner_zip_buf = io.BytesIO()
with zipfile.ZipFile(inner_zip_buf, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(
        "config.txt",
        "device=router-v2\nfirmware_version=3.1.4\nboot_mode=normal\n"
        "admin_hash=5f4dcc3b5aa765d61d8327deb882cf99\n"
    )
    zf.writestr(
        "keys/device.key",
        "-----BEGIN PRIVATE KEY-----\n[PLACEHOLDER \xe2\x80\x94 NOT A REAL KEY]\n"
        "-----END PRIVATE KEY-----\n"
    )
    zf.writestr("log/boot.log",
        "2024-03-10 06:00:01 system boot\n2024-03-10 06:00:03 network up\n")
(LAB / "firmware.bin").write_bytes(jpeg_bytes + inner_zip_buf.getvalue())
print("  [+] firmware.bin")

# ─── 7. Extension mismatch files ──────────────────────────────────────────────
shutil.copy(LAB / "photo.jpg",   LAB / "mismatch1.pdf")
shutil.copy(LAB / "archive.zip", LAB / "mismatch2.docx")
print("  [+] mismatch1.pdf, mismatch2.docx")

print("[*] Python file fabrication complete.")
PYEOF

# ── ELF binaries ──────────────────────────────────────────────────────────────
echo "[*] Staging ELF binaries..."
cp /usr/bin/find "$LAB_DIR/normal.elf"

if command -v upx &>/dev/null; then
    upx --best -o "$LAB_DIR/packed.elf" "$LAB_DIR/normal.elf" -q 2>/dev/null \
        || { echo "  [!] upx failed — packed.elf will be a copy of normal.elf";
             cp "$LAB_DIR/normal.elf" "$LAB_DIR/packed.elf"; }
else
    echo "  [!] upx not found — packed.elf will be a copy of normal.elf"
    cp "$LAB_DIR/normal.elf" "$LAB_DIR/packed.elf"
fi
echo "  [+] normal.elf, packed.elf"

# ── PE binaries ───────────────────────────────────────────────────────────────
# FIX #4: A version resource .rc file is compiled with windres and linked in.
# This ensures VS_VERSIONINFO is present in normal.exe, so inspect_pe.py
# and Task 7.3 find populated ProductName, FileDescription, etc. fields.
echo "[*] Compiling PE binaries with mingw-w64..."

cat > /tmp/lab_normal.c <<'CEOF'
#include <windows.h>
#include <stdio.h>
/* CSCI 4623 lab binary — not for execution */
const char* build_info = "LabTool v1.0 built with MinGW";
int main(void) {
    MessageBoxA(NULL, "Hello from PE binary", "CSCI 4623", MB_OK);
    return 0;
}
CEOF

cat > /tmp/lab_version.rc <<'RCEOF'
#include <winver.h>
VS_VERSION_INFO VERSIONINFO
FILEVERSION    1,0,0,0
PRODUCTVERSION 1,0,0,0
FILEFLAGSMASK  VS_FFI_FILEFLAGSMASK
FILEFLAGS      0
FILEOS         VOS_NT_WINDOWS32
FILETYPE       VFT_APP
FILESUBTYPE    VFT2_UNKNOWN
BEGIN
    BLOCK "StringFileInfo"
    BEGIN
        BLOCK "040904B0"
        BEGIN
            VALUE "CompanyName",      "CSCI 4623 Digital Forensics Lab\0"
            VALUE "FileDescription",  "Lab Tool v1.0 -- forensic analysis sample\0"
            VALUE "FileVersion",      "1.0.0.0\0"
            VALUE "InternalName",     "labtool\0"
            VALUE "LegalCopyright",   "Copyright 2024 University of New Orleans\0"
            VALUE "OriginalFilename", "labtool.exe\0"
            VALUE "ProductName",      "LabTool\0"
            VALUE "ProductVersion",   "1.0.0.0\0"
        END
    END
    BLOCK "VarFileInfo"
    BEGIN
        VALUE "Translation", 0x0409, 0x04B0
    END
END
RCEOF

if x86_64-w64-mingw32-windres /tmp/lab_version.rc \
        -O coff -o /tmp/lab_version.o 2>/dev/null && \
   x86_64-w64-mingw32-gcc /tmp/lab_normal.c \
        /tmp/lab_version.o \
        -o "$LAB_DIR/normal.exe" \
        -luser32 \
        -Wl,--subsystem,windows \
        -D_FORTIFY_SOURCE=0 2>/dev/null; then
    echo "  [+] normal.exe (with version resource)"
    if command -v upx &>/dev/null; then
        upx --best -o "$LAB_DIR/packed.exe" "$LAB_DIR/normal.exe" -q 2>/dev/null \
            && echo "  [+] packed.exe" \
            || { cp "$LAB_DIR/normal.exe" "$LAB_DIR/packed.exe";
                 echo "  [!] upx failed — packed.exe is a copy of normal.exe"; }
    else
        cp "$LAB_DIR/normal.exe" "$LAB_DIR/packed.exe"
        echo "  [!] upx not found — packed.exe is a copy of normal.exe"
    fi
else
    echo "  [!] mingw-w64 compilation failed — PE files not created"
    echo "      Install with: sudo apt-get install mingw-w64"
fi

# ── video.mp4 ─────────────────────────────────────────────────────────────────
# FIX #6: GPS written as native ©xyz QuickTime user data atom via mutagen.mp4,
# not as XMP metadata, matching what iOS devices actually produce.
# FIX #7: ©day set to historical date (2024-09-14) so the embedded container
# timestamp predates the file system mtime, making Task 8.2 discrepancy work.
echo "[*] Creating video.mp4..."
ffmpeg -f lavfi -i color=c=steelblue:size=320x240:rate=5 \
    -t 4 -vcodec libx264 -pix_fmt yuv420p \
    "$LAB_DIR/video.mp4" -y -loglevel quiet

$PYTHON - <<'PYEOF'
from pathlib import Path
from mutagen.mp4 import MP4

mp4_path = Path.home() / "formats-lab" / "video.mp4"
tags = MP4(mp4_path)

# FIX #7: Historical creation date — predates the file system mtime
tags["\xa9day"] = ["2024-09-14T11:47:32"]

# FIX #6: Native ©xyz GPS atom in iOS format: "+lat+lon+alt/"
# Lat: 29.9354°N  Lon: 90.0771°W  Alt: 3m
tags["\xa9xyz"] = ["+29.9354-090.0771+003.000/"]

# Device identity atoms
tags["\xa9too"] = ["iPhone 15 Pro / iOS 17.2.1"]  # encoder string
tags["\xa9mak"] = ["Apple"]
tags["\xa9mod"] = ["iPhone 15 Pro"]

tags.save()
print("  [+] video.mp4 (native \xa9xyz GPS atom, historical \xa9day)")
PYEOF

# ── audio.mp3 ─────────────────────────────────────────────────────────────────
echo "[*] Creating audio.mp3..."
ffmpeg -f lavfi -i "sine=frequency=440:duration=6" \
    -codec:a libmp3lame -q:a 4 \
    "$LAB_DIR/audio.mp3" -y -loglevel quiet

$PYTHON - <<'PYEOF'
from pathlib import Path
from PIL import Image
import io
from mutagen.id3 import (
    ID3, TIT2, TPE1, TALB, TDRC, COMM, APIC, WXXX, ID3NoHeaderError
)

mp3_path = Path.home() / "formats-lab" / "audio.mp3"

try:
    tags = ID3(mp3_path)
except ID3NoHeaderError:
    tags = ID3()

tags.add(TIT2(encoding=3, text="Evidence Track 01"))
tags.add(TPE1(encoding=3, text="Unknown Artist"))
tags.add(TALB(encoding=3, text="Case 2024-0847 Recovery"))
tags.add(TDRC(encoding=3, text="2024"))
tags.add(COMM(
    encoding=3, lang="eng", desc="comment",
    text="Recovered from device NAND storage, logical offset 0x1A3F000. "
         "Hash verified: SHA-256 matches acquisition record."
))
tags.add(WXXX(encoding=3, desc="source",
              url="https://evidence.example.com/case2024-0847/track01"))

cover = Image.new("RGB", (120, 120), color=(180, 100, 60))
cover_buf = io.BytesIO()
cover.save(cover_buf, format="JPEG")
tags.add(APIC(
    encoding=3, mime="image/jpeg", type=3,
    desc="Cover", data=cover_buf.getvalue()
))

tags.save(mp3_path)
print("  [+] audio.mp3 ID3v2 tags written")
PYEOF

# ── legacy.doc (LibreOffice conversion) ───────────────────────────────────────
# FIX #12 (documentation): The author fields (James Wilson, Sarah Okonkwo)
# carry over correctly from report.docx into the OLE SummaryInformation stream,
# so Task 4.5 comparisons work as intended. However, AppName in legacy.doc will
# show "LibreOffice" rather than "Microsoft Word" because LibreOffice performed
# the conversion. The tutorial notes this explicitly so students are not confused.
echo "[*] Creating legacy.doc via LibreOffice..."
if command -v libreoffice &>/dev/null; then
    libreoffice --headless \
        --convert-to doc \
        --outdir "$LAB_DIR" \
        "$LAB_DIR/report.docx" \
        --quiet 2>/dev/null \
    && mv "$LAB_DIR/report.doc" "$LAB_DIR/legacy.doc" \
    && echo "  [+] legacy.doc" \
    || echo "  [!] LibreOffice conversion failed — legacy.doc not created"
else
    echo "  [!] LibreOffice not found — legacy.doc not created"
fi

# ── Python helper scripts ─────────────────────────────────────────────────────
echo "[*] Writing Python helper scripts to $SCRIPTS_DIR..."

# ── scripts/inspect_jpeg.py ───────────────────────────────────────────────────
cat > "$SCRIPTS_DIR/inspect_jpeg.py" <<'PYEOF'
#!/usr/bin/env python3
"""
inspect_jpeg.py — CSCI 4623 File Formats Lab
Prints EXIF fields and extracts the embedded thumbnail from a JPEG file.
Usage: python3 inspect_jpeg.py <file.jpg>
"""
import sys, struct
from pathlib import Path
import piexif

def parse_gps_coord(coord_tuple, ref):
    d, m, s = coord_tuple
    deg = d[0]/d[1] + m[0]/m[1]/60 + s[0]/s[1]/3600
    if ref in (b"S", b"W"):
        deg = -deg
    return round(deg, 6)

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.jpg>")
        sys.exit(1)

    path = Path(sys.argv[1])
    data = path.read_bytes()

    # FIX #10: Print only the 2-byte SOI marker (FF D8).
    # The third byte (FF) is the start of the following APP marker —
    # it is not part of the SOI marker itself.
    if data[:2] != b"\xff\xd8":
        print("[!] Not a JPEG (missing SOI marker)")
        sys.exit(1)
    print(f"[+] SOI marker confirmed: {data[:2].hex().upper()}")

    try:
        exif = piexif.load(data)
    except Exception as e:
        print(f"[!] Could not load EXIF: {e}")
        sys.exit(1)

    ifd0 = exif.get("0th", {})
    print("\n── IFD0 (primary image) ──────────────────────────")
    for tag_id, label in [
        (piexif.ImageIFD.Make,     "Make"),
        (piexif.ImageIFD.Model,    "Model"),
        (piexif.ImageIFD.Software, "Software"),
        (piexif.ImageIFD.DateTime, "DateTime"),
    ]:
        val = ifd0.get(tag_id)
        if val:
            print(f"  {label:20s}: {val.decode(errors='replace')}")

    exif_ifd = exif.get("Exif", {})
    print("\n── Exif IFD ─────────────────────────────────────")
    for tag_id, label in [
        (piexif.ExifIFD.DateTimeOriginal,  "DateTimeOriginal"),
        (piexif.ExifIFD.DateTimeDigitized, "DateTimeDigitized"),
        (piexif.ExifIFD.LensModel,         "LensModel"),
        (piexif.ExifIFD.ISOSpeedRatings,   "ISO"),
    ]:
        val = exif_ifd.get(tag_id)
        if val:
            if isinstance(val, bytes):
                print(f"  {label:20s}: {val.decode(errors='replace')}")
            else:
                print(f"  {label:20s}: {val}")

    gps = exif.get("GPS", {})
    if gps:
        print("\n── GPS IFD ──────────────────────────────────────")
        lat     = gps.get(piexif.GPSIFD.GPSLatitude)
        lat_ref = gps.get(piexif.GPSIFD.GPSLatitudeRef, b"N")
        lon     = gps.get(piexif.GPSIFD.GPSLongitude)
        lon_ref = gps.get(piexif.GPSIFD.GPSLongitudeRef, b"E")
        alt     = gps.get(piexif.GPSIFD.GPSAltitude)
        if lat and lon:
            print(f"  Latitude             : {parse_gps_coord(lat, lat_ref)} ({lat_ref.decode()})")
            print(f"  Longitude            : {parse_gps_coord(lon, lon_ref)} ({lon_ref.decode()})")
        if alt:
            print(f"  Altitude             : {alt[0]/alt[1]:.1f} m")
        ds = gps.get(piexif.GPSIFD.GPSDateStamp)
        if ds:
            print(f"  GPS DateStamp        : {ds.decode()}")

    thumb = exif.get("thumbnail")
    if thumb:
        out = path.with_name(path.stem + "_thumbnail.jpg")
        out.write_bytes(thumb)
        print(f"\n[+] Thumbnail extracted: {out} ({len(thumb)} bytes)")
        print("    Compare thumbnail dimensions and content with the main image.")
    else:
        print("\n[-] No embedded thumbnail found.")

if __name__ == "__main__":
    main()
PYEOF

# ── scripts/inspect_png.py ────────────────────────────────────────────────────
cat > "$SCRIPTS_DIR/inspect_png.py" <<'PYEOF'
#!/usr/bin/env python3
"""
inspect_png.py — CSCI 4623 File Formats Lab
Enumerates all chunks in a PNG file and prints ancillary chunk contents.
Usage: python3 inspect_png.py <file.png>
"""
import sys, struct, zlib
from pathlib import Path

PNG_SIG  = b"\x89PNG\r\n\x1a\n"
CRITICAL = {b"IHDR", b"PLTE", b"IDAT", b"IEND"}

def read_chunks(data):
    pos, chunks = 8, []
    while pos < len(data):
        if pos + 8 > len(data):
            break
        length     = struct.unpack(">I", data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+length]
        crc_stored = struct.unpack(">I", data[pos+8+length:pos+12+length])[0]
        crc_calc   = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        chunks.append({"type": chunk_type, "length": length, "data": chunk_data,
                        "crc_ok": crc_stored == crc_calc, "offset": pos})
        pos += 12 + length
    return chunks

def decode_text_chunk(chunk_type, data):
    if chunk_type == b"tEXt":
        null = data.index(b"\x00")
        return data[:null].decode("latin-1"), data[null+1:].decode("latin-1")
    elif chunk_type == b"iTXt":
        null    = data.index(b"\x00")
        keyword = data[:null].decode("latin-1")
        rest    = data[null+1:]
        comp_flag = rest[0]
        lang_end  = rest.index(b"\x00", 2)
        tkw_end   = rest.index(b"\x00", lang_end + 1)
        text_bytes = rest[tkw_end+1:]
        if comp_flag:
            text_bytes = zlib.decompress(text_bytes)
        return keyword, text_bytes.decode("utf-8", errors="replace")
    elif chunk_type == b"zTXt":
        null    = data.index(b"\x00")
        keyword = data[:null].decode("latin-1")
        return keyword, zlib.decompress(data[null+2:]).decode("latin-1", errors="replace")
    return None, None

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.png>")
        sys.exit(1)
    path = Path(sys.argv[1])
    data = path.read_bytes()
    if data[:8] != PNG_SIG:
        print("[!] Not a valid PNG file (signature mismatch)")
        sys.exit(1)
    print("[+] PNG signature confirmed")

    chunks = read_chunks(data)
    print(f"\n── Chunk inventory ({len(chunks)} chunks) ────────────────────")
    print(f"  {'#':>3}  {'Type':8}  {'Offset':>10}  {'Length':>8}  {'Kind':10}  CRC")
    print(f"  {'─'*3}  {'─'*8}  {'─'*10}  {'─'*8}  {'─'*10}  {'─'*3}")
    for i, ch in enumerate(chunks):
        kind       = "critical" if ch["type"] in CRITICAL else "ancillary"
        crc_status = "OK" if ch["crc_ok"] else "FAIL"
        print(f"  {i:>3}  {ch['type'].decode():8}  {ch['offset']:>10}  "
              f"{ch['length']:>8}  {kind:10}  {crc_status}")

    text_chunks = [ch for ch in chunks if ch["type"] in {b"tEXt", b"iTXt", b"zTXt"}]
    if text_chunks:
        print(f"\n── Text chunk contents ({len(text_chunks)} found) ──────────────")
        for ch in text_chunks:
            try:
                keyword, text = decode_text_chunk(ch["type"], ch["data"])
                print(f"\n  Type    : {ch['type'].decode()}")
                print(f"  Keyword : {keyword}")
                print(f"  Text    : {text}")
            except Exception as e:
                print(f"  [!] Could not decode chunk: {e}")
    else:
        print("\n[-] No text chunks found.")

if __name__ == "__main__":
    main()
PYEOF

# ── scripts/inspect_ole.py ────────────────────────────────────────────────────
cat > "$SCRIPTS_DIR/inspect_ole.py" <<'PYEOF'
#!/usr/bin/env python3
"""
inspect_ole.py — CSCI 4623 File Formats Lab
Lists streams in an OLE/CFB file and dumps SummaryInformation metadata.
Usage: python3 inspect_ole.py <file.doc>
"""
import sys
from pathlib import Path
import olefile

def filetime_to_str(ft):
    if ft is None:
        return "(not set)"
    return ft.strftime("%Y-%m-%d %H:%M:%S UTC")

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.doc>")
        sys.exit(1)
    path = Path(sys.argv[1])
    if not olefile.isOleFile(path):
        print(f"[!] {path.name} is not a valid OLE/CFB file")
        sys.exit(1)

    ole = olefile.OleFileIO(path)
    print(f"[+] OLE file confirmed: {path.name}")

    print(f"\n── Directory tree (streams and storages) ────────────────")
    for entry in sorted(ole.listdir(streams=True, storages=True)):
        path_str = "/".join(entry)
        try:
            size = ole.get_size(entry)
            print(f"  {path_str:<50}  {size:>8} bytes")
        except Exception:
            print(f"  {path_str:<50}  [storage]")

    print(f"\n── SummaryInformation ───────────────────────────────────")
    try:
        meta   = ole.get_metadata()
        fields = [
            ("Author",        meta.author),
            ("Last saved by", meta.last_saved_by),
            ("Title",         meta.title),
            ("Subject",       meta.subject),
            ("Keywords",      meta.keywords),
            ("Revision",      meta.revision_number),
            ("Created",       filetime_to_str(meta.create_time)),
            ("Last saved",    filetime_to_str(meta.last_saved_time)),
            ("Last printed",  filetime_to_str(meta.last_printed)),
            ("Num words",     meta.num_words),
            ("Num chars",     meta.num_chars),
            ("Company",       meta.company),
            ("Manager",       meta.manager),
            # FIX #12: AppName shows "LibreOffice" here — the conversion tool —
            # not "Microsoft Word". The tutorial notes this explicitly.
            ("App name",      meta.app_name),
        ]
        for label, value in fields:
            if value is not None and value != b"":
                if isinstance(value, bytes):
                    value = value.decode("utf-8", errors="replace")
                print(f"  {label:<20}: {value}")
    except Exception as e:
        print(f"  [!] Could not read metadata: {e}")

    if ole.exists("Macros") or ole.exists("_VBA_PROJECT_CUR"):
        print(f"\n[!] VBA macro storage detected — further analysis recommended")
    else:
        print(f"\n[-] No VBA macro storage found")

    ole.close()

if __name__ == "__main__":
    main()
PYEOF

# ── scripts/inspect_pe.py ─────────────────────────────────────────────────────
cat > "$SCRIPTS_DIR/inspect_pe.py" <<'PYEOF'
#!/usr/bin/env python3
"""
inspect_pe.py — CSCI 4623 File Formats Lab
Prints PE headers, sections, imports, version info, and debug directory.
Usage: python3 inspect_pe.py <file.exe>
"""
import sys, datetime
from pathlib import Path
import pefile

def ts_to_str(ts):
    try:
        return datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        return f"0x{ts:08X} (invalid)"

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file.exe>")
        sys.exit(1)
    path = Path(sys.argv[1])
    try:
        pe = pefile.PE(str(path))
    except pefile.PEFormatError as e:
        print(f"[!] Not a valid PE file: {e}")
        sys.exit(1)

    print(f"[+] PE file confirmed: {path.name}")

    print(f"\n── COFF header ──────────────────────────────────────────")
    machine = pe.FILE_HEADER.Machine
    print(f"  Machine              : {pefile.MACHINE_TYPE.get(machine, f'0x{machine:04X}')}")
    print(f"  Compile timestamp    : {ts_to_str(pe.FILE_HEADER.TimeDateStamp)}")
    print(f"  Characteristics      : 0x{pe.FILE_HEADER.Characteristics:04X}")

    oh = pe.OPTIONAL_HEADER
    print(f"\n── Optional header ──────────────────────────────────────")
    print(f"  Magic                : 0x{oh.Magic:04X} ({'PE32+' if oh.Magic == 0x20b else 'PE32'})")
    print(f"  Entry point (RVA)    : 0x{oh.AddressOfEntryPoint:08X}")
    print(f"  Image base           : 0x{oh.ImageBase:016X}")
    print(f"  Subsystem            : {pefile.SUBSYSTEM_TYPE.get(oh.Subsystem, f'0x{oh.Subsystem:04X}')}")

    print(f"\n── Sections ({len(pe.sections)}) ──────────────────────────────────────")
    print(f"  {'Name':10}  {'VirtAddr':>12}  {'VirtSize':>10}  {'RawSize':>10}  {'Entropy':>8}")
    print(f"  {'─'*10}  {'─'*12}  {'─'*10}  {'─'*10}  {'─'*8}")
    for sec in pe.sections:
        name = sec.Name.rstrip(b"\x00").decode("ascii", errors="replace")
        print(f"  {name:10}  0x{sec.VirtualAddress:08X}    "
              f"{sec.Misc_VirtualSize:>10}  {sec.SizeOfRawData:>10}  "
              f"{sec.get_entropy():>8.3f}")

    if hasattr(pe, "DIRECTORY_ENTRY_IMPORT"):
        print(f"\n── Imports ──────────────────────────────────────────────")
        for entry in pe.DIRECTORY_ENTRY_IMPORT:
            dll   = entry.dll.decode("ascii", errors="replace")
            funcs = [
                imp.name.decode("ascii", errors="replace") if imp.name
                else f"ordinal {imp.ordinal}"
                for imp in entry.imports
            ]
            print(f"  {dll}")
            for f in funcs[:8]:
                print(f"    {f}")
            if len(funcs) > 8:
                print(f"    ... ({len(funcs) - 8} more)")

    if hasattr(pe, "VS_VERSIONINFO"):
        print(f"\n── Version info ─────────────────────────────────────────")
        if hasattr(pe, "FileInfo"):
            for fi in pe.FileInfo:
                for entry in fi:
                    if hasattr(entry, "StringTable"):
                        for st in entry.StringTable:
                            for k, v in st.entries.items():
                                print(f"  {k.decode():25}: {v.decode()}")

    if hasattr(pe, "DIRECTORY_ENTRY_DEBUG"):
        print(f"\n── Debug directory ──────────────────────────────────────")
        for dbg in pe.DIRECTORY_ENTRY_DEBUG:
            if hasattr(dbg.entry, "PdbFileName"):
                pdb = dbg.entry.PdbFileName.rstrip(b"\x00").decode("ascii", errors="replace")
                print(f"  PDB path             : {pdb}")

    pe.close()

if __name__ == "__main__":
    main()
PYEOF

# ── scripts/inspect_elf.py ────────────────────────────────────────────────────
cat > "$SCRIPTS_DIR/inspect_elf.py" <<'PYEOF'
#!/usr/bin/env python3
"""
inspect_elf.py — CSCI 4623 File Formats Lab
Prints ELF header fields, section inventory, Build ID, and .comment content.
Usage: python3 inspect_elf.py <file>
"""
import sys, struct, subprocess
from pathlib import Path

ELF_MAGIC = b"\x7fELF"
OSABI     = {0x00: "System V", 0x03: "Linux", 0x06: "Solaris",
             0x09: "FreeBSD", 0x0C: "OpenBSD"}
E_TYPE    = {1: "ET_REL (relocatable)", 2: "ET_EXEC (executable)",
             3: "ET_DYN (shared object)", 4: "ET_CORE (core dump)"}
E_MACHINE = {0x3E: "x86-64 (AMD64)", 0x28: "ARM", 0xB7: "AArch64",
             0x02: "SPARC", 0x08: "MIPS", 0x14: "PowerPC"}

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <file>")
        sys.exit(1)
    path = Path(sys.argv[1])
    data = path.read_bytes()

    if data[:4] != ELF_MAGIC:
        print(f"[!] Not an ELF file (magic: {data[:4].hex()})")
        sys.exit(1)

    ei_class = data[4]
    ei_data  = data[5]
    ei_osabi = data[7]
    endian   = "<" if ei_data == 1 else ">"
    bits     = 32 if ei_class == 1 else 64

    print(f"[+] ELF file confirmed: {path.name}")
    print(f"\n── ELF identification ───────────────────────────────────")
    print(f"  Class                : ELF{bits}")
    print(f"  Data encoding        : {'Little-endian' if ei_data == 1 else 'Big-endian'}")
    print(f"  OS/ABI               : {OSABI.get(ei_osabi, f'0x{ei_osabi:02X}')}")

    fmt = "HHIQQQIHHHHHH" if bits == 64 else "HHIIIIIHHHHHH"
    (e_type, e_machine, _, e_entry, *_rest) = struct.unpack_from(f"{endian}{fmt}", data, 16)
    print(f"  Type                 : {E_TYPE.get(e_type, f'0x{e_type:04X}')}")
    print(f"  Machine              : {E_MACHINE.get(e_machine, f'0x{e_machine:04X}')}")
    width = 16 if bits == 64 else 8
    print(f"  Entry point          : 0x{e_entry:0{width}X}")

    def run_readelf(args):
        try:
            return subprocess.run(["readelf"] + args + [str(path)],
                                  capture_output=True, text=True)
        except FileNotFoundError:
            return None

    print(f"\n── Sections ─────────────────────────────────────────────")
    r = run_readelf(["-S", "--wide"])
    if r is None:
        print("  [!] readelf not found — install binutils")
    else:
        lines = [l for l in r.stdout.splitlines()
                 if l.strip() and "[" in l
                 and not l.strip().startswith("[Nr]")
                 and not l.strip().startswith("There are")
                 and "Key to Flags" not in l]
        for line in lines[:20]:
            print(f"  {line}")
        if len(lines) > 20:
            print(f"  ... ({len(lines)-20} more sections)")

    print(f"\n── Notes (.note sections) ───────────────────────────────")
    r = run_readelf(["-n"])
    if r:
        for line in r.stdout.splitlines():
            if line.strip():
                print(f"  {line}")

    print(f"\n── .comment section ─────────────────────────────────────")
    r = run_readelf(["-p", ".comment"])
    if r and r.returncode == 0:
        for line in r.stdout.splitlines():
            if line.strip():
                print(f"  {line}")
    else:
        print("  [-] No .comment section found (binary may be stripped)")

    r2 = subprocess.run(["file", str(path)], capture_output=True, text=True)
    print(f"\n── Strip status ─────────────────────────────────────────")
    print(f"  {r2.stdout.strip()}")

if __name__ == "__main__":
    main()
PYEOF

chmod +x "$SCRIPTS_DIR"/*.py

# ── Verify file manifest ──────────────────────────────────────────────────────
echo ""
echo "[*] File manifest:"
echo ""
printf "  %-22s  %s\n" "Filename" "Description"
printf "  %-22s  %s\n" "──────────────────────" "──────────────────────────────────────────────────"
for f in \
    "photo.jpg:JPEG — GPS EXIF, DateTime > DateTimeOriginal, thumbnail mismatch" \
    "graphic.png:PNG — hidden iTXt (operator/case) and tEXt (Software) chunks" \
    "document.pdf:PDF — author metadata, incremental update with reviewer" \
    "report.docx:OOXML — author chain (Wilson → Okonkwo), revision 7" \
    "legacy.doc:OLE/CFB — SummaryInformation (AppName=LibreOffice, see Task 4.5)" \
    "archive.zip:ZIP — EOCD comment, Unix UT extended timestamps on all entries" \
    "firmware.bin:JPEG+ZIP — ZIP appended after JPEG EOI marker" \
    "normal.elf:ELF — unstripped /usr/bin/find, Build ID, .comment" \
    "packed.elf:ELF — UPX-packed (high entropy, stripped sections)" \
    "normal.exe:PE — cross-compiled with version resource and imports" \
    "packed.exe:PE — UPX-packed (minimal imports, high-entropy .text)" \
    "video.mp4:MP4 — native ©xyz GPS atom, historical ©day CreateDate" \
    "audio.mp3:MP3 — ID3v2 tags, embedded APIC JPEG, WXXX URL frame" \
    "mismatch1.pdf:JPEG renamed .pdf — extension mismatch" \
    "mismatch2.docx:ZIP renamed .docx — extension mismatch"; do
    name="${f%%:*}"
    desc="${f#*:}"
    if [ -f "$LAB_DIR/$name" ]; then
        size=$(du -h "$LAB_DIR/$name" | cut -f1)
        printf "  %-22s  %-52s  %s\n" "$name" "$desc" "$size"
    else
        printf "  %-22s  %-52s  %s\n" "$name" "$desc" "[NOT CREATED]"
    fi
done

echo ""
echo "[*] Helper scripts:"
ls -1 "$SCRIPTS_DIR"

if [ -d "$LAB_DIR/pdftools" ]; then
    echo ""
    echo "[*] PDF analysis tools:"
    ls -1 "$LAB_DIR/pdftools"
fi

echo ""
echo "[✓] Setup complete. Lab directory: $LAB_DIR"
echo "    To verify all files: cd $LAB_DIR && file -i *"
