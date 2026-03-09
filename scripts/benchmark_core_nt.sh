#!/usr/bin/env bash
# Usage: ./scripts/benchmark_core_nt.sh <binary> <db_out> <fasta_list> <acc2taxid> <taxonomy_dir> [max_ram] [threads]
#
# Runs a Metabuli database build, capturing all output (stdout+stderr) to a log file.
# Designed for multi-hour cloud runs. Use inside tmux or with nohup for session persistence.
#
# Session persistence (recommended):
#   tmux new-session -d -s bench
#   tmux send-keys -t bench './scripts/benchmark_core_nt.sh ./metabuli /data/db /data/fasta.list /data/acc2taxid.tsv /data/taxonomy 1000' Enter
#
# nohup alternative:
#   nohup ./scripts/benchmark_core_nt.sh ... > /data/bench.log 2>&1 &

set -euo pipefail

BINARY="${1:?Usage: $0 <binary> <db_out> <fasta_list> <acc2taxid> <taxonomy_dir> [max_ram] [threads]}"
DB_OUT="${2:?}"
FASTA_LIST="${3:?}"
ACC2TAXID="${4:?}"
TAXONOMY="${5:?}"
MAX_RAM="${6:-1000}"
THREADS="${7:-100}"

LOG="${DB_OUT}/benchmark_ram${MAX_RAM}.log"

mkdir -p "$DB_OUT"

echo "=== Metabuli Benchmark ===" | tee "$LOG"
echo "Binary:     $BINARY" | tee -a "$LOG"
echo "DB out:     $DB_OUT" | tee -a "$LOG"
echo "FASTA list: $FASTA_LIST" | tee -a "$LOG"
echo "max-ram:    $MAX_RAM" | tee -a "$LOG"
echo "threads:    $THREADS" | tee -a "$LOG"
echo "Start time: $(date -u)" | tee -a "$LOG"
echo "===========================" | tee -a "$LOG"

"$BINARY" build "$DB_OUT" "$FASTA_LIST" "$ACC2TAXID" \
    --taxonomy-path "$TAXONOMY" \
    --threads "$THREADS" \
    --max-ram "$MAX_RAM" \
    2>&1 | tee -a "$LOG"

echo "===========================" | tee -a "$LOG"
echo "End time:   $(date -u)" | tee -a "$LOG"
echo "Log:        $LOG" | tee -a "$LOG"
