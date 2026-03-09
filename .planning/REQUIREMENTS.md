# Requirements: Metabuli FASTA Random Access

**Defined:** 2026-03-04
**Core Value:** Eliminate redundant FASTA I/O so Metabuli can build core_nt-scale databases in hours instead of days

## v1 Requirements

### Build System

- [x] **BUILD-01**: CMakeLists.txt defines `_FILE_OFFSET_BITS=64` for UNIX targets, ensuring `off_t` is 64-bit on 32-bit Linux
- [x] **BUILD-02**: A `static_assert(sizeof(off_t) == 8, ...)` compile-time guard catches misconfigured builds before they produce silently wrong offsets

### Offset Index

- [x] **OFFIDX-01**: `IndexCreator` stores a `vector<vector<uint64_t>> fastaOffsets` field where `fastaOffsets[fileIdx][ordinal]` is the byte offset of the `>` header character for that sequence
- [x] **OFFIDX-02**: `buildFastaOffsetIndex()` scans all FASTA files in a single parallel pre-pass using OpenMP `schedule(dynamic, 1)` across files
- [x] **OFFIDX-03**: Files are opened in binary mode (`"rb"`) during the pre-pass to ensure `ftello()` returns physical byte positions (not CRLF-adjusted positions)
- [x] **OFFIDX-04**: Offset recording stores the position of `>` (before reading the character, not after), so `fseeko` to that offset positions the file pointer at the start of the header
- [x] **OFFIDX-05**: Gzip files are detected via magic bytes (`0x1F 0x8B`) during the pre-pass; their offset vectors are left empty as a fallback sentinel
- [x] **OFFIDX-06**: `buildFastaOffsetIndex()` is called between `getObservedAccessions()` and `getTaxonomyOfAccessions()` in the build pipeline
- [x] **OFFIDX-07**: A spot-check validation confirms stored offsets point to `>` characters by sampling a random subset of (fileIdx, ordinal) pairs after the pre-pass

### Inner Loop Refactor — extractKmerFromSixFrames()

- [x] **EXTKMER-01**: If `fastaOffsets[whichFasta]` is non-empty, the function uses `fseeko()` to seek directly to each required sequence instead of scanning from byte 0
- [x] **EXTKMER-02**: Batch orders are sorted by byte offset before seeking, ensuring forward-only sequential access within each batch (enables OS read-ahead)
- [x] **EXTKMER-03**: If `fastaOffsets[whichFasta]` is empty (gzip fallback), the function falls back to the existing KSeqWrapper sequential scan path
- [x] **EXTKMER-04**: A per-thread `seqBuf` vector is reused across all sequences in a batch, replacing the per-sequence `maskedSeq = new char[...]` / `delete[]` pattern

### Inner Loop Refactor — fillTargetKmerBuffer()

- [x] **FILLTGT-01**: If `fastaOffsets[whichFasta]` is non-empty, the function uses `fseeko()` to seek directly to each required sequence instead of scanning from byte 0
- [x] **FILLTGT-02**: Batch orders sorted by byte offset before seeking (same as EXTKMER-02)
- [x] **FILLTGT-03**: Gzip fallback to existing sequential path when offset vector is empty (same as EXTKMER-03)
- [x] **FILLTGT-04**: Per-thread `seqBuf` vector reused across sequences (same as EXTKMER-04)

### Regression Testing

- [x] **REGTEST-01**: A mini-corpus of ~3 uncompressed FASTA files, ~4 species, ~10 accessions is committed to `test/data/` — designed so at least one species has sequences across two FASTA files, and `--max-ram 1` forces at least 2 buffer flushes
- [x] **REGTEST-02**: A shell script `test/regression_fasta_access.sh` builds the same database with the old (sequential) and new (fseeko) implementations using `--threads 1 --max-ram 1`, then byte-compares `diffIdx`, `info`, and `split` with `cmp -s`
- [x] **REGTEST-03**: `metabuli validateDatabase` passes on both the old and new builds, confirming internal consistency (k-mer count in `diffIdx` matches entry count in `info`)
- [x] **REGTEST-04**: The regression script exits non-zero and prints the first differing byte offset if any output file differs

### Benchmarking

- [x] **BENCH-01**: A build of core_nt (or a ≥100 GB representative subset) is run with the new implementation, recording per-stage wall-clock time: offset pre-pass, k-mer extraction, sort, filter, write per flush cycle
- [ ] **BENCH-02**: Benchmark results are documented (build time before and after, per-stage breakdown) to confirm the I/O improvement and identify the next bottleneck

### Documentation

- [x] **DOCS-01**: A note is added to the build documentation explaining that gzip FASTA files are not supported for random access and must be decompressed before building large databases

## v2 Requirements

### Consolidated Single-Pass (Deferred)

- **CONSOLIDATE-01**: Integrate offset recording into `getObservedAccessions()` so both accession discovery and offset building happen in a single file scan — eliminates the separate pre-pass and the ordinal mismatch risk entirely
- **CONSOLIDATE-02**: If consolidated, remove the spot-check validation (OFFIDX-07) as ordinal mismatch becomes architecturally impossible

### Performance Enhancements (Deferred — evaluate after BENCH-01 confirms sort is next bottleneck)

- **PERF-01**: Replace `fgetc`-per-byte pre-pass scanner with `fread` 64 KB blocks + `memchr` for `>` — achieves full disk I/O throughput for the pre-pass
- **PERF-02**: Per-thread cached `FILE*` handles keyed by `fileIdx` — eliminates `fopen`/`fclose` overhead when a thread processes multiple batches from the same file
- **PERF-03**: Pre-convert nucleotide sequences to integer arrays once per sequence before six-frame loop — eliminates 3× redundant `atcg[]` character lookups (~20-35% translation speedup)
- **PERF-04**: Flatten `nuc2aa[8][8][8]` to `nuc2aa_flat[512]` — eliminates 3 dependent pointer-chasing cache accesses per codon lookup

### External/Prefix-Based Sorting (Deferred — major architectural change)

- **SORT-01**: Write k-mers to per-prefix temporary files based on upper bits of value, then sort each prefix independently — reduces per-flush sort time, critical if 280 flush cycles remain the bottleneck after I/O fix

## Out of Scope

| Feature | Reason |
|---------|--------|
| CUDA acceleration | GPU target not decided; evaluate after benchmarking confirms sort dominance |
| SIMD batch translation | Depends on PERF-03; evaluate after CUDA decision |
| Dynamic split count scaling | Query-time improvement, not build-time critical |
| Query-time (classification) performance | Not yet evaluated at core_nt scale |
| bgzip + .gzi random access for compressed FASTA | High complexity; decompressing input files is the pragmatic v1 approach |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REGTEST-01 | Phase 1 | Complete |
| REGTEST-02 | Phase 1 | Complete |
| REGTEST-03 | Phase 1 | Complete |
| REGTEST-04 | Phase 1 | Complete |
| BUILD-01 | Phase 2 | Complete |
| BUILD-02 | Phase 2 | Complete |
| OFFIDX-01 | Phase 2 | Complete |
| OFFIDX-02 | Phase 2 | Complete |
| OFFIDX-03 | Phase 2 | Complete |
| OFFIDX-04 | Phase 2 | Complete |
| OFFIDX-05 | Phase 2 | Complete |
| OFFIDX-06 | Phase 2 | Complete |
| OFFIDX-07 | Phase 2 | Complete |
| EXTKMER-01 | Phase 3 | Complete |
| EXTKMER-02 | Phase 3 | Complete |
| EXTKMER-03 | Phase 3 | Complete |
| EXTKMER-04 | Phase 3 | Complete |
| FILLTGT-01 | Phase 3 | Complete |
| FILLTGT-02 | Phase 3 | Complete |
| FILLTGT-03 | Phase 3 | Complete |
| FILLTGT-04 | Phase 3 | Complete |
| DOCS-01 | Phase 3 | Complete |
| BENCH-01 | Phase 4 | Complete |
| BENCH-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-04*
*Last updated: 2026-03-04 — traceability updated after phase reorder (Testing Framework promoted to Phase 1)*
