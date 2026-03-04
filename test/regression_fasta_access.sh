#!/usr/bin/env bash
set -euo pipefail

# Usage: ./test/regression_fasta_access.sh <path-to-metabuli-binary>
BINARY="${1:?Usage: $0 <path-to-metabuli-binary>}"

# Derive data paths from script location — no hardcoded paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

# Create temp directories for two independent builds + temp fasta.list
BUILD1=$(mktemp -d)
BUILD2=$(mktemp -d)
FASTA_LIST=$(mktemp)
trap 'rm -rf "$BUILD1" "$BUILD2"; rm -f "$FASTA_LIST"' EXIT

# Generate fasta.list at runtime with absolute paths
printf '%s\n' \
    "$DATA_DIR/seq1.fasta" \
    "$DATA_DIR/seq2.fasta" \
    "$DATA_DIR/seq3.fasta" > "$FASTA_LIST"

# Build step — run twice with identical arguments to establish determinism baseline
"$BINARY" build "$BUILD1" "$FASTA_LIST" \
    "$DATA_DIR/accession2taxid.tsv" \
    --taxonomy-path "$DATA_DIR/taxonomy" \
    --threads 1 --max-ram 1

"$BINARY" build "$BUILD2" "$FASTA_LIST" \
    "$DATA_DIR/accession2taxid.tsv" \
    --taxonomy-path "$DATA_DIR/taxonomy" \
    --threads 1 --max-ram 1

# Validate — confirm each build passes structural integrity checks (REGTEST-03)
if ! "$BINARY" validateDatabase "$BUILD1"; then
    echo "FAIL: validateDatabase failed on build1" >&2
    exit 1
fi
if ! "$BINARY" validateDatabase "$BUILD2"; then
    echo "FAIL: validateDatabase failed on build2" >&2
    exit 1
fi

# Compare — byte-compare deterministic output files (REGTEST-02, REGTEST-04)
# Excludes taxID_list and db.parameters (db.parameters contains a build timestamp)
for FILE in diffIdx info split; do
    if ! cmp -s "$BUILD1/$FILE" "$BUILD2/$FILE"; then
        OFFSET=$(cmp "$BUILD1/$FILE" "$BUILD2/$FILE" 2>&1 | awk '{print $5}' | tr -d ',')
        echo "FAIL: $FILE differs at byte offset $OFFSET" >&2
        exit 1
    fi
done

echo "PASS"
