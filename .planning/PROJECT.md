# Metabuli Scaling — Phase 1: FASTA Random Access

## What This Is

Metabuli is a metagenomic taxonomic classifier using dual-layer "metamer" k-mers that encode both amino acid identity (40 bits) and synonymous codon usage (24 bits) in a single 64-bit key. This enables protein-level sensitivity for homology detection while retaining DNA-level specificity for strain discrimination — a capability DIAMOND-style tools discard entirely.

This project delivers the first scaling phase: eliminating the dominant I/O bottleneck that makes building reference-level databases (core_nt ~900 GB, ~20M batches) take ~22 days instead of hours. The current branch (`feat/fasta-random-access`) is already in progress.

## Core Value

Replace redundant sequential FASTA scanning with offset-indexed random access so that 900 GB of reference data is read once instead of ~7,500 times — reducing database build time from ~22 days to ~10-12 hours.

## Requirements

### Validated

- ✓ Six-frame translation + metamer assembly pipeline works — existing
- ✓ Database builds functional for smaller references (GTDB, viral databases) — existing
- ✓ KSeqFactory-based sequential FASTA reading functional (but bottlenecked at scale) — existing
- ✓ OpenMP multi-threading for parallel batch processing — existing
- ✓ Memory-bounded processing via configurable `--max-ram` — existing
- ✓ Differential index encoding (diffIdx + delta) produces compact, queryable databases — existing
- ✓ LCA + EM-based taxonomic assignment pipeline — existing
- ✓ Cross-platform builds (Linux AVX2/SSE2/ARM64, macOS Universal, Windows) — existing

### Active

- [ ] FASTA offset index built in one parallel pre-pass: `fastaOffsets[fileIdx][ordinal] = byte_offset`
- [ ] `extractKmerFromSixFrames()` uses `fseek()`-based random access instead of sequential scan from byte 0
- [ ] `fillTargetKmerBuffer()` uses `fseek()`-based random access instead of sequential scan from byte 0
- [ ] Per-thread sequence buffer (`seqBuf` vector) reused across sequences, replacing both KSeq's internal buffer and the per-sequence `maskedSeq` malloc/free
- [ ] Index build is parallelized across files (2,382 files × 378 MB each scanned once, not 8,400× each)
- [ ] Classification output is identical to current implementation on regression test dataset
- [ ] Gzip FASTA limitation is documented: `.gz` files require bgzip + `.gzi` index for random access; plain sequential mode used as fallback
- [ ] Benchmark data collected on core_nt or representative subset with per-stage timing (I/O, extraction, sort, filter, write per flush cycle)

### Out of Scope

- CUDA acceleration (GPU target not decided — deferred to next milestone)
- External/prefix-based sorting (deferred — evaluate after I/O fix benchmark confirms sort is next bottleneck)
- Pre-convert nucleotides to integers once per sequence — deferred (low effort, but not the dominant bottleneck)
- Flatten 3D lookup tables (`nuc2aa[8][8][8]` → `nuc2aa_flat[512]`) — deferred
- SIMD batch translation — deferred (depends on pre-conversion, evaluate after CUDA decision)
- Dynamic split count scaling — deferred (query-time improvement, not build-time critical)
- Query-time (classification) performance at core_nt scale — not yet evaluated

## Context

### The Bottleneck

Each `AccessionBatch` is defined as (speciesID × FASTA file). At core_nt scale:
- 2,382 FASTA files, ~8,400 batches per file on average
- Each batch independently opens its file and **scans from byte 0** to find sequences by ordinal
- Effective I/O: 8,400 × 378 MB × 2,382 files = **~7.5 PB** for **900 GB** of actual data
- OS page cache rescues much of this (~22 days observed vs. 174 days theoretical), but 8,400 threads hitting the same file still causes severe cache pressure

A single sequential pass of all 900 GB at 500 MB/s takes ~30 minutes. The fix brings effective I/O back down to that baseline.

### Affected Code

| File | What changes |
|------|-------------|
| `src/commons/IndexCreator.h` | Add `vector<vector<uint64_t>> fastaOffsets` field, `buildFastaOffsetIndex()` declaration |
| `src/commons/IndexCreator.cpp` | Implement `buildFastaOffsetIndex()`, modify `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` inner loops |
| `src/workflow/build.cpp` | Insert `buildFastaOffsetIndex()` call between `getObservedAccessions()` and `getTaxonomyOfAccessions()` |

### Flush Cycle Reality

Earlier estimates of "10-15 flush cycles" assumed core_nt was 50-80 GB. Correct figure:
- 900 GB × 2.5 k-mers/nucleotide × 16 bytes/k-mer → ~2.25 trillion k-mers
- 128 GB RAM → ~8 billion k-mers per flush → **~280 flush cycles**
- After I/O fix: sort dominates (~7-10h across 280 cycles). External sort or CUDA radix sort is the next milestone.

### What Metabuli Is Not

Metabuli is not redundant with DIAMOND. DIAMOND operates purely in AA space for functional annotation. Metabuli's codon layer encodes synonymous variation that DIAMOND discards — enabling strain-level discrimination. This is the unique capability that justifies reference-level database support.

## Constraints

- **Language**: C++17 — no new language features beyond existing codebase standard
- **Build**: CMake 3.15+, OpenMP; no new build dependencies for Phase 1 (CUDA deferred)
- **Correctness**: Must produce classification-equivalent output to current implementation; regression suite required before merge
- **Compatibility**: Uncompressed FASTA only for random access path; gzip fallback to existing sequential reader
- **Cross-platform**: Linux (AVX2, SSE2, ARM64), macOS (Apple Silicon + Intel), Windows — cannot break any platform
- **Users**: Both internal Broad EMI use and open source community; correctness and documentation matter

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| `fseek()`-based random access, not mmap | Simpler, works within existing `FILE*` patterns in `extractKmerFromSixFrames()`; mmap adds complexity without clear benefit at this stage | — Pending |
| Fix both `extractKmerFromSixFrames()` AND `fillTargetKmerBuffer()` | Both have identical sequential scan patterns; fixing only one leaves the same bottleneck on a different code path | — Pending |
| Per-thread `seqBuf` vector replaces KSeq buffer + per-sequence `maskedSeq` | Two problems solved in one: eliminates KSeq dependency in inner loop AND removes per-sequence malloc | — Pending |
| Parallel offset index build across files, not across batches | Files are independent — embarrassingly parallel. Build time: ~minutes for 2,382 files at 500 MB/s with 32 threads | — Pending |
| Scope Phase 1 to I/O fix only, benchmark before committing to sort strategy | Sort dominance is predicted but unconfirmed; actual per-stage timing after fix determines whether external sort or CUDA radix sort is the better next investment | — Pending |

---
*Last updated: 2026-03-04 after initialization*
