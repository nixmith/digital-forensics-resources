#!/usr/bin/env bash
#
# sdhash_tests.sh
# ================
# Reproduces the controlled study (Section 3) from:
#   Roussev, V. (2011). "An evaluation of forensic similarity hashes."
#   Digital Investigation, 8, S34–S41. doi:10.1016/j.diin.2011.05.005
#
# Implements all three scenarios (sdhash only):
#   3.3  Embedded object detection
#   3.4  Single-common-block file correlation
#   3.5  Multiple-common-blocks file correlation
#
# Prerequisites: sdhash 3.4 installed and on PATH
#
# Usage:
#   ./sdhash_tests.sh                    # quick mode, all scenarios
#   ./sdhash_tests.sh quick              # quick mode, all scenarios (~15-30 min)
#   ./sdhash_tests.sh full               # full replication, all scenarios (~3-6 hrs)
#   ./sdhash_tests.sh quick 1            # quick mode, scenario 1 only
#   ./sdhash_tests.sh full 2             # full mode, scenario 2 only
#   ./sdhash_tests.sh quick 1,3          # quick mode, scenarios 1 and 3
#   ./sdhash_tests.sh full 1,2,3         # full mode, all scenarios (explicit)
#
# Output: CSV files in results/ directory
#   scenario1_embedded_detection.csv
#   scenario2_single_block_correlation.csv
#   scenario3_multiple_blocks_correlation.csv
#   summary_report.txt
#
set -euo pipefail

###############################################################################
# Configuration
###############################################################################

MODE="${1:-quick}"
SCENARIOS="${2:-1,2,3}"

# Validate mode
if [[ "$MODE" != "quick" && "$MODE" != "full" ]]; then
    echo "ERROR: Mode must be 'quick' or 'full', got '$MODE'"
    echo "Usage: $0 [quick|full] [1|2|3|1,2|1,3|2,3|1,2,3]"
    exit 1
fi

run_s1=false; run_s2=false; run_s3=false
IFS=',' read -ra SCENARIO_LIST <<< "$SCENARIOS"
for s in "${SCENARIO_LIST[@]}"; do
    case "$s" in
        1) run_s1=true ;;
        2) run_s2=true ;;
        3) run_s3=true ;;
        *) echo "ERROR: Unknown scenario '$s'. Use 1, 2, 3, or comma-separated (e.g. 1,3)"; exit 1 ;;
    esac
done

# Paper parameters: 25 iterations x 40 placements = 1000 observations
# Quick mode:        5 iterations x 10 placements =   50 observations
if [[ "$MODE" == "full" ]]; then
    ITERATIONS=25
    PLACEMENTS=40
    # Scenario 1: object sizes (KB) and target multipliers
    S1_OBJ_SIZES=(64 128 256 512 1024)
    S1_MULTIPLIERS=(1 2 3 4 8 16 32 64 128 256 512 1024)
    # Scenario 2: target sizes (KB)
    S2_TGT_SIZES=(256 512 1024 2048 4096)
    # Scenario 3: target sizes (KB)
    S3_TGT_SIZES=(256 512 1024 2048 4096)
else
    ITERATIONS=5
    PLACEMENTS=10
    S1_OBJ_SIZES=(64 256 1024)
    S1_MULTIPLIERS=(1 3 8 32 128 512)
    S2_TGT_SIZES=(256 1024 4096)
    S3_TGT_SIZES=(256 1024 4096)
fi

TOTAL_PER_CONFIG=$((ITERATIONS * PLACEMENTS))

# Scenario 2: object size fractions to test (denominator of target size)
# e.g., 32 means object = target/32
S2_DIVISORS=(32 16 12 8 6 4 3 2)

# Working and output directories
WORKDIR=$(mktemp -d /tmp/roussev2011.XXXXXX)
OUTDIR="results"
mkdir -p "$OUTDIR"

CSV_S1="$OUTDIR/scenario1_embedded_detection.csv"
CSV_S2="$OUTDIR/scenario2_single_block_correlation.csv"
CSV_S3="$OUTDIR/scenario3_multiple_blocks_correlation.csv"
REPORT="$OUTDIR/summary_report.txt"

###############################################################################
# Preflight checks
###############################################################################

if ! command -v sdhash &>/dev/null; then
    echo "ERROR: sdhash not found on PATH. Install sdhash 3.4 and retry."
    exit 1
fi

echo "============================================================"
echo " Roussev (2011) Controlled Study Reproduction — sdhash only"
echo "============================================================"
echo "  Mode:             $MODE"
echo "  Scenarios:        $SCENARIOS"
echo "  Iterations:       $ITERATIONS"
echo "  Placements/iter:  $PLACEMENTS"
echo "  Observations/cfg: $TOTAL_PER_CONFIG"
echo "  Working dir:      $WORKDIR"
echo "  Output dir:       $OUTDIR/"
echo "============================================================"
echo ""

###############################################################################
# Utility functions
###############################################################################

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Generate a file of pseudorandom bytes
# Usage: gen_random <path> <size_in_KB>
gen_random() {
    dd if=/dev/urandom of="$1" bs=1024 count="$2" 2>/dev/null
}

# Return a random integer in [0, max] using /dev/urandom
# Usage: rand_int <max>
rand_int() {
    local max=$1
    if (( max <= 0 )); then
        echo 0
        return
    fi
    local raw
    raw=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
    echo $(( raw % (max + 1) ))
}

# Embed (overwrite) object into target at a random KB-aligned offset
# Usage: embed_random <target> <target_kb> <object> <object_kb>
embed_random() {
    local target="$1" target_kb="$2" object="$3" object_kb="$4"
    local max_pos_kb=$(( target_kb - object_kb ))
    local pos_kb
    pos_kb=$(rand_int "$max_pos_kb")
    dd if="$object" of="$target" bs=1024 seek="$pos_kb" conv=notrunc 2>/dev/null
}

# Run sdhash: hash two files and compare, return the score
# Usage: sdhash_score <file_a> <file_b>
# Returns: integer score (0 if no match or error, -1 if insufficient data)
sdhash_score() {
    local fa="$1" fb="$2"
    local da="$WORKDIR/a.sdbf" db="$WORKDIR/b.sdbf"

    rm -f "$da" "$db"

    # Generate digests (suppress warnings for small/uniform files)
    if ! sdhash "$fa" -o "$da" 2>/dev/null; then
        echo "0"; return
    fi
    if ! sdhash "$fb" -o "$db" 2>/dev/null; then
        echo "0"; return
    fi

    # Two-set comparison, threshold 0 to capture all scores
    local line score
    line=$(sdhash -c "$da" "$db" -t 0 2>/dev/null | head -1) || true

    if [[ -z "$line" ]]; then
        echo "0"
    else
        score=$(echo "$line" | awk -F'|' '{print $3}' | tr -d '[:space:]')
        # Treat -1 (unknown/insufficient data) as 0
        if [[ "$score" == "-1" || -z "$score" ]]; then
            echo "0"
        else
            echo "$score"
        fi
    fi

    rm -f "$da" "$db"
}

# Print a progress bar
# Usage: progress <current> <total> <label>
progress() {
    local cur=$1 total=$2 label="$3"
    local pct=$(( cur * 100 / total ))
    local bar_len=30
    local filled=$(( pct * bar_len / 100 ))
    local empty=$(( bar_len - filled ))
    printf "\r  [%-${bar_len}s] %3d%%  %s" \
        "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)" \
        "$pct" "$label"
}

###############################################################################
# Scenario 1: Embedded Object Detection (Section 3.3)
#
# Given object O of fixed size embedded in target T, what is the largest T
# for which O and T can be reliably correlated?
#
# For each (object_size, target_size) pair, embed O at a random position
# inside T, then compare O against the modified T using sdhash.
###############################################################################

run_scenario1() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Scenario 1: Embedded Object Detection (Section 3.3)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "scenario,object_kb,target_kb,iteration,placement,score" > "$CSV_S1"

    local total_configs=$(( ${#S1_OBJ_SIZES[@]} * ${#S1_MULTIPLIERS[@]} ))
    local config_num=0

    for obj_kb in "${S1_OBJ_SIZES[@]}"; do
        for mult in "${S1_MULTIPLIERS[@]}"; do
            local tgt_kb=$(( obj_kb * mult ))
            # Skip degenerate case where target < object
            (( tgt_kb < obj_kb )) && continue

            config_num=$((config_num + 1))
            local label="obj=${obj_kb}KB tgt=${tgt_kb}KB [${config_num}/${total_configs}]"

            local run_count=0
            for iter in $(seq 1 "$ITERATIONS"); do
                # Fresh random object and base target each iteration
                gen_random "$WORKDIR/object.bin" "$obj_kb"
                gen_random "$WORKDIR/target_base.bin" "$tgt_kb"

                for place in $(seq 1 "$PLACEMENTS"); do
                    run_count=$((run_count + 1))
                    progress "$run_count" "$TOTAL_PER_CONFIG" "$label"

                    # Copy base target and embed object at random position
                    cp "$WORKDIR/target_base.bin" "$WORKDIR/target.bin"
                    embed_random "$WORKDIR/target.bin" "$tgt_kb" \
                                 "$WORKDIR/object.bin" "$obj_kb"

                    local score
                    score=$(sdhash_score "$WORKDIR/object.bin" "$WORKDIR/target.bin")

                    echo "embedded_detection,${obj_kb},${tgt_kb},${iter},${place},${score}" >> "$CSV_S1"
                done
            done
            echo ""  # newline after progress bar
        done
    done

    echo "  → Results written to $CSV_S1"
    echo ""
}

###############################################################################
# Scenario 2: Single-Common-Block File Correlation (Section 3.4)
#
# Given T1 and T2 that share a common data object O, what is the smallest O
# for which sdhash reliably correlates the two targets?
#
# Both targets are the same size. We embed the same object O at independent
# random positions in each target, then compare T1 against T2.
###############################################################################

run_scenario2() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Scenario 2: Single-Common-Block Correlation (Section 3.4)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "scenario,target_kb,object_kb,iteration,placement,score" > "$CSV_S2"

    local total_configs=$(( ${#S2_TGT_SIZES[@]} * ${#S2_DIVISORS[@]} ))
    local config_num=0

    for tgt_kb in "${S2_TGT_SIZES[@]}"; do
        for div in "${S2_DIVISORS[@]}"; do
            local obj_kb=$(( tgt_kb / div ))
            # Minimum meaningful object size: 4 KB (sdhash min is 512 bytes)
            (( obj_kb < 4 )) && continue
            # Object must be smaller than target
            (( obj_kb >= tgt_kb )) && continue

            config_num=$((config_num + 1))
            local label="tgt=${tgt_kb}KB obj=${obj_kb}KB [${config_num}/${total_configs}]"

            local run_count=0
            for iter in $(seq 1 "$ITERATIONS"); do
                gen_random "$WORKDIR/object.bin" "$obj_kb"
                gen_random "$WORKDIR/t1_base.bin" "$tgt_kb"
                gen_random "$WORKDIR/t2_base.bin" "$tgt_kb"

                for place in $(seq 1 "$PLACEMENTS"); do
                    run_count=$((run_count + 1))
                    progress "$run_count" "$TOTAL_PER_CONFIG" "$label"

                    # Embed same object at different random positions in each target
                    cp "$WORKDIR/t1_base.bin" "$WORKDIR/t1.bin"
                    cp "$WORKDIR/t2_base.bin" "$WORKDIR/t2.bin"
                    embed_random "$WORKDIR/t1.bin" "$tgt_kb" \
                                 "$WORKDIR/object.bin" "$obj_kb"
                    embed_random "$WORKDIR/t2.bin" "$tgt_kb" \
                                 "$WORKDIR/object.bin" "$obj_kb"

                    local score
                    score=$(sdhash_score "$WORKDIR/t1.bin" "$WORKDIR/t2.bin")

                    echo "single_block,${tgt_kb},${obj_kb},${iter},${place},${score}" >> "$CSV_S2"
                done
            done
            echo ""
        done
    done

    echo "  → Results written to $CSV_S2"
    echo ""
}

###############################################################################
# Scenario 3: Multiple-Common-Blocks File Correlation (Section 3.5)
#
# T1 and T2 share 50% common data, split into 4 or 8 non-overlapping pieces,
# each independently and randomly placed. We measure the probability that
# sdhash produces a positive score.
###############################################################################

# Embed N non-overlapping pieces into a target using segment partitioning.
# Each piece goes into its own segment (target divided into N equal parts)
# at a random offset within that segment.
#
# Usage: embed_pieces <target> <target_kb> <piece_dir> <num_pieces> <piece_kb>
embed_pieces() {
    local target="$1" target_kb="$2" piece_dir="$3"
    local num_pieces="$4" piece_kb="$5"
    local segment_kb=$(( target_kb / num_pieces ))

    for i in $(seq 0 $(( num_pieces - 1 ))); do
        local seg_start=$(( i * segment_kb ))
        local max_offset=$(( segment_kb - piece_kb ))
        local offset_in_seg
        offset_in_seg=$(rand_int "$max_offset")
        local pos_kb=$(( seg_start + offset_in_seg ))

        dd if="${piece_dir}/piece_${i}.bin" of="$target" \
           bs=1024 seek="$pos_kb" conv=notrunc 2>/dev/null
    done
}

run_scenario3() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Scenario 3: Multiple-Common-Blocks Correlation (Section 3.5)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    echo "scenario,target_kb,common_kb,num_pieces,piece_kb,iteration,placement,score" > "$CSV_S3"

    local piece_counts=(4 8)
    local total_configs=$(( ${#S3_TGT_SIZES[@]} * ${#piece_counts[@]} ))
    local config_num=0

    mkdir -p "$WORKDIR/pieces"

    for tgt_kb in "${S3_TGT_SIZES[@]}"; do
        local common_kb=$(( tgt_kb / 2 ))  # 50% commonality

        for npieces in "${piece_counts[@]}"; do
            local piece_kb=$(( common_kb / npieces ))
            # Ensure piece is at least 4 KB
            (( piece_kb < 4 )) && continue

            config_num=$((config_num + 1))
            local label="tgt=${tgt_kb}KB ${npieces}×${piece_kb}KB [${config_num}/${total_configs}]"

            local run_count=0
            for iter in $(seq 1 "$ITERATIONS"); do
                # Generate fresh pieces and base targets each iteration
                for p in $(seq 0 $(( npieces - 1 ))); do
                    gen_random "$WORKDIR/pieces/piece_${p}.bin" "$piece_kb"
                done
                gen_random "$WORKDIR/t1_base.bin" "$tgt_kb"
                gen_random "$WORKDIR/t2_base.bin" "$tgt_kb"

                for place in $(seq 1 "$PLACEMENTS"); do
                    run_count=$((run_count + 1))
                    progress "$run_count" "$TOTAL_PER_CONFIG" "$label"

                    # Embed all pieces into both targets at different positions
                    cp "$WORKDIR/t1_base.bin" "$WORKDIR/t1.bin"
                    cp "$WORKDIR/t2_base.bin" "$WORKDIR/t2.bin"

                    embed_pieces "$WORKDIR/t1.bin" "$tgt_kb" \
                                 "$WORKDIR/pieces" "$npieces" "$piece_kb"
                    embed_pieces "$WORKDIR/t2.bin" "$tgt_kb" \
                                 "$WORKDIR/pieces" "$npieces" "$piece_kb"

                    local score
                    score=$(sdhash_score "$WORKDIR/t1.bin" "$WORKDIR/t2.bin")

                    echo "multi_block,${tgt_kb},${common_kb},${npieces},${piece_kb},${iter},${place},${score}" >> "$CSV_S3"
                done
            done
            echo ""
        done
    done

    echo "  → Results written to $CSV_S3"
    echo ""
}

###############################################################################
# Summary report
###############################################################################

generate_report() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Generating summary report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cat > "$REPORT" <<'HEADER'
==============================================================================
 Roussev (2011) Controlled Study Reproduction — Summary Report (sdhash)
==============================================================================

Reference: Roussev, V. (2011). "An evaluation of forensic similarity hashes."
           Digital Investigation, 8, S34–S41.

Detection is defined as score > 0. Reliable detection = ≥95% true positive rate.

HEADER

    # Scenario 1 summary
    if [[ -f "$CSV_S1" ]]; then
    echo "--- Scenario 1: Embedded Object Detection ---" >> "$REPORT"
    echo "" >> "$REPORT"
    printf "%-12s %-12s %8s %10s %10s\n" \
        "Object(KB)" "Target(KB)" "Runs" "Detected" "Rate(%)" >> "$REPORT"
    printf "%-12s %-12s %8s %10s %10s\n" \
        "----------" "----------" "----" "--------" "-------" >> "$REPORT"

    awk -F',' 'NR>1 {
        key = $2 "," $3
        total[key]++
        if ($6 > 0) detected[key]++
    }
    END {
        for (k in total) {
            split(k, a, ",")
            d = (k in detected) ? detected[k] : 0
            rate = d * 100.0 / total[k]
            printf "%-12s %-12s %8d %10d %9.1f\n", a[1], a[2], total[k], d, rate
        }
    }' "$CSV_S1" | sort -t' ' -k1,1n -k2,2n >> "$REPORT"

    echo "" >> "$REPORT"
    fi

    # Scenario 2 summary
    if [[ -f "$CSV_S2" ]]; then
    echo "--- Scenario 2: Single-Common-Block File Correlation ---" >> "$REPORT"
    echo "" >> "$REPORT"
    printf "%-12s %-12s %8s %10s %10s %10s\n" \
        "Target(KB)" "Object(KB)" "Runs" "Detected" "Rate(%)" "AvgScore" >> "$REPORT"
    printf "%-12s %-12s %8s %10s %10s %10s\n" \
        "----------" "----------" "----" "--------" "-------" "--------" >> "$REPORT"

    awk -F',' 'NR>1 {
        key = $2 "," $3
        total[key]++
        sum[key] += $6
        if ($6 > 0) detected[key]++
    }
    END {
        for (k in total) {
            split(k, a, ",")
            d = (k in detected) ? detected[k] : 0
            rate = d * 100.0 / total[k]
            avg = sum[k] / total[k]
            printf "%-12s %-12s %8d %10d %9.1f %9.1f\n", a[1], a[2], total[k], d, rate, avg
        }
    }' "$CSV_S2" | sort -t' ' -k1,1n -k2,2n >> "$REPORT"

    echo "" >> "$REPORT"
    fi

    # Scenario 3 summary
    if [[ -f "$CSV_S3" ]]; then
    echo "--- Scenario 3: Multiple-Common-Blocks File Correlation ---" >> "$REPORT"
    echo "" >> "$REPORT"
    printf "%-12s %-12s %-8s %-10s %8s %10s %10s %10s\n" \
        "Target(KB)" "Common(KB)" "Pieces" "Piece(KB)" "Runs" "Detected" "Rate(%)" "AvgScore" >> "$REPORT"
    printf "%-12s %-12s %-8s %-10s %8s %10s %10s %10s\n" \
        "----------" "----------" "------" "---------" "----" "--------" "-------" "--------" >> "$REPORT"

    awk -F',' 'NR>1 {
        key = $2 "," $3 "," $4 "," $5
        total[key]++
        sum[key] += $8
        if ($8 > 0) detected[key]++
    }
    END {
        for (k in total) {
            split(k, a, ",")
            d = (k in detected) ? detected[k] : 0
            rate = d * 100.0 / total[k]
            avg = sum[k] / total[k]
            printf "%-12s %-12s %-8s %-10s %8d %10d %9.1f %9.1f\n", \
                a[1], a[2], a[3], a[4], total[k], d, rate, avg
        }
    }' "$CSV_S3" | sort -t' ' -k1,1n -k3,3n >> "$REPORT"

    echo "" >> "$REPORT"
    fi

    # Paper reference values
    cat >> "$REPORT" <<'REFERENCE'

==============================================================================
 Paper Reference Values (sdhash results from Roussev 2011, Tables 1, 3, 4)
==============================================================================

Table 1 — Embedded Object Detection (max target for ≥95% detection):
  Object 64KB  → tested up to 65,536 KB (still detected)
  Object 128KB → tested up to 131,072 KB
  Object 256KB → tested up to 262,144 KB
  Object 512KB → tested up to 524,288 KB
  Object 1024KB→ tested up to 1,048,576 KB

Table 3 — Single-Common-Block (min object for ≥95% detection):
  Target 256KB  → min object  16 KB
  Target 512KB  → min object  24 KB
  Target 1024KB → min object  32 KB
  Target 2048KB → min object  48 KB
  Target 4096KB → min object  96 KB

Table 4 — Multiple-Common-Blocks (detection probability, sdhash):
  All tested configurations: 1.00 (100%) for both 4-piece and 8-piece
  Average scores: 17-18 (4-piece), 13-14 (8-piece)
REFERENCE

    echo "" >> "$REPORT"
    echo "  → Report written to $REPORT"
    echo ""
}

###############################################################################
# Main
###############################################################################

START_TIME=$(date +%s)

$run_s1 && run_scenario1
$run_s2 && run_scenario2
$run_s3 && run_scenario3
generate_report

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS_REM=$(( ELAPSED % 60 ))

echo "============================================================"
echo "  Complete! Total time: ${MINUTES}m ${SECONDS_REM}s"
echo ""
echo "  Output files:"
$run_s1 && echo "    $CSV_S1"
$run_s2 && echo "    $CSV_S2"
$run_s3 && echo "    $CSV_S3"
echo "    $REPORT"
echo "============================================================"
