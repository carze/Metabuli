---
phase: 02-build-system-offset-index
plan: "02"
subsystem: database
tags: [fasta, offset-index, openmp, parallel, random-access, fseeko]

# Dependency graph
requires:
  - phase: 02-build-system-offset-index plan 01
    provides: IndexCreator.h with fastaOffsets/fastaPaths members, buildFastaOffsetIndex() declaration, _FILE_OFFSET_BITS=64 CMake config, static_assert(sizeof(off_t)==8)
provides:
  - buildFastaOffsetIndex() implementation in IndexCreator.cpp
  - Parallel fgetc scan populating fastaOffsets[fileIdx][ordinal] with byte offsets of '>' chars
  - gzip magic byte detection (0x1F 0x8B) — silently skips compressed files
  - Spot-check validation: up to 100 random fseeko checks confirm stored offsets point to '>'
  - Call site wired in indexReferenceSequences() between getObservedAccessions() and getTaxonomyOfAccessions()
affects: [03-random-access-reader, phase 3 implementation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ftello() called BEFORE fgetc() to record pre-consumption position of '>' char"
    - "fastaOffsets.resize() before #pragma omp parallel for prevents race conditions"
    - "Each thread writes only to fastaOffsets[i] via its own loop variable — no omp critical needed"
    - "fopen with 'rb' binary mode for cross-platform byte-accurate scanning"
    - "rewind() after magic byte check ensures scan starts at byte 0"
    - "Spot-check uses srand(time(nullptr)) — no fixed seed per CONTEXT decision"

key-files:
  created: []
  modified:
    - src/commons/IndexCreator.cpp

key-decisions:
  - "Spot-check loop iterates up to min(100, validPairs.size()) random entries — avoids O(N) validation cost on large corpora"
  - "gzip sentinel is silent skip (continue) not an error — mixed gzip/plain FASTA lists are valid"
  - "Spot-check build of validPairs iterates all (fileIdx, ordinal) pairs to ensure uniform coverage across files"

patterns-established:
  - "Parallel file scan pattern: resize outer vector before parallel for, each thread writes only its slot"
  - "Magic byte gzip check pattern: read 2 bytes, check 0x1F/0x8B, rewind before real scan"
  - "fseeko spot-check pattern: open file, seek to stored offset, confirm fgetc returns expected char"

requirements-completed: [OFFIDX-02, OFFIDX-03, OFFIDX-04, OFFIDX-05, OFFIDX-06, OFFIDX-07]

# Metrics
duration: 2min
completed: 2026-03-05
---

# Phase 02 Plan 02: Build FASTA Offset Index Summary

**Parallel fgetc pre-pass builds fastaOffsets[fileIdx][ordinal] lookup table with gzip detection and fseeko spot-check validation, wired into indexReferenceSequences() between accession scan and taxonomy lookup**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-05T16:40:38Z
- **Completed:** 2026-03-05T16:42:19Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- `buildFastaOffsetIndex()` fully implemented in `src/commons/IndexCreator.cpp` — parallel OpenMP scan over all FASTA files, recording byte offset of every `>` header character using `ftello()` before `fgetc()`
- gzip detection via magic bytes (0x1F 0x8B) — compressed files are silently skipped, leaving `fastaOffsets[i]` empty as sentinel
- Spot-check validation confirms up to 100 random stored offsets via `fseeko` + `fgetc` — exits with error if any offset doesn't point to `>`
- Call site wired in `indexReferenceSequences()` between `getObservedAccessions()` and `getTaxonomyOfAccessions()` — build log prints "Building FASTA offset index..." and completion summary
- Regression harness passes: two byte-identical builds, both `validatedb` clean, `PASS` output

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement buildFastaOffsetIndex() in IndexCreator.cpp** - `d327c0f7` (feat)
2. **Task 2: Wire buildFastaOffsetIndex() into indexReferenceSequences() and run regression** - `dd1e8c04` (feat)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified

- `src/commons/IndexCreator.cpp` - Added `buildFastaOffsetIndex()` implementation (86 lines) and call site in `indexReferenceSequences()`

## Decisions Made

- Spot-check `validPairs` vector is built by iterating all (fileIdx, ordinal) pairs to ensure uniform random coverage across files of different sizes — avoids bias toward large files
- gzip files are a silent skip, not an error — mixed gzip/plain FASTA input lists are a valid expected use case
- Spot-check uses `srand(time(nullptr))` per CONTEXT decision — no fixed seed, varies per build run

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Regression script invoked with `./build/metabuli` (per plan docs) but actual binary path is `./build/src/metabuli` — corrected binary path. Not a code issue; regression passed on first real attempt.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `fastaOffsets[fileIdx][ordinal]` is fully populated during every `metabuli build` run
- Phase 3 (random access reader) can use `fseeko(fp, fastaOffsets[fi][ord], SEEK_SET)` to jump directly to any sequence header
- Concern: ordinal mismatch risk between this pre-pass and `getObservedAccessions()` KSeqWrapper ordering — Phase 3 planning must validate that ordinals are consistent

---
*Phase: 02-build-system-offset-index*
*Completed: 2026-03-05*

## Self-Check: PASSED

- src/commons/IndexCreator.cpp: FOUND
- .planning/phases/02-build-system-offset-index/02-02-SUMMARY.md: FOUND
- Commit d327c0f7 (Task 1): FOUND
- Commit dd1e8c04 (Task 2): FOUND
