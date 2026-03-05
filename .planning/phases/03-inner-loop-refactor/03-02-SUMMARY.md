---
phase: 03-inner-loop-refactor
plan: "02"
subsystem: database
tags: [fseeko, ftello, fasta, random-access, openmp, kmer-extraction, indexcreator, prodigal]

# Dependency graph
requires:
  - phase: 03-inner-loop-refactor
    plan: "01"
    provides: readFastaSequence() static helper; fseeko pattern established in extractKmerFromSixFrames; offsets.empty() gzip sentinel
  - phase: 02-build-system-offset-index
    provides: fastaOffsets vector populated during DB build; _FILE_OFFSET_BITS=64 compile flag; off_t 64-bit guarantee
provides:
  - fseeko random-access branch in fillTargetKmerBuffer() with gzip KSeq fallback
  - per-thread seqBuf and rcBuf replacing per-sequence new/delete allocations in Prodigal RC path
  - cdsInfoMap key extraction via header re-seek after readFastaSequence
affects:
  - 03-03 (documentation, gzip limitation note)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Header re-seek pattern: after readFastaSequence loads body, fseeko back to curOff + fgets extracts accession name for map lookup"
    - "Prodigal forward strand: Prodigal gene prediction on raw seqBuf BEFORE in-place masking; extractTargetKmers on masked seqBuf"
    - "Prodigal RC strand: reverseComplement (malloc), Prodigal on rc, rcBuf for masked RC; free(rc)"
    - "rcBuf resize on each RC sequence (lazy allocation, reused across batches via vector capacity)"
    - "Sort-permutation pattern reused from Plan 01: iota + sort on sortedIdx preserves parallel arrays"

key-files:
  created: []
  modified:
    - src/commons/IndexCreator.cpp

key-decisions:
  - "seqBuf and rcBuf declared inside omp parallel block (per-thread) — not in shared() list"
  - "Header re-seek: after readFastaSequence has loaded the body, seek back to curOff to extract the FASTA accession name for cdsInfoMap lookup"
  - "Training sequence reads (trainingSeqFasta / trainingSeqIdx) preserved unchanged on KSeqWrapper path in both fseeko and gzip branches"
  - "Forward Prodigal: masking happens AFTER getExtendedORFs, before extractTargetKmers — matches original code order where Prodigal saw unmasked sequence"
  - "RC maskedRC pointer: const char* pointing to either rcBuf.data() (maskMode=true) or rc (maskMode=false); free(rc) always called after"
  - "Gzip fallback else branch: original KSeqWrapper scan copied verbatim including maskedSeq new/delete and training sequence block"

patterns-established:
  - "Two-fseeko pattern for cdsInfoMap: readFastaSequence to load body, then fseeko again to extract header name"
  - "rcBuf strategy: vector<char> per-thread with resize(seqBytes+1) on each RC sequence; null-terminate after mask"

requirements-completed: [FILLTGT-01, FILLTGT-02, FILLTGT-03, FILLTGT-04]

# Metrics
duration: 4min
completed: 2026-03-05
---

# Phase 3 Plan 02: fillTargetKmerBuffer fseeko Refactor Summary

**fseeko sort-by-offset random access + per-thread seqBuf/rcBuf replaces O(N) sequential FASTA scan in fillTargetKmerBuffer Prodigal path, with header re-seek for cdsInfoMap lookup and KSeq gzip fallback**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-05T18:51:41Z
- **Completed:** 2026-03-05T18:55:13Z
- **Tasks:** 1/1
- **Files modified:** 1

## Accomplishments

- Refactored `fillTargetKmerBuffer()` fseeko branch: sort permutation by ascending byte offset, fopen once per batch, `readFastaSequence()` per ordinal, header re-seek for `cdsInfoMap` key extraction
- CDS path: in-place `maskLowComplexityRegions` on `seqBuf` before `devideToCdsAndNonCds` (no new/delete)
- Prodigal forward path: `getPredictedGenes`/`getExtendedORFs` on raw `seqBuf`, masking after, `extractTargetKmers` on masked `seqBuf`
- Prodigal RC path: `reverseComplement` (malloc), Prodigal on rc, `rcBuf.data()` for masked RC (not new char[]), `free(rc)` on exit
- Training sequence block unchanged: KSeqWrapper path preserved in both fseeko and gzip branches
- Original KSeqWrapper sequential scan preserved verbatim as gzip fallback (`offsets.empty()`)
- Per-thread `seqBuf` and `rcBuf` vectors declared inside `#pragma omp parallel` block
- Regression script passes: 99,924 k-mers, byte-identical between both builds

## Task Commits

1. **Task 1: Refactor fillTargetKmerBuffer main scan loop to use fseeko with gzip fallback and vector buffers** - `4eacf059` (feat)

**Plan metadata:** (docs commit — see final_commit step)

## Files Created/Modified

- `src/commons/IndexCreator.cpp` - Added `seqBuf`/`rcBuf` per-thread vectors, fseeko branch replacing KSeq-only inner loop in `fillTargetKmerBuffer()`, header re-seek for cdsInfoMap key, verbatim KSeq gzip fallback

## Decisions Made

- `seqBuf` and `rcBuf` declared inside the `#pragma omp parallel` block (per-thread) so they don't appear in `shared()` list
- Header re-seek chosen over storing accession in batch metadata: `readFastaSequence` only loads the body (strips header), so re-seeking to `curOff` and `fgets` extracting the name was the least-invasive approach requiring no data structure changes
- Training sequence reads stay on KSeqWrapper in both branches — this was a locked decision from CONTEXT.md; Prodigal training requires a full sequence scan that doesn't benefit from offset indexing and touches a different file
- Forward Prodigal masking happens AFTER `getExtendedORFs` — verified against original code: original passed `e.sequence.s` (raw) to Prodigal and `maskedSeq` to `extractTargetKmers`; new code matches by masking in-place after Prodigal calls
- `const char* maskedRC` avoids a separate variable for the RC masking destination: points to `rcBuf.data()` when `maskMode=true`, or directly to `rc` when `maskMode=false`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Build was clean on first attempt; regression test passed immediately with 99,924 k-mers byte-identical.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Both inner loop functions (`extractKmerFromSixFrames` and `fillTargetKmerBuffer`) now use fseeko for FASTA files with offset indices
- Plan 03 (documentation) can proceed: gzip limitation note, README update, CHANGELOG
- Build system already has all required plumbing from Phase 02

## Self-Check: PASSED

- IndexCreator.cpp: FOUND
- 03-02-SUMMARY.md: FOUND
- Commit 4eacf059 (Task 1): FOUND
- Build: clean (no errors, pre-existing warnings only)
- Regression: PASS (99,924 k-mers, byte-identical)
- offsets.empty() appears twice (lines 1091, 1269) — once per function
- new char[ only in gzip fallback branches (lines 1164, 1482, 1596)
- delete[] maskedSeq only in gzip fallback branches (lines 1181, 1595, 1620)
- trainingSeqFasta preserved in both fseeko (line 1365) and gzip (line 1529) branches

---
*Phase: 03-inner-loop-refactor*
*Completed: 2026-03-05*
