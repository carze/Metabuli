#!/usr/bin/env bash
# Stress test: compare fseeko vs KSeqWrapper with 50 files, multi-threaded, multiple flushes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METABULI="$REPO_ROOT/build/src/metabuli"
STRESS_DATA="$REPO_ROOT/test/data/stress"
SRC_FILE="$REPO_ROOT/src/commons/IndexCreator.cpp"
BUILD_DIR="$REPO_ROOT/build"

THREADS=${1:-8}
MAX_RAM=${2:-1}

WORK_DIR=$(mktemp -d)
echo "=== Stress test: fseeko vs KSeqWrapper ==="
echo "Threads: $THREADS, Max RAM: $MAX_RAM GiB"
echo "Working directory: $WORK_DIR"
echo ""

run_build() {
    local label="$1"
    local db_dir="$2"
    local log_prefix="$3"

    mkdir -p "$db_dir/taxonomy"
    cp "$STRESS_DATA"/taxonomy/* "$db_dir/taxonomy/"

    "$METABULI" build \
        "$db_dir" \
        "$STRESS_DATA/fasta_list.txt" \
        "$STRESS_DATA/accession2taxid.tsv" \
        --threads "$THREADS" \
        --mask 0 \
        --max-ram "$MAX_RAM" \
        >"${log_prefix}_stdout.log" 2>"${log_prefix}_stderr.log"

    local kmer_count
    kmer_count=$(/usr/bin/grep "Loaded k-mer count" "${log_prefix}_stdout.log" | /usr/bin/awk '{print $NF}' || echo "N/A")
    local unique_count
    unique_count=$(/usr/bin/grep "Unique k-mer count" "${log_prefix}_stdout.log" | /usr/bin/awk '{print $NF}' || echo "N/A")
    local written_count
    written_count=$(/usr/bin/grep "Written k-mer count" "${log_prefix}_stdout.log" | /usr/bin/awk '{print $NF}' || echo "N/A")
    local flush_count
    flush_count=$(/usr/bin/grep -c "batches processed" "${log_prefix}_stdout.log" || true)

    echo "  $label: loaded=$kmer_count unique=$unique_count written=$written_count batch_lines=$flush_count"
}

# --- Run 1: fseeko enabled ---
echo "=== Run 1: fseeko path ==="
run_build "fseeko" "$WORK_DIR/db_fseek" "$WORK_DIR/fseek"

# --- Run 2: KSeqWrapper only ---
echo "=== Run 2: Patching to disable fseeko... ==="
sed -i.bak 's/if (!offsets.empty())/if (false \&\& !offsets.empty())/g' "$SRC_FILE"
(cd "$BUILD_DIR" && make -j$(sysctl -n hw.ncpu) 2>&1 | tail -2)
run_build "kseq  " "$WORK_DIR/db_kseq" "$WORK_DIR/kseq"

# --- Restore ---
mv "$SRC_FILE.bak" "$SRC_FILE"
echo "Restoring fseeko and rebuilding..."
(cd "$BUILD_DIR" && make -j$(sysctl -n hw.ncpu) 2>&1 | tail -2)

echo ""
echo "=== File comparison ==="
any_diff=0
for fname in diffIdx info split taxID_list acc2taxid.map taxonomyDB; do
    f1="$WORK_DIR/db_fseek/$fname"
    f2="$WORK_DIR/db_kseq/$fname"
    if [[ -f "$f1" && -f "$f2" ]]; then
        if cmp -s "$f1" "$f2"; then
            echo "  MATCH: $fname"
        else
            s1=$(wc -c < "$f1"); s2=$(wc -c < "$f2")
            echo "  DIFFER: $fname (fseeko=${s1}B, kseq=${s2}B)"
            any_diff=1
        fi
    elif [[ -f "$f1" ]]; then
        echo "  ONLY IN FSEEK: $fname"
        any_diff=1
    elif [[ -f "$f2" ]]; then
        echo "  ONLY IN KSEQ: $fname"
        any_diff=1
    else
        echo "  MISSING: $fname (both)"
    fi
done

# Check numbered files too
for f1 in "$WORK_DIR/db_fseek"/*_diffIdx "$WORK_DIR/db_fseek"/*_info; do
    [[ -f "$f1" ]] || continue
    fname=$(basename "$f1")
    f2="$WORK_DIR/db_kseq/$fname"
    if [[ -f "$f2" ]]; then
        if cmp -s "$f1" "$f2"; then
            echo "  MATCH: $fname"
        else
            s1=$(wc -c < "$f1"); s2=$(wc -c < "$f2")
            echo "  DIFFER: $fname (fseeko=${s1}B, kseq=${s2}B)"
            any_diff=1
        fi
    else
        echo "  ONLY IN FSEEK: $fname"
        any_diff=1
    fi
done

echo ""
if [[ $any_diff -eq 0 ]]; then
    echo "RESULT: ALL FILES MATCH"
    rm -rf "$WORK_DIR"
else
    echo "RESULT: DIFFERENCES FOUND"
    echo "Logs preserved at: $WORK_DIR"
fi
