#!/usr/bin/env bash
# Compare database output between fseeko path and KSeqWrapper fallback path
# Usage: ./test/compare_fseek_vs_kseq.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METABULI="$REPO_ROOT/build/src/metabuli"
TEST_DATA="$REPO_ROOT/test/data"
SRC_FILE="$REPO_ROOT/src/commons/IndexCreator.cpp"
BUILD_DIR="$REPO_ROOT/build"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Metabuli fseeko vs KSeqWrapper comparison test ==="
echo "Working directory: $WORK_DIR"
echo ""

# Create FASTA list file (absolute paths)
FASTA_LIST="$WORK_DIR/fasta_list.txt"
for f in "$TEST_DATA"/seq*.fasta; do
    echo "$f"
done > "$FASTA_LIST"

echo "FASTA files:"
cat "$FASTA_LIST"
echo ""

# --- Run 1: fseeko path enabled (current code) ---
echo "=== Run 1: fseeko path (current code) ==="
DB_FSEEK="$WORK_DIR/db_fseek"
mkdir -p "$DB_FSEEK/taxonomy"
cp "$TEST_DATA"/taxonomy/* "$DB_FSEEK/taxonomy/"

"$METABULI" build \
    "$DB_FSEEK" \
    "$FASTA_LIST" \
    "$TEST_DATA/accession2taxid.tsv" \
    --threads 1 \
    --mask 0 \
    --max-ram 1 \
    2>"$WORK_DIR/stderr_fseek.log" || true

echo "fseeko run complete."
echo ""

# --- Run 2: Force KSeqWrapper by disabling fseeko path ---
echo "=== Run 2: KSeqWrapper path (fseeko disabled) ==="

# Patch the source to disable fseeko
sed -i.bak \
    's/if (!offsets.empty())/if (false \&\& !offsets.empty())/g' \
    "$SRC_FILE"

# Rebuild
echo "Rebuilding with fseeko disabled..."
(cd "$BUILD_DIR" && make -j$(sysctl -n hw.ncpu) 2>&1 | tail -3)

DB_KSEQ="$WORK_DIR/db_kseq"
mkdir -p "$DB_KSEQ/taxonomy"
cp "$TEST_DATA"/taxonomy/* "$DB_KSEQ/taxonomy/"

"$METABULI" build \
    "$DB_KSEQ" \
    "$FASTA_LIST" \
    "$TEST_DATA/accession2taxid.tsv" \
    --threads 1 \
    --mask 0 \
    --max-ram 1 \
    2>"$WORK_DIR/stderr_kseq.log" || true

echo "KSeqWrapper run complete."
echo ""

# --- Restore source ---
mv "$SRC_FILE.bak" "$SRC_FILE"
echo "Rebuilding with fseeko re-enabled..."
(cd "$BUILD_DIR" && make -j$(sysctl -n hw.ncpu) 2>&1 | tail -3)
echo ""

# --- Compare outputs ---
echo "============================================"
echo "=== COMPARISON ==="
echo "============================================"
echo ""

# Compare key database files
for fname in diffIdx info split taxID_list acc2taxid.map taxonomyDB; do
    f1="$DB_FSEEK/$fname"
    f2="$DB_KSEQ/$fname"
    if [[ -f "$f1" && -f "$f2" ]]; then
        if cmp -s "$f1" "$f2"; then
            echo "  MATCH: $fname"
        else
            s1=$(wc -c < "$f1")
            s2=$(wc -c < "$f2")
            echo "  DIFFER: $fname (fseeko=${s1} bytes, kseq=${s2} bytes)"
        fi
    elif [[ -f "$f1" ]]; then
        echo "  ONLY IN FSEEK: $fname"
    elif [[ -f "$f2" ]]; then
        echo "  ONLY IN KSEQ: $fname"
    fi
done

# Also compare any numbered temp files (0_diffIdx, 0_info, etc.)
echo ""
echo "--- Numbered index files ---"
for f1 in "$DB_FSEEK"/*_diffIdx "$DB_FSEEK"/*_info; do
    [[ -f "$f1" ]] || continue
    fname=$(basename "$f1")
    f2="$DB_KSEQ/$fname"
    if [[ -f "$f2" ]]; then
        if cmp -s "$f1" "$f2"; then
            echo "  MATCH: $fname"
        else
            s1=$(wc -c < "$f1")
            s2=$(wc -c < "$f2")
            echo "  DIFFER: $fname (fseeko=${s1} bytes, kseq=${s2} bytes)"
        fi
    else
        echo "  ONLY IN FSEEK: $fname"
    fi
done
for f2 in "$DB_KSEQ"/*_diffIdx "$DB_KSEQ"/*_info; do
    [[ -f "$f2" ]] || continue
    fname=$(basename "$f2")
    f1="$DB_FSEEK/$fname"
    [[ -f "$f1" ]] || echo "  ONLY IN KSEQ: $fname"
done

echo ""
echo "--- File listings ---"
echo "fseeko DB:"
ls -la "$DB_FSEEK"/ | grep -v taxonomy | grep -v "^total" | grep -v "^d"
echo ""
echo "KSeqWrapper DB:"
ls -la "$DB_KSEQ"/ | grep -v taxonomy | grep -v "^total" | grep -v "^d"

echo ""
echo "--- stderr excerpts (k-mer counts) ---"
echo "fseeko stderr (last 30 lines):"
tail -30 "$WORK_DIR/stderr_fseek.log"
echo ""
echo "KSeqWrapper stderr (last 30 lines):"
tail -30 "$WORK_DIR/stderr_kseq.log"

echo ""
echo "Full logs at:"
echo "  $WORK_DIR/stderr_fseek.log"
echo "  $WORK_DIR/stderr_kseq.log"

# Keep temp dir on exit for manual inspection
trap '' EXIT
echo ""
echo "Working directory preserved: $WORK_DIR"
