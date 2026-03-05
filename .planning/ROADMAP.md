# Roadmap: Metabuli FASTA Random Access

## Overview

This milestone eliminates the dominant I/O bottleneck in Metabuli's database build pipeline by replacing
redundant sequential FASTA scanning with offset-indexed random access. Four phases deliver in dependency
order: the regression test harness is established first (both old and new builds are the same unmodified
code at this point — proving the harness itself works and establishing the correctness baseline), then the
build system safety guards and offset index infrastructure, then the actual inner loop refactor (harness
catches any divergence), and finally benchmarking to confirm the fix and identify the next bottleneck.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Testing Framework** - Mini FASTA corpus and regression script green on unmodified code — correctness baseline established
- [x] **Phase 2: Build System + Offset Index** - CMake 64-bit guards and parallel pre-pass offset index (completed 2026-03-05)
- [ ] **Phase 3: Inner Loop Refactor** - Replace sequential scans with fseeko random access in both extraction paths
- [ ] **Phase 4: Benchmarking and Validation** - Confirm I/O improvement at scale and document next bottleneck

## Phase Details

### Phase 1: Testing Framework
**Goal**: A byte-identical binary diff gate exists, passes green on the unmodified sequential implementation (both builds are the same code), and is ready to catch any divergence the inner loop refactor introduces
**Depends on**: Nothing (first phase)
**Requirements**: REGTEST-01, REGTEST-02, REGTEST-03, REGTEST-04
**Success Criteria** (what must be TRUE):
  1. A mini FASTA corpus in `test/data/` with ~3 files, ~10 accessions, at least one species spanning two files runs successfully with `--max-ram 1` forcing at least 2 buffer flushes
  2. `test/regression_fasta_access.sh` builds the same database twice from the same (unmodified) binary using `--threads 1 --max-ram 1` and exits 0 when `diffIdx`, `info`, and `split` are byte-identical via `cmp -s` — proving the harness itself is deterministic and correct
  3. `metabuli validateDatabase` passes on both builds, confirming k-mer count in `diffIdx` matches entry count in `info`
  4. The script exits non-zero and prints the first differing byte offset when the two builds differ
**Plans**: 2 plans
Plans:
- [ ] 01-01-PLAN.md — Synthetic FASTA corpus and taxonomy data files
- [ ] 01-02-PLAN.md — Regression harness script (build twice, validate, byte-compare)

### Phase 2: Build System + Offset Index
**Goal**: The offset index infrastructure is built, verified correct, and called from the build pipeline — without touching any k-mer extraction code
**Depends on**: Phase 1
**Requirements**: BUILD-01, BUILD-02, OFFIDX-01, OFFIDX-02, OFFIDX-03, OFFIDX-04, OFFIDX-05, OFFIDX-06, OFFIDX-07
**Success Criteria** (what must be TRUE):
  1. CMake compiles with `_FILE_OFFSET_BITS=64` on UNIX targets; `static_assert(sizeof(off_t) == 8)` fires on misconfigured builds and is confirmed by CI
  2. `buildFastaOffsetIndex()` runs in parallel across all FASTA files and populates `fastaOffsets[fileIdx][ordinal]` with `>` byte offsets (binary mode, position recorded before consuming the character)
  3. Gzip files are silently skipped: their offset vectors are left empty as a fallback sentinel (verified by magic byte detection)
  4. A spot-check validation samples random (fileIdx, ordinal) pairs and confirms each stored offset points to a `>` character
  5. `buildFastaOffsetIndex()` is wired into the build pipeline between `getObservedAccessions()` and `getTaxonomyOfAccessions()`
**Plans**: 2 plans
Plans:
- [ ] 02-01-PLAN.md — CMake _FILE_OFFSET_BITS=64 compile definition, static_assert, fastaOffsets field and method declaration in IndexCreator.h
- [ ] 02-02-PLAN.md — buildFastaOffsetIndex() implementation (parallel pre-pass, gzip detection, spot-check) and pipeline wiring

### Phase 3: Inner Loop Refactor
**Goal**: Both `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` use fseeko random access with per-batch FILE* handles, the regression harness is green, and gzip fallback is preserved
**Depends on**: Phase 2
**Requirements**: EXTKMER-01, EXTKMER-02, EXTKMER-03, EXTKMER-04, FILLTGT-01, FILLTGT-02, FILLTGT-03, FILLTGT-04, DOCS-01
**Success Criteria** (what must be TRUE):
  1. `extractKmerFromSixFrames()` seeks directly to each required sequence via `fseeko` (no scan from byte 0) when `fastaOffsets[whichFasta]` is non-empty; falls back to existing KSeqWrapper path for gzip files
  2. `fillTargetKmerBuffer()` applies the identical fseeko pattern with gzip fallback
  3. Batch orders are sorted by ascending byte offset before seeking in both functions (forward-only access, enabling OS read-ahead)
  4. Per-thread `seqBuf` vectors are reused across sequences in both functions, replacing per-sequence `new char[...]` / `delete[]`
  5. The regression script (`test/regression_fasta_access.sh`) exits 0 when comparing the old sequential build against the refactored fseeko build
  6. Build documentation states that gzip FASTA files must be decompressed before building large databases
**Plans**: TBD

### Phase 4: Benchmarking and Validation
**Goal**: A core_nt-scale (or representative >=100 GB subset) build is run with the new implementation, per-stage timings are recorded, and the results confirm the I/O improvement and identify the next bottleneck
**Depends on**: Phase 3
**Requirements**: BENCH-01, BENCH-02
**Success Criteria** (what must be TRUE):
  1. A build of core_nt or a >=100 GB representative subset completes successfully with the new implementation
  2. Per-stage wall-clock times are recorded: offset pre-pass, k-mer extraction, sort, filter, and write per flush cycle
  3. Benchmark results are documented showing build time before and after the I/O fix, with the next bottleneck (sort dominance or otherwise) identified
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Testing Framework | 1/2 | In Progress|  |
| 2. Build System + Offset Index | 2/2 | Complete   | 2026-03-05 |
| 3. Inner Loop Refactor | 0/TBD | Not started | - |
| 4. Benchmarking and Validation | 0/TBD | Not started | - |
