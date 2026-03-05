---
phase: 03-inner-loop-refactor
plan: "01"
subsystem: database
tags: [fseeko, ftello, fasta, random-access, openmp, kmer-extraction, indexcreator]

# Dependency graph
requires:
  - phase: 02-build-system-offset-index
    provides: fastaOffsets vector populated during DB build; _FILE_OFFSET_BITS=64 compile flag; off_t 64-bit guarantee
provides:
  - readFastaSequence() static helper in IndexCreator.cpp (reusable by Plan 02)
  - fseeko random-access branch in extractKmerFromSixFrames() with gzip KSeq fallback
  - per-thread seqBuf replacing per-sequence new/delete allocations
affects:
  - 03-02 (fillTargetKmerBuffer refactor — reuses readFastaSequence helper)
  - 03-03 (documentation, gzip limitation note)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sort-permutation pattern: std::iota + std::sort on index vector preserves parallel arrays (orders/taxIDs/lengths)"
    - "Static file-scope helper for FASTA I/O: readFastaSequence(fp, curOff, nextOff, buf)"
    - "Per-thread vector<char> seqBuf declared inside omp parallel block (one allocation reused across all batches)"
    - "In-place maskLowComplexityRegions: src==dst pointer safe, avoids extra copy"
    - "nextOffset==0 sentinel: last sequence in file uses SEEK_END to determine body length"

key-files:
  created: []
  modified:
    - src/commons/IndexCreator.cpp

key-decisions:
  - "readFastaSequence helper placed file-scope static (not class method) so Plan 02 can reuse it without header change"
  - "Sort permutation via iota+sort on sortedIdx avoids mutating orders[], taxIDs[], lengths[] parallel arrays"
  - "seqBuf declared inside #pragma omp parallel block (per-thread), not in shared() list"
  - "fopen/fclose per batch (not per thread) — future Plan 02 may cache FILE* per thread if profiling shows overhead"
  - "Gzip fallback (KSeq path) preserved exactly as original code; only triggered when offsets.empty()"

patterns-established:
  - "FASTA offset sentinel: ordinal+1 >= offsets.size() means last sequence; nextOff=0 signals readFastaSequence to SEEK_END"
  - "taxID==0 guard checked before expensive fopen in fseeko path"
  - "Build verification: cmake --build then regression_fasta_access.sh for byte-identical output check"

requirements-completed: [EXTKMER-01, EXTKMER-02, EXTKMER-03, EXTKMER-04]

# Metrics
duration: 15min
completed: 2026-03-05
---

# Phase 3 Plan 01: extractKmerFromSixFrames fseeko Refactor Summary

**readFastaSequence static helper + fseeko sort-by-offset random access replaces O(N) sequential FASTA scan in extractKmerFromSixFrames, with in-place seqBuf masking and KSeq gzip fallback**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-05T18:33:00Z
- **Completed:** 2026-03-05T18:48:00Z
- **Tasks:** 2/2
- **Files modified:** 1

## Accomplishments

- Added `readFastaSequence()` file-scope static helper: fseeko seek, FASTA header skip (long-header safe), bounded fread, newline-strip in-place, 0-sentinel for last sequence
- Refactored `extractKmerFromSixFrames()` fseeko branch: builds sort permutation by ascending byte offset, opens FILE* once per batch, calls `readFastaSequence()` per ordinal, null-terminates seqBuf, in-place `maskLowComplexityRegions` (no new/delete)
- Original KSeqWrapper sequential scan preserved exactly as gzip fallback when `fastaOffsets[whichFasta].empty()`
- Per-thread `seqBuf` vector declared inside the `#pragma omp parallel` block — zero heap allocation per sequence
- Regression script passes: both builds produce byte-identical 166,551 k-mers

## Task Commits

1. **Task 1: Add readFastaSequence static helper** - `20321b9f` (feat)
2. **Task 2: Refactor extractKmerFromSixFrames fseeko + seqBuf** - `0acb47dc` (feat)

**Plan metadata:** (docs commit — see final_commit step)

## Files Created/Modified

- `src/commons/IndexCreator.cpp` - Added `#include <numeric>`, `readFastaSequence()` static helper (lines 1007-1047), `std::vector<char> seqBuf` per-thread variable, fseeko branch replacing KSeq-only inner loop in `extractKmerFromSixFrames()`

## Decisions Made

- `readFastaSequence` placed as file-scope static (not class method) so Plan 02 (`fillTargetKmerBuffer`) can call it without touching `IndexCreator.h`
- Sort permutation pattern (iota + sort on index vector) chosen over sorting orders[] in-place because `taxIDs[]` and `lengths[]` are parallel arrays that must maintain positional correspondence
- `seqBuf` declared inside the `#pragma omp parallel` block (not outside) so it doesn't appear in `shared()` list — each thread owns its own resizable buffer
- `fopen`/`fclose` done per-batch (not cached per-thread) for simplicity; Plan 02 can revisit if profiling shows overhead
- `nextOffset == 0` sentinel (not a special flag field) chosen because ordinal+1 >= offsets.size() is unambiguous and requires no API surface changes

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Build was clean on first attempt; regression test passed immediately.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `readFastaSequence()` helper is immediately usable by Plan 02 (`fillTargetKmerBuffer` refactor)
- `fastaOffsets[whichFasta].empty()` gzip sentinel works identically for both functions
- Build system already has `_FILE_OFFSET_BITS=64` from Phase 02 — no further plumbing needed

## Self-Check: PASSED

- IndexCreator.cpp: FOUND
- 03-01-SUMMARY.md: FOUND
- Commit 20321b9f (Task 1): FOUND
- Commit 0acb47dc (Task 2): FOUND

---
*Phase: 03-inner-loop-refactor*
*Completed: 2026-03-05*
