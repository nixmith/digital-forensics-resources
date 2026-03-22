# CSCI 4623 — File Formats Lab: Setup Guide

This document describes all prerequisites and setup steps for the File Formats
hands-on lab. Read it in full before running the setup script.

---

## VM requirements

| Property | Requirement |
|---|---|
| OS | Ubuntu 22.04 LTS or 24.04 LTS (64-bit) |
| RAM | 4 GB minimum; 8 GB recommended |
| Disk | 10 GB free space in home directory |
| Network | Outbound HTTPS required during setup (see below) |
| Architecture | x86-64 only (mingw-w64 cross-compiler produces x86-64 PE binaries) |

The setup script will not run correctly on ARM VMs (e.g., Apple Silicon UTM
with an Ubuntu ARM image). Use an x86-64 image.

---

## Outbound network access required during setup

The setup script downloads three items that are not available via apt. These
downloads happen only once at setup time. After setup completes, the lab can
run offline.

| Item | URL | Purpose |
|---|---|---|
| TrID binary | `https://mark0.net/download/trid_linux.zip` | Format identification tool (Task 0.4) |
| TrID definitions | `https://mark0.net/download/triddefs.zip` | Signature database for TrID |
| pdfid.py | `https://didierstevens.com/files/software/pdfid_v0_2_8.zip` | PDF active content scanner (Task 3.4) |

If your VM does not have outbound internet access, download these files
manually on another machine, transfer them to the VM, and place them at the
paths shown in the fallback instructions printed by the setup script.

---

## Sudo access

The setup script requires `sudo` to:

- Run `apt-get update` and `apt-get install`
- Install TrID to `/usr/local/bin/`

The student account must be in the `sudo` group. Verify with:

```bash
groups $USER | grep sudo
```

If `sudo` is not listed, add the account:

```bash
su -c "usermod -aG sudo $USER" root
# then log out and back in
```

---

## System packages installed by the script

All of the following are installed via `apt-get`. The script handles
installation automatically; this list is provided for reference and for
pre-staging on air-gapped VMs.

| Package | Provides | Used in |
|---|---|---|
| `libimage-exiftool-perl` | `exiftool` | Tasks 1, 3, 4, 8 |
| `binwalk` | `binwalk` | Tasks 5, 6, 7 |
| `pngcheck` | `pngcheck` | Task 2 |
| `mingw-w64` | `x86_64-w64-mingw32-gcc`, `x86_64-w64-mingw32-windres` | PE binary fabrication |
| `upx-ucl` | `upx` | Packed ELF and PE fabrication |
| `ffmpeg` | `ffmpeg` | MP4 and MP3 fabrication |
| `libmagic1`, `libmagic-dev` | libmagic C library | `python-magic` Python package |
| `python3-pip` | `pip3` | Python package installation |
| `unzip` | `unzip` | Tasks 0, 4; TrID/pdfid install |
| `xxd` | `xxd` | Tasks 1, 2 |
| `binutils` | `readelf` | Tasks 6.2, 6.3, 6.4; `inspect_elf.py` |
| `libxml2-utils` | `xmllint` | Task 4.3 |
| `imagemagick` | `identify` | Task 1.4 (optional) |
| `libreoffice-core`, `libreoffice-writer` | `libreoffice` | `legacy.doc` fabrication |

> **Note:** `trid` is not available as an Ubuntu apt package. The script
> downloads and installs it separately from mark0.net.

---

## Python packages installed by the script

All installed via `pip3 install --break-system-packages`.

| Package | Version constraint | Purpose |
|---|---|---|
| `Pillow` | any | Image fabrication (JPEG, PNG, BMP) |
| `piexif` | any | JPEG EXIF construction and parsing |
| `reportlab` | any | PDF fabrication |
| `python-docx` | any | OOXML `.docx` fabrication |
| `mutagen` | any | MP3 ID3 tags and MP4 atom writing |
| `olefile` | any | OLE/CFB stream inspection (`inspect_ole.py`) |
| `pefile` | any | PE header inspection (`inspect_pe.py`) |
| `python-magic` | any | libmagic Python bindings |
| `pikepdf` | any | PDF parsing (available for extension tasks) |
| `lxml` | any | XML parsing |

> **Note on `--break-system-packages`:** Ubuntu 22.04+ uses PEP 668 to
> protect system Python from `pip` installs. The flag is required and safe
> in the course VM context. If your VM uses a virtual environment by default,
> activate it before running the script and remove the flag.

---

## Files produced by the script

After a successful run, `~/formats-lab/` will contain the following files.

```
~/formats-lab/
├── photo.jpg           JPEG — GPS EXIF, thumbnail mismatch, post-edit DateTime
├── graphic.png         PNG — hidden iTXt and tEXt ancillary chunks
├── document.pdf        PDF — author metadata, incremental update
├── report.docx         OOXML — author chain, revision 7
├── legacy.doc          OLE/CFB — converted from report.docx via LibreOffice
├── archive.zip         ZIP — EOCD comment, Unix UT extended timestamps
├── firmware.bin        JPEG+ZIP — ZIP appended after JPEG EOI
├── normal.elf          ELF — unstripped /usr/bin/find copy
├── packed.elf          ELF — UPX-packed version of normal.elf
├── normal.exe          PE  — cross-compiled with version resource
├── packed.exe          PE  — UPX-packed version of normal.exe
├── video.mp4           MP4 — native ©xyz GPS atom, historical CreateDate
├── audio.mp3           MP3 — ID3v2 tags with embedded JPEG (APIC frame)
├── mismatch1.pdf       JPEG renamed .pdf (extension mismatch)
├── mismatch2.docx      ZIP renamed .docx (extension mismatch)
├── scripts/
│   ├── inspect_jpeg.py
│   ├── inspect_png.py
│   ├── inspect_ole.py
│   ├── inspect_pe.py
│   └── inspect_elf.py
└── pdftools/
    └── pdfid.py
```

The script prints a manifest with file sizes at the end. Any file that could
not be created is flagged `[NOT CREATED]` — see the troubleshooting section.

---

## Running the setup script

```bash
chmod +x setup_formats_lab.sh
./setup_formats_lab.sh
```

Expected runtime: 3–8 minutes depending on network speed and whether
LibreOffice is already installed.

At the end, run the verification command printed by the script:

```bash
cd ~/formats-lab && file -i *
```

All 15 sample files should be identified. Correct MIME types are shown in
the manifest at the bottom of the script's output.

---

## Partial failures and fallbacks

The script is written so that failures in optional components do not abort the
entire run (`set -euo pipefail` applies to the shell, but individual
conditional blocks catch their own errors).

| Component | Failure symptom | Impact | Manual fix |
|---|---|---|---|
| TrID download | `[!] TrID download failed` | Task 0.4 skipped | Download from https://mark0.net/soft-trid-e.html; unzip to `/usr/local/bin/`; `chmod +x /usr/local/bin/trid` |
| pdfid.py download | `[!] pdfid.py download failed` | Task 3.4 skipped | Download from https://didierstevens.com/files/software/pdfid_v0_2_8.zip; unzip to `~/formats-lab/pdftools/` |
| mingw-w64 compilation | `[!] mingw-w64 compilation failed` | `normal.exe`, `packed.exe` not created; Tasks 7 skipped | `sudo apt-get install mingw-w64`; re-run script |
| UPX not found | `[!] upx not found` | `packed.elf`, `packed.exe` are copies of unpacked versions; entropy contrast in Tasks 6.5, 7.2 not visible | `sudo apt-get install upx-ucl`; re-run script |
| LibreOffice failure | `[!] LibreOffice conversion failed` | `legacy.doc` not created; Task 4.5 skipped | `sudo apt-get install libreoffice-core libreoffice-writer`; re-run script |

---

## Known differences from a real forensic environment

These are intentional simplifications for the lab setting.

**`normal.exe` and `packed.exe`** are cross-compiled on Linux with mingw-w64,
not compiled on Windows. The COFF compile timestamp, Rich header, and version
resource will reflect the Linux build environment. The binaries are not
executable on the student VM without Wine.

**`legacy.doc`** is produced by LibreOffice converting `report.docx`. The
`App name` field in its OLE `SummaryInformation` stream will show `LibreOffice`
rather than `Microsoft Word`. All other metadata fields (author, last saved by,
timestamps) carry over correctly from the source document. Task 4.5 addresses
this explicitly.

**`video.mp4`** is a synthetic color-field video generated by ffmpeg, not a
real device recording. The `©xyz` GPS atom and `©day` creation date are
injected via mutagen after generation. The file system `mtime` will reflect
the time the setup script ran, which is intentionally later than the embedded
`©day` timestamp — this discrepancy is the artifact examined in Task 8.2.

**`packed.elf`** and **`packed.exe`** are packed with UPX. UPX-packed binaries
are legitimate tools for binary size reduction, not inherently malicious.
They are used here only to demonstrate high-entropy section profiles and
minimal import tables. Do not run these binaries outside the lab.
