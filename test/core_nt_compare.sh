#!/usr/bin/env bash
# =============================================================================
# Compare fseeko vs KSeqWrapper using a subset of real core_nt files.
#
# Builds metabuli twice:
#   1. Current code (fseeko path active for uncompressed FASTA)
#   2. Patched code  (fseeko disabled — forces KSeqWrapper for all files)
#
# Captures per-batch k-mer counts (BATCH_FILLTGT/BATCH_EXTKMER lines on stderr)
# so divergences can be traced to specific batches/files/species.
#
# Usage:
#   ./test/core_nt_compare.sh [NUM_FILES] [THREADS] [MAX_RAM]
#
# Example:
#   ./test/core_nt_compare.sh 50 16 32
#
# Override paths via environment:
#   FASTA_LIST=/path/to/files.txt \
#   TAXID_MAP=/path/to/accession2taxid \
#   TAXONOMY=/path/to/taxonomy/ \
#   REPO_ROOT=/path/to/Metabuli \
#     ./test/core_nt_compare.sh 50 16 32
# =============================================================================
set -euo pipefail

# --- Configuration ---
NUM_FILES=${1:-100}
THREADS=${2:-16}
MAX_RAM=${3:-32}

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
METABULI="$REPO_ROOT/build/src/metabuli"
SRC_FILE="$REPO_ROOT/src/commons/IndexCreator.cpp"
BUILD_DIR="$REPO_ROOT/build"

FASTA_LIST="${FASTA_LIST:-/data/databases/fasta/core_nt_split.files.txt}"
TAXID_MAP="${TAXID_MAP:-/data/databases/taxonomy/nucl_all.clean.accession2taxid}"
TAXONOMY="${TAXONOMY:-/data/databases/taxonomy/}"

NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

WORK_DIR=$(mktemp -d)

echo "============================================"
echo "  core_nt fseeko vs KSeqWrapper comparison"
echo "============================================"
echo "Files:     $NUM_FILES (of $(wc -l < "$FASTA_LIST" | tr -d ' ') total)"
echo "Threads:   $THREADS"
echo "Max RAM:   $MAX_RAM GiB"
echo "Work dir:  $WORK_DIR"
echo "Repo:      $REPO_ROOT"
echo ""

# --- Create subset file list ---
SUBSET_LIST="$WORK_DIR/subset_files.txt"
head -n "$NUM_FILES" "$FASTA_LIST" > "$SUBSET_LIST"

# Sanity: verify first and last files exist
first_file=$(head -1 "$SUBSET_LIST")
last_file=$(tail -1 "$SUBSET_LIST")
for f in "$first_file" "$last_file"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: file not found: $f"
        exit 1
    fi
done
echo "Subset files verified (spot-check: first and last exist)"
echo ""

# --- Helper: run a build and extract stats ---
run_build() {
    local label="$1"
    local db_dir="$2"
    local log_prefix="$3"

    mkdir -p "$db_dir"

    local rc=0
    "$METABULI" build \
        "$db_dir" \
        "$SUBSET_LIST" \
        "$TAXID_MAP" \
        --taxonomy-path "$TAXONOMY" \
        --threads "$THREADS" \
        --max-ram "$MAX_RAM" \
        >"${log_prefix}_stdout.log" 2>"${log_prefix}_stderr.log" || rc=$?

    # Extract summary stats from stdout
    local loaded written flushes batches
    loaded=$(grep "Loaded k-mer count" "${log_prefix}_stdout.log" | awk '{sum += $NF} END {print sum+0}')
    written=$(grep "Written k-mer count" "${log_prefix}_stdout.log" | awk '{sum += $NF} END {print sum+0}')
    flushes=$(grep -c "Write k-mers" "${log_prefix}_stdout.log" || echo 0)
    batches=$(grep "Number of accession batches" "${log_prefix}_stdout.log" | awk '{print $NF}' || echo "?")

    # Extract offset validation from stderr
    local offset_status
    offset_status=$(grep -c "OFFSET_MISMATCH" "${log_prefix}_stderr.log" || echo 0)

    # Extract per-batch stats from stderr
    local batch_lines
    batch_lines=$(grep -c "^BATCH_" "${log_prefix}_stderr.log" || echo 0)

    # Sort per-batch log by batch index for stable comparison
    grep "^BATCH_" "${log_prefix}_stderr.log" | sort -t= -k2 -n > "${log_prefix}_batches_sorted.log" || true

    local build_time
    build_time=$(grep "Build complete in" "${log_prefix}_stdout.log" || echo "N/A")

    echo "  [$label]"
    echo "    Exit code:        $rc"
    echo "    Batches:          $batches"
    echo "    Flushes:          $flushes"
    echo "    Total loaded:     $loaded"
    echo "    Total written:    $written"
    echo "    Batch log lines:  $batch_lines"
    echo "    Offset mismatches: $offset_status"
    echo "    $build_time"

    if [[ "$offset_status" -gt 0 ]]; then
        echo "    ** OFFSET MISMATCHES FOUND: **"
        grep "OFFSET_MISMATCH" "${log_prefix}_stderr.log" | head -10
    fi
}

# =====================================================================
# Run 1: fseeko path (current code)
# =====================================================================
echo "=== Run 1: fseeko path (current code) ==="
t1_start=$(date +%s)
run_build "fseeko" "$WORK_DIR/db_fseek" "$WORK_DIR/fseek"
t1_end=$(date +%s)
echo "    Wall time: $((t1_end - t1_start))s"
echo ""

# =====================================================================
# Run 2: force KSeqWrapper (disable fseeko via source patch)
# =====================================================================
echo "=== Run 2: Patching source to disable fseeko... ==="
sed -i.bak 's/if (!offsets\.empty())/if (false \&\& !offsets.empty())/g' "$SRC_FILE"
echo "Rebuilding..."
(cd "$BUILD_DIR" && make -j"$NPROC" 2>&1 | tail -3)
echo ""

t2_start=$(date +%s)
run_build "kseq" "$WORK_DIR/db_kseq" "$WORK_DIR/kseq"
t2_end=$(date +%s)
echo "    Wall time: $((t2_end - t2_start))s"
echo ""

# --- Restore source ---
echo "Restoring source and rebuilding..."
mv "$SRC_FILE.bak" "$SRC_FILE"
(cd "$BUILD_DIR" && make -j"$NPROC" 2>&1 | tail -3)
echo ""

# =====================================================================
# Analysis
# =====================================================================

echo "============================================"
echo "  PER-FLUSH K-MER COUNT COMPARISON"
echo "============================================"
# Compare per-flush loaded counts
fseek_flushes=$(grep -c "Loaded k-mer count" "$WORK_DIR/fseek_stdout.log" || echo 0)
kseq_flushes=$(grep -c "Loaded k-mer count" "$WORK_DIR/kseq_stdout.log" || echo 0)
max_flushes=$((fseek_flushes > kseq_flushes ? fseek_flushes : kseq_flushes))

if [[ $max_flushes -gt 0 ]]; then
    paste \
        <(grep "Loaded k-mer count" "$WORK_DIR/fseek_stdout.log" | awk '{print NR, $NF}') \
        <(grep "Loaded k-mer count" "$WORK_DIR/kseq_stdout.log" | awk '{print $NF}') \
        2>/dev/null | awk '{
            printf "  Flush %d: fseeko=%-12s kseq=%-12s", $1, $2, $3
            if ($2 != $3) printf "  ** DIFFER (ratio=%.4f)", ($3 > 0 ? $2/$3 : 0)
            else printf "  MATCH"
            printf "\n"
        }'
fi

echo ""
fseek_total=$(grep "Loaded k-mer count" "$WORK_DIR/fseek_stdout.log" | awk '{sum+=$NF} END {print sum+0}')
kseq_total=$(grep "Loaded k-mer count" "$WORK_DIR/kseq_stdout.log" | awk '{sum+=$NF} END {print sum+0}')
echo "  TOTAL: fseeko=$fseek_total  kseq=$kseq_total"
if [[ "$fseek_total" != "$kseq_total" ]]; then
    ratio=$(awk "BEGIN {if ($fseek_total > 0) printf \"%.4f\", $kseq_total / $fseek_total; else print \"inf\"}")
    echo "  ** MISMATCH: kseq/fseeko ratio = $ratio"
else
    echo "  ** MATCH"
fi

# =====================================================================
echo ""
echo "============================================"
echo "  PER-BATCH K-MER COMPARISON"
echo "============================================"
# Compare sorted batch logs line-by-line
if [[ -s "$WORK_DIR/fseek_batches_sorted.log" && -s "$WORK_DIR/kseq_batches_sorted.log" ]]; then
    # Extract batch_id and kmers from each, join on batch_id
    awk -F'[ =]' '{
        for(i=1;i<=NF;i++) {
            if($i=="batch") batch=$(i+1)
            if($i=="kmers") kmers=$(i+1)
        }
        print batch, kmers
    }' "$WORK_DIR/fseek_batches_sorted.log" > "$WORK_DIR/fseek_bk.txt"

    awk -F'[ =]' '{
        for(i=1;i<=NF;i++) {
            if($i=="batch") batch=$(i+1)
            if($i=="kmers") kmers=$(i+1)
        }
        print batch, kmers
    }' "$WORK_DIR/kseq_batches_sorted.log" > "$WORK_DIR/kseq_bk.txt"

    # Join and compare
    differ_count=$(join "$WORK_DIR/fseek_bk.txt" "$WORK_DIR/kseq_bk.txt" | awk '$2 != $3 {count++} END {print count+0}')
    total_batches=$(wc -l < "$WORK_DIR/fseek_bk.txt" | tr -d ' ')
    echo "  Batches compared: $total_batches"
    echo "  Batches differing: $differ_count"

    if [[ $differ_count -gt 0 ]]; then
        echo ""
        echo "  First 20 differing batches (batch_id  fseeko_kmers  kseq_kmers):"
        join "$WORK_DIR/fseek_bk.txt" "$WORK_DIR/kseq_bk.txt" \
            | awk '$2 != $3 {printf "    batch=%-6s fseeko=%-10s kseq=%-10s ratio=%.4f\n", $1, $2, $3, ($3>0 ? $2/$3 : 0)}' \
            | head -20

        # Also show which files/species those batches belong to
        echo ""
        echo "  File/species detail for differing batches:"
        for batch_id in $(join "$WORK_DIR/fseek_bk.txt" "$WORK_DIR/kseq_bk.txt" | awk '$2 != $3 {print $1}' | head -10); do
            fseek_line=$(grep "batch=$batch_id " "$WORK_DIR/fseek_batches_sorted.log" | head -1)
            kseq_line=$(grep "batch=$batch_id " "$WORK_DIR/kseq_batches_sorted.log" | head -1)
            echo "    FSEEK: $fseek_line"
            echo "    KSEQ:  $kseq_line"
            echo ""
        done
    fi
else
    echo "  No batch logs to compare"
fi

# =====================================================================
echo ""
echo "============================================"
echo "  OUTPUT FILE COMPARISON"
echo "============================================"
any_diff=0

compare_file() {
    local fname="$1"
    local f1="$WORK_DIR/db_fseek/$fname"
    local f2="$WORK_DIR/db_kseq/$fname"
    if [[ -f "$f1" && -f "$f2" ]]; then
        if cmp -s "$f1" "$f2"; then
            echo "  MATCH:  $fname ($(wc -c < "$f1" | tr -d ' ')B)"
        else
            local s1 s2
            s1=$(wc -c < "$f1" | tr -d ' '); s2=$(wc -c < "$f2" | tr -d ' ')
            echo "  DIFFER: $fname (fseeko=${s1}B, kseq=${s2}B)"
            any_diff=1
        fi
    elif [[ -f "$f1" ]]; then
        echo "  ONLY IN FSEEK: $fname"; any_diff=1
    elif [[ -f "$f2" ]]; then
        echo "  ONLY IN KSEQ: $fname"; any_diff=1
    fi
}

for fname in diffIdx info split taxID_list acc2taxid.map taxonomyDB; do
    compare_file "$fname"
done
for f1 in "$WORK_DIR/db_fseek"/*_diffIdx "$WORK_DIR/db_fseek"/*_info; do
    [[ -f "$f1" ]] || continue
    compare_file "$(basename "$f1")"
done
for f2 in "$WORK_DIR/db_kseq"/*_diffIdx "$WORK_DIR/db_kseq"/*_info; do
    [[ -f "$f2" ]] || continue
    fname=$(basename "$f2")
    [[ -f "$WORK_DIR/db_fseek/$fname" ]] || { echo "  ONLY IN KSEQ: $fname"; any_diff=1; }
done

# =====================================================================
echo ""
echo "============================================"
if [[ $any_diff -eq 0 && "$fseek_total" == "$kseq_total" ]]; then
    echo "  RESULT: PASS — k-mer counts and index files match"
else
    echo "  RESULT: DIFFERENCES FOUND — see details above"
fi
echo "============================================"
echo ""
echo "Logs preserved at: $WORK_DIR"
echo ""
echo "Useful commands:"
echo "  # Per-flush k-mer counts"
echo "  grep 'Loaded k-mer count' $WORK_DIR/fseek_stdout.log"
echo "  grep 'Loaded k-mer count' $WORK_DIR/kseq_stdout.log"
echo ""
echo "  # Offset validation"
echo "  grep 'OFFSET_MISMATCH' $WORK_DIR/fseek_stderr.log"
echo ""
echo "  # Per-batch details (sorted by batch ID)"
echo "  head -20 $WORK_DIR/fseek_batches_sorted.log"
echo "  head -20 $WORK_DIR/kseq_batches_sorted.log"
echo ""
echo "  # Sequence-level debug (first 20 batches)"
echo "  grep '^FSEEK\|^KSEQ' $WORK_DIR/fseek_stderr.log | head -40"
echo "  grep '^KSEQ' $WORK_DIR/kseq_stderr.log | head -40"
