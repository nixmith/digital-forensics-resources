---
title: "Block Hashes & Known-File Filtering"
subtitle: "CSCI 4623 — Digital Forensics — Hands-on Exercise"
css: blockhash-exercise.css
---

## Overview

In this exercise you will use **block hashing** to identify known content
on a disk image — including a file that has been deleted. You will start
with a scripted, manual approach to understand the mechanics, then
graduate to `hashdb` for the real-tool workflow. Along the way, you will
use TSK tools to investigate matched blocks and recover the deleted file.

**Time:** ~25 minutes
**Prerequisites:** TSK tools (`blkstat`, `blkcat`, `ifind`, `icat`), basic shell scripting
**Block size:** 4096 bytes (one ext4 filesystem block)


## Setup

Run the setup script to create the lab environment:

```bash
chmod +x setup_blockhash_lab.sh
sudo bash setup_blockhash_lab.sh
```

This creates:

| File | Status | Type |
|------|--------|------|
| `blockhash_lab.img` | — | 64 MB ext4 disk image |
| `reference/memo.txt` | allocated | known reference |
| `reference/known_app.bin` | allocated | known reference |
| `reference/secret_config.conf` | **deleted** | known reference (your target) |

The image also contains three "unknown" decoy files (`README.txt`,
`random_data.bin`, `system.log`) that should **not** match any reference
hashes.


## Task 1 — Manual block hashing

Hash the entire disk image in 4096-byte blocks. This is the scripted
approach — slow but transparent.

```bash
IMG="blockhash_lab.img"
BLOCK_SIZE=4096
TOTAL_BLOCKS=$(($(stat -c%s "$IMG") / BLOCK_SIZE))

echo "Hashing ${TOTAL_BLOCKS} blocks..."

for ((i=0; i<TOTAL_BLOCKS; i++)); do
    HASH=$(dd if="$IMG" bs=$BLOCK_SIZE skip=$i count=1 2>/dev/null \
           | sha256sum | awk '{print $1}')
    echo "${i},${HASH}"
done > image_hashes.csv

echo "Done. $(wc -l < image_hashes.csv) block hashes written to image_hashes.csv"
```

Examine the output:

```bash
head -20 image_hashes.csv
wc -l image_hashes.csv
```

**Questions to consider:**

- How many total blocks were hashed?
- Do you notice any repeated hash values? What might they represent?

> **Hint:** blocks of all zeros will all share the same hash. You can check
> with:
>
> ```bash
> ZERO_HASH=$(dd if=/dev/zero bs=4096 count=1 2>/dev/null | sha256sum | awk '{print $1}')
> grep -c "$ZERO_HASH" image_hashes.csv
> ```


## Task 2 — Build a reference hash set

Hash each known reference file block-by-block using the same block size:

```bash
for FILE in reference/*; do
    FNAME=$(basename "$FILE")
    FILE_BLOCKS=$(( ($(stat -c%s "$FILE") + BLOCK_SIZE - 1) / BLOCK_SIZE ))
    for ((i=0; i<FILE_BLOCKS; i++)); do
        HASH=$(dd if="$FILE" bs=$BLOCK_SIZE skip=$i count=1 2>/dev/null \
               | sha256sum | awk '{print $1}')
        echo "${HASH},${FNAME},block_${i}"
    done
done > reference_hashes.csv

echo "Reference set: $(wc -l < reference_hashes.csv) block hashes"
cat reference_hashes.csv
```

**Questions to consider:**

- How many blocks does each reference file occupy?
- Why is it important that the reference hashes use the same block size (4096)?


## Task 3 — Compare and identify matches

Match image block hashes against the reference set:

```bash
# Extract just the hash column from each file
cut -d',' -f2 image_hashes.csv  | sort -u > image_hash_values.txt
cut -d',' -f1 reference_hashes.csv | sort -u > ref_hash_values.txt

# Find common hashes (excluding all-zeros)
ZERO_HASH=$(dd if=/dev/zero bs=4096 count=1 2>/dev/null \
            | sha256sum | awk '{print $1}')

comm -12 image_hash_values.txt ref_hash_values.txt \
  | grep -v "$ZERO_HASH" > matched_hashes.txt

echo "=== Matched hashes (excluding zeros) ==="
echo "$(wc -l < matched_hashes.txt) block hashes matched"
echo ""

# For each match, show which image block and which reference file
while read HASH; do
    IMG_BLOCK=$(grep "$HASH" image_hashes.csv | cut -d',' -f1)
    REF_INFO=$(grep "$HASH" reference_hashes.csv | cut -d',' -f2,3)
    echo "Block ${IMG_BLOCK} -> ${REF_INFO}  [${HASH:0:16}...]"
done < matched_hashes.txt
```

**This is the key moment.** You should see matches from:

- `memo.txt` — allocated, expected
- `known_app.bin` — allocated, expected
- `secret_config.conf` — **this file was deleted**, but its blocks are still on disk

Whole-file hashing would have missed `secret_config.conf` entirely because
it no longer appears in the directory. Block hashing found it anyway.


## Task 4 — TSK investigation of matched blocks

Pick one of the blocks that matched `secret_config.conf` and investigate
with TSK. Replace `BLOCK_NUM` below with the actual block number from your
Task 3 output.

```bash
IMG="blockhash_lab.img"
BLOCK_NUM=<your block number here>
```

### Check allocation status

```bash
blkstat "$IMG" "$BLOCK_NUM"
```

You should see the block is **not allocated** — it belongs to a deleted
file.

### Extract and inspect the block

```bash
blkcat "$IMG" "$BLOCK_NUM" | xxd | head -20
blkcat "$IMG" "$BLOCK_NUM" | strings
```

You should recognize content from `secret_config.conf` (database
credentials, API keys).

### Find the inode that owned this block

```bash
ifind -d "$IMG" "$BLOCK_NUM"
```

This returns the inode number of the deleted file. The inode metadata may
still be intact even though the file was removed from the directory.

### Recover the full file

```bash
INODE=$(ifind -d "$IMG" "$BLOCK_NUM")
icat "$IMG" "$INODE" > recovered_config.conf
cat recovered_config.conf
```

Compare with the original:

```bash
diff recovered_config.conf reference/secret_config.conf
```

If the blocks haven't been overwritten, the recovery should be identical.

> **The pipeline in action:**
> block hash match → `blkstat` (confirm unallocated) → `blkcat` (inspect) →
> `ifind -d` (find inode) → `icat` (recover file)


## Task 5 — hashdb at scale

Now repeat the workflow using `hashdb`, which is designed for real
casework with millions of hashes.

### Create a new hash database

```bash
hashdb create reference.hdb
```

### Import reference hashes

Hash the reference files into hashdb format and import:

```bash
for FILE in reference/*; do
    hashdb import_tab reference.hdb <(
        FNAME=$(basename "$FILE")
        FILE_BLOCKS=$(( ($(stat -c%s "$FILE") + BLOCK_SIZE - 1) / BLOCK_SIZE ))
        for ((i=0; i<FILE_BLOCKS; i++)); do
            OFFSET=$((i * BLOCK_SIZE))
            HASH=$(dd if="$FILE" bs=$BLOCK_SIZE skip=$i count=1 2>/dev/null \
                   | md5sum | awk '{print $1}')
            printf "%s\t%s\t%s\n" "$HASH" "$FNAME" "$OFFSET"
        done
    )
done
echo "Reference database built:"
hashdb size reference.hdb
```

### Scan the image

```bash
hashdb scan_image reference.hdb blockhash_lab.img
```

### Compare the experience

- How does the speed compare to your Task 1 scripted loop?
- How does the output format differ?
- What additional metadata does hashdb track that your script did not?

> **Note:** `hashdb` uses MD5 by default for compatibility with existing
> hash databases (including NSRL). Your scripted approach used SHA-256.
> In practice, the choice depends on your reference database and threat
> model.


## Wrap-up

You have now completed the full block-hash forensic workflow:

1. **Manual hashing** — understood the mechanics: slice image into blocks,
   hash each one independently
2. **Reference set** — built a lookup database from known files
3. **Comparison** — found known content including a deleted file that
   whole-file hashing would have missed
4. **TSK investigation** — confirmed allocation status, inspected content,
   traced to inode, recovered the file
5. **hashdb** — repeated at scale with a purpose-built tool

The deleted `secret_config.conf` was invisible to directory listings and
whole-file hashing, but block hashing identified it immediately. This is
the core value of block-level known-file filtering in forensic analysis.
