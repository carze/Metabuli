#!/usr/bin/awk -f
# Usage: awk -f scripts/parse_bench_log.awk <benchmark_log>
#
# Parses a captured Metabuli benchmark log from --max-ram 128 (multi-flush run).
# Extracts per-cycle timings for K-mer extraction, Sort, Filter, and Write stages.
# Prints min/max/avg for each stage — suitable for SCALING_ANALYSIS.md Section 8.2.

/K-mer extraction/ { extract[++ne] = $NF }
/Sort k-mers/      { sort_t[++ns]  = $NF }
/Filter k-mers/    { filter[++nf]  = $NF }
/Write k-mers/     { write_t[++nw] = $NF }

function stats(arr, n,    i, min, max, sum) {
    if (n == 0) { print "N/A"; return }
    min = arr[1]; max = arr[1]; sum = 0
    for (i = 1; i <= n; i++) {
        if (arr[i] < min) min = arr[i]
        if (arr[i] > max) max = arr[i]
        sum += arr[i]
    }
    printf "min=%.0f  max=%.0f  avg=%.1f  (n=%d cycles)\n", min, max, sum/n, n
}

END {
    print "=== Per-Cycle Stage Summary ==="
    printf "K-mer extraction : "; stats(extract, ne)
    printf "Sort k-mers      : "; stats(sort_t,  ns)
    printf "Filter k-mers    : "; stats(filter,  nf)
    printf "Write k-mers     : "; stats(write_t, nw)
}
