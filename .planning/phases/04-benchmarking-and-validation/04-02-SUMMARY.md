---
phase: 04-benchmarking-and-validation
plan: "02"
subsystem: tooling
tags: [bash, awk, benchmark, metabuli, core-nt, timing, log-parsing]

# Dependency graph
requires:
  - phase: 03-inner-loop-refactor
    provides: FASTA random access implementation whose timing we benchmark
  - phase: 04-01
    provides: Build wall-clock timer emitting "Build complete in Xs" line
provides:
  - scripts/benchmark_core_nt.sh — reproducible cloud benchmark runner with tee-based log capture
  - scripts/parse_bench_log.awk — per-cycle stage stats extractor (min/max/avg for 4 stages)
  - SCALING_ANALYSIS.md Section 8 — benchmark results template with predicted vs actual tables
affects: [04-03-results, cloud-run-execution]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Benchmark runner: tee -a captures stdout+stderr to timestamped log file alongside binary execution"
    - "AWK stats function: accumulates per-cycle timing values into min/max/avg summary without external tools"

key-files:
  created:
    - scripts/benchmark_core_nt.sh
    - scripts/parse_bench_log.awk
  modified:
    - SCALING_ANALYSIS.md

key-decisions:
  - "Log path derived from max-ram parameter (benchmark_ram${MAX_RAM}.log) so single-flush and multi-flush runs produce distinct log files"
  - "parse_bench_log.awk uses $NF (last field) to extract timing values — robust to varying whitespace/label formatting"
  - "Section 8 placeholder cells use dash (—) not TBD — visually distinct from text TBD fields and table-friendly"

patterns-established:
  - "Benchmark scripts: parameterize binary path and DB output dir; derive log name from config params"
  - "Post-run analysis: awk script reads log directly — no intermediate files, no Python dependency"

requirements-completed: [BENCH-01, BENCH-02]

# Metrics
duration: 2min
completed: 2026-03-09
---

# Phase 4 Plan 02: Benchmark Operational Tooling Summary

**Benchmark runner script with tee-based log capture, AWK per-cycle stats parser, and SCALING_ANALYSIS.md Section 8 results template with predicted-vs-actual tables ready for cloud run**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-09T12:42:44Z
- **Completed:** 2026-03-09T12:44:39Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `scripts/benchmark_core_nt.sh` — accepts binary, db_out, fasta_list, acc2taxid, taxonomy_dir, max_ram, threads; captures all stdout+stderr via `tee -a` to `${DB_OUT}/benchmark_ram${MAX_RAM}.log`; designed for tmux/nohup cloud sessions
- Created `scripts/parse_bench_log.awk` — reads multi-flush benchmark log, extracts per-cycle timings for all four stages (K-mer extraction, Sort, Filter, Write), prints min/max/avg with cycle count
- Added Section 8 to SCALING_ANALYSIS.md with subsections 8.1 (single-flush predicted vs actual), 8.2 (per-cycle multi-flush summary), 8.3 (before/after comparison), 8.4 (reproduction commands); committed previously-untracked file to git

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/benchmark_core_nt.sh and scripts/parse_bench_log.awk** - `23a86763` (feat)
2. **Task 2: Add Section 8 to SCALING_ANALYSIS.md and commit to git** - `81b3c44c` (feat)

## Files Created/Modified

- `scripts/benchmark_core_nt.sh` - Reproducible benchmark runner; tee-based stdout+stderr capture to per-config log file; positional args for all Metabuli build parameters
- `scripts/parse_bench_log.awk` - Post-run log parser; accumulates per-stage timing values; prints min/max/avg summary table for SCALING_ANALYSIS.md Section 8.2
- `SCALING_ANALYSIS.md` - Added Section 8 benchmark results structure (subsections 8.1-8.4); updated Section 7 open question to note pending cloud run; file committed from previously-untracked state

## Decisions Made

- Log path derived from `max-ram` parameter (`benchmark_ram${MAX_RAM}.log`) so single-flush (1000 GB) and multi-flush (128 GB) runs produce distinct log files without overwriting each other
- `parse_bench_log.awk` uses `$NF` (last field) to extract timing values — robust to varying whitespace between label and number in Metabuli output
- Section 8 placeholder cells use dash character (—) rather than "TBD" — visually clear in markdown tables and semantically distinct from the text "TBD" fields in the header block

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both scripts are ready to run on cloud instance; copy `scripts/` directory alongside Metabuli binary
- Section 8 tables in SCALING_ANALYSIS.md are ready to fill after cloud run completes
- Run `./scripts/benchmark_core_nt.sh ./metabuli /data/db_1000 ...` for single-flush, repeat with `128` for multi-flush
- After multi-flush run: `awk -f scripts/parse_bench_log.awk /data/db_128/benchmark_ram128.log` to get Section 8.2 values

---
*Phase: 04-benchmarking-and-validation*
*Completed: 2026-03-09*

## Self-Check: PASSED

- FOUND: scripts/benchmark_core_nt.sh
- FOUND: scripts/parse_bench_log.awk
- FOUND: SCALING_ANALYSIS.md
- FOUND: .planning/phases/04-benchmarking-and-validation/04-02-SUMMARY.md
- FOUND commit: 23a86763 (Task 1)
- FOUND commit: 81b3c44c (Task 2)
