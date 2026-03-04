# Codebase Concerns

**Analysis Date:** 2026-03-04

---

## Tech Debt

### 1. Redundant FASTA I/O at Database Build Time (Critical)

**Issue:** The dominant bottleneck causing 22-day build times for core_nt (~900 GB).

**Files:** `src/commons/IndexCreator.cpp:953-995`, `src/commons/IndexCreator.cpp:1014`

**Impact:** Database builds at large scale are impractical. The current implementation processes ~8,400 batches per FASTA file on average, with each batch independently opening the file and scanning from byte 0 to find its sequences by ordinal position.

```cpp
// Current pattern - reads same file thousands of times
while (kseq->ReadEntry()) {
    if (seqCnt == accessionBatches[batchIdx].orders[idx]) {
        // process sequence
    }
    seqCnt++;  // skip everything else
}
```

**Root Cause:**
- AccessionBatch defined as (speciesID × FASTA file) — each batch independently opens its file
- Linear sequential scan from byte 0 for every batch
- Measured effective I/O: 7.5 petabytes for 900 GB of data (174 days raw I/O, reduced to 22 days only by OS page cache)
- At core_nt scale: 2,382 FASTA files × 8,400 batches/file = ~20 million batches

**Fix Approach:** Implement FASTA random access indexing via pre-pass byte offset recording:
- Build `fastaOffsets[fileIdx][ordinal] = byte_offset` once per file
- Use `fseek()` to jump directly to needed sequences instead of scanning
- Expected outcome: 22 days → 10-12 hours

**Priority:** CRITICAL — This is the current work in `feat/fasta-random-access` branch.

---

### 2. Per-Sequence Memory Allocation During K-mer Extraction (Medium)

**Issue:** Frequent malloc/free calls causing heap churn at scale.

**Files:** `src/commons/IndexCreator.cpp:970` (masking path)

**Impact:** At core_nt scale with millions of sequences, per-sequence `new`/`delete` adds memory allocation overhead.

```cpp
maskedSeq = new char[e.sequence.l + 1];  // malloc per sequence
// ... use ...
delete[] maskedSeq;                       // free per sequence
```

**Fix Approach:** Reuse resizable buffer per thread instead of per-sequence allocation. This is naturally solved as part of the FASTA random access implementation with a per-thread `seqBuf` vector.

**Priority:** LOW (resolved alongside FASTA fix in Priority 1).

---

### 3. Excessive Sort Operations at Scale (High)

**Issue:** Becomes dominant bottleneck after I/O is fixed.

**Files:** `src/commons/IndexCreator.cpp:351-353`

**Impact:** At core_nt scale, ~280 flush cycles × ~60-90s per sort = ~7-10 hours of compute after I/O fix. Sort dominates the post-I/O time profile.

```cpp
SORT_PARALLEL(kmerBuffer.buffer,
              kmerBuffer.buffer + kmerBuffer.startIndexOfReserve,
              Kmer::compareTargetKmer);
```

**Measured at core_nt:** ~2.25 trillion k-mers generated, ~128 GB RAM per flush → ~280 flush cycles.

**Fix Approach (Priority Order):**
1. **CUDA radix sort (Priority 3):** 10-15x speedup via CUB `DeviceRadixSort` → ~45-60 min sort time
2. **External/prefix-based sorting (Priority 2):** Write k-mers to per-prefix temporary files based on upper bits, sort independently → reduces flush count significantly but requires architectural change

**Priority:** HIGH — After FASTA fix, this is the primary remaining bottleneck.

---

### 4. Fixed Split Count Regardless of Database Size (Medium)

**Issue:** `splitNum = 4096` hardcoded, too coarse for large databases.

**Files:** `src/workflow/build.cpp:20`

**Impact:** For core_nt (~500+ GB), each split averages ~100 MB — inefficient for query-time skip optimization and index granularity.

**Fix Approach:** Scale dynamically: `max(4096, dbSizeGB * 40)` to improve query-time skip optimization on large databases.

**Priority:** MEDIUM — Query-time concern, not build-time.

---

## Performance Bottlenecks

### 1. Six-Frame Translation Overhead (Medium)

**Issue:** Lookup-intensive operation causes CPU pipeline stalls.

**Files:** `src/commons/KmerExtractor.cpp:375-405`, `src/commons/KmerScanner.h:82-117`

**Problem:**
- Per codon: 3 `atcg[]` lookups (character-to-integer normalization) + 2 table lookups (`nuc2aa`, `nuc2num`)
- All 6 frames processed **sequentially** per sequence
- `atcg[]` redundancy: nucleotide position read by all frames (3N lookups for N nucleotides instead of N)
- 3D lookup table `nuc2aa[8][8][8]` causes cache misses (multi-pointer chase)

**Expected Gain:**
- Pre-convert nucleotides to integers once: ~20-35% speedup (Priority 5, effort: low)
- Flatten 3D lookup to 1D: ~5-10% speedup (Priority 7, effort: low)
- SIMD batch translation: ~4-8x speedup (Priority 9, effort: high, depends on Priority 5)
- CUDA kernel: 15-30x speedup (Priority 4, pairs with CUDA sort)

**Priority:** MEDIUM — After sort is fixed, translation becomes notable (~15% post-fix time). CUDA kernel (Priority 4) + CPU optimizations (Priority 5, 7) are both viable paths.

---

### 2. No CUDA Acceleration (High for Scale)

**Issue:** Metabuli's lookup-intensive operations are GPU-suitable but not implemented.

**Files:** Build pipeline spread across `IndexCreator`, `KmerExtractor`, etc.

**Opportunity:**
- Six-frame translation: Lookup tables tiny (2 KB each) → fit in GPU shared memory
- K-mer assembly: Embarrassingly parallel (one thread per position)
- Sorting: CUB `DeviceRadixSort` (10-15x speedup)
- Filter/compact: CUB `DeviceSelect` (5-10x speedup)

**Architecture Gap:**
```
Current:  Sequential CPU → All stages CPU-bound
Proposed: CPU reads FASTA → GPU kernels (translation, k-mer assembly, sort) → CPU writes
```

Expected end-to-end after FASTA fix + CUDA: ~2-3 hours for core_nt.

**Priority:** HIGH — But only after FASTA fix and sort analysis. Requires CUDA build system setup.

---

### 3. Linear AccessionBatch Processing (Medium)

**Issue:** Batches grouped by species cause load imbalance when some species dominate.

**Files:** `src/commons/IndexCreator.cpp` (batch generation and processing)

**Impact:** Species like *E. coli* with enormous representation cause single batches to span several GB, creating thread starvation in the batch processing loop.

**Fix Approach:** Dynamic work-stealing queue or finer-grained batching by sequence count rather than species.

**Priority:** MEDIUM — Improves parallelism efficiency but not a critical path blocker.

---

## Known Bugs & Edge Cases

### 1. Incomplete Error Handling in Batch Processing

**Issue:** Hard exit on invalid taxID but potentially incomplete error reporting.

**Files:** `src/commons/IndexCreator.cpp:958-963`

```cpp
if (accessionBatches[batchIdx].taxIDs[idx] == 0) {
    #pragma omp critical
    {
        accessionBatches[batchIdx].print();
        exit(1);  // Hard exit without cleanup
    }
}
```

**Risk:** Unclean exit may leave temporary files, incomplete databases, or corrupted state.

**Recommendation:** Replace hard `exit()` with proper exception handling or structured cleanup (return error code to outer scope, trigger destructor chains).

**Priority:** MEDIUM.

---

### 2. Potential Resource Leaks in Error Paths

**Issue:** `TaxonomyWrapper` and other heap allocations may not be freed on error.

**Files:** `src/workflow/build.cpp:89-102`

```cpp
TaxonomyWrapper * taxonomy =  new TaxonomyWrapper(...);
IndexCreator idxCre(par, taxonomy, 2);
idxCre.createIndex();  // May throw or exit; taxonomy not explicitly freed
```

**Risk:** Process termination on error may not allow proper cleanup.

**Recommendation:** Use RAII (unique_ptr) for heap allocations instead of raw `new`.

**Priority:** MEDIUM.

---

### 3. KSeq Wrapper Cleanup in Exception Paths

**Issue:** `KSeqWrapper` allocated with `KSeqFactory` but potentially not deleted if exception occurs.

**Files:** `src/commons/IndexCreator.cpp:953, 995` (and similar patterns in extraction)

**Risk:** File handles and buffers may leak if `kseq->ReadEntry()` encounters unexpected EOF or corruption.

**Recommendation:** Wrap in RAII resource guard or use try-finally equivalent.

**Priority:** LOW-MEDIUM (unlikely in practice but cleanup would improve robustness).

---

## Security Considerations

### 1. No Input Validation on Taxonomy Files

**Issue:** Taxonomy dump files (`names.dmp`, `nodes.dmp`, `merged.dmp`) read without integrity checks.

**Files:** `src/commons/TaxonomyWrapper.cpp`, `src/commons/NcbiTaxonomy.cpp`

**Risk:** Malformed or malicious taxonomy files could cause buffer overflows, infinite loops, or DoS.

**Recommendation:**
- Add schema validation for taxonomy files
- Bounds-check on IDs during taxonomy tree construction
- Maximum depth checks on recursive operations

**Priority:** MEDIUM.

---

### 2. FASTA Header Parsing

**Issue:** Accession extraction from FASTA headers relies on regex but no validation of extracted values.

**Files:** `src/commons/IndexCreator.cpp` (accession extraction logic)

**Risk:** Crafted headers could cause injection into accession-to-taxid mapping.

**Recommendation:** Whitelist allowed characters in accessions, validate against schema.

**Priority:** LOW (bioinformatics context, but good practice).

---

### 3. Database Integrity Not Verified at Load Time

**Issue:** No checksums or signatures on built databases.

**Files:** Query-time loaders in `src/commons/Classifier.cpp`, `src/commons/KmerMatcher.cpp`

**Risk:** Corrupted or modified databases loaded silently.

**Recommendation:** Add optional cryptographic hash verification of database files.

**Priority:** LOW (good hardening but not critical for primary use).

---

## Scaling Limits

### 1. 64-Bit Taxonomy ID Overflow Risk

**Issue:** `TaxID` (likely 32-bit or 64-bit depending on typedef) limits taxonomy size.

**Files:** `src/commons/common.h` (TaxID typedef), taxonomy structures throughout

**Risk:** At scale (GTDB R226: 143,614 species, NCBI: millions of genomes), taxonomy growth could hit limits.

**Current Limit:** Unsigned 32-bit TaxID = ~4 billion unique IDs (ample but not infinite).

**Recommendation:** Document TaxID limits. Consider 64-bit if taxonomy exceeds 2^32 entries.

**Priority:** LOW (current databases far below limit).

---

### 2. RAM-Based Index Flush Thresholds

**Issue:** Flush cycle count grows with database size; no adaptive buffering.

**Files:** `src/commons/IndexCreator.cpp:1002-1006`

**Measured:** core_nt scale = ~280 flush cycles. Larger databases (future reference sets) could push this further.

**Scaling Path:**
- Aggressive prefix-based sorting (Priority 2) reduces logical flush count
- CUDA reduces per-flush time dramatically
- Disk-based merging for very large buffers

**Priority:** MEDIUM (not urgent but necessary for future 1+ TB databases).

---

## Fragile Areas

### 1. KSeq Dependency for FASTA Parsing

**Files:** `src/commons/SeqIterator.cpp`, usage throughout IndexCreator

**Fragility:**
- KSeq is a C-style library (in `lib/mmseqs`)
- Error handling is minimal (returns NULL on failure)
- Integrating random access requires significant refactoring

**Safe Modification:**
- Implement wrapper class `RandomAccessFasta` with pre-built offsets
- Keep KSeq for sequential reading, use FILE*/fseek for random access
- Add test coverage for offset correctness (unit tests for offset index generation)

**Test Coverage:** No existing unit tests for FASTA offset indexing — high risk area for the in-progress `feat/fasta-random-access` implementation.

**Priority:** HIGH during FASTA implementation; ensure comprehensive testing.

---

### 2. Batch Assignment and Load Balancing

**Files:** `src/commons/IndexCreator.cpp` (batch generation and processing)

**Fragility:**
- AccessionBatch assignment by species is hardcoded
- No dynamic rebalancing if batch sizes are wildly unequal
- Thread pool waits for slowest batch (no work-stealing)

**Safe Modification:**
- Add profiling hooks to measure batch execution times
- Implement optional fine-grained batching by sequence count
- Use atomic counters to expose load imbalance

**Test Coverage:** No tests for batch distribution uniformity.

**Priority:** MEDIUM (affects scaling efficiency, not correctness).

---

### 3. Taxonomy Tree Traversal with Potential Cycles

**Files:** `src/commons/TaxonomyWrapper.cpp`, `src/commons/NcbiTaxonomy.cpp`

**Fragility:**
- Assumes taxonomy is a DAG (directed acyclic graph), but no cycle detection
- Malformed `merged.dmp` or `nodes.dmp` could create cycles
- LCA (lowest common ancestor) computation could infinite-loop

**Safe Modification:**
- Add cycle detection during taxonomy loading
- Cap recursion depth in LCA computation
- Validate parent-child relationships

**Test Coverage:** No explicit cycle detection tests.

**Priority:** MEDIUM (would require malicious taxonomy to trigger, but hardening is cheap).

---

## Test Coverage Gaps

### 1. No Integration Tests for FASTA Random Access Indexing

**Problem:** The in-progress `feat/fasta-random-access` feature is complex (byte-level file seeking, offset correctness) with no existing integration test suite.

**Files:** New code in `src/commons/IndexCreator.cpp` and supporting random access layer

**Risk:** Off-by-one errors, boundary conditions (empty files, single-sequence files, very large files) could corrupt database builds silently.

**Recommendation:**
- Create test fixture with synthetic FASTA files of various sizes (1 sequence, 1000 sequences, 100 MB file, etc.)
- Verify offset index accuracy by reading back sequences at random offsets
- Test with pathological cases: sequences with no newlines >4 GB, headers with special characters, etc.
- Compare database hashes before/after switch to random access

**Priority:** CRITICAL during implementation.

---

### 2. No Benchmarks for Translation Performance

**Problem:** Translation optimizations (§4.2, §4.3, §4.5) are proposed but unmeasured.

**Files:** `src/commons/KmerExtractor.cpp` (extractKmer_dna2aa), `src/commons/KmerScanner.h`

**Risk:** Optimizations could regress performance or introduce subtle bugs in lookup tables.

**Recommendation:**
- Microbenchmark translation rate (codons/second) for baseline and each optimization
- Validate correctness (checksums of translated sequences) after each change
- Use perf/VTune to confirm CPU cache behavior improvements

**Priority:** HIGH for Priority 5, 7, 9 optimizations.

---

### 3. No Unit Tests for Taxonomy LCA

**Problem:** LCA computation is critical path but no isolated tests.

**Files:** `src/commons/TaxonomyWrapper.cpp`, `src/commons/Taxonomer.cpp`

**Risk:** Incorrect LCA could propagate silently through classification results.

**Recommendation:**
- Create taxonomy fixtures with known LCA relationships
- Test edge cases: identical species, different kingdoms, extinct taxa
- Compare output against naive O(n²) reference implementation

**Priority:** MEDIUM.

---

## Open Technical Decisions

### 1. CUDA Adoption Path (Unresolved)

**Question:** Is CUDA acceleration planned? Which GPU target (A100, consumer RTX, multi-GPU)?

**Impact:** Determines priority sequence (FASTA → sort optimization vs. FASTA → CUDA sort). Double-buffering strategy depends on GPU memory size.

**Files Affected:** Build system (CMakeLists.txt), kernel development (new .cu files)

**Status:** Not decided. SCALING_ANALYSIS.md documents CUDA feasibility but no implementation plan yet.

---

### 2. Maximum Database Size Target (Unresolved)

**Question:** Is core_nt (~900 GB) the ceiling, or should Metabuli scale to nt/nr (several TB)?

**Impact:** Changes flush cycle strategy (Priority 2: external sorting becomes more important) and memory allocation assumptions.

**Status:** Not documented. Feature branch assumes core_nt is the target.

---

### 3. Compression Support for FASTA (Unresolved)

**Question:** Should random access indexing support gzip-compressed FASTA?

**Impact:** Requires bgzip (seekable gzip) with .gzi index, complicates file handling.

**Current:** FASTA files assumed uncompressed; gzip support mentioned but not implemented in random access path.

**Status:** Not decided. Blocking decision for `feat/fasta-random-access`.

---

## Dependency Risks

### 1. MMseqs2 Submodule (Critical Dependency)

**Risk:** Metabuli depends on `lib/mmseqs` submodule. Upstream changes could break compatibility.

**Files:** `CMakeLists.txt:17`, all downstream code using MMseqs classes

**Mitigation:** Submodule pinned to specific commit. Regular testing against upstream changes recommended.

**Priority:** LOW (submodule pattern is stable) but document in maintenance runbook.

---

### 2. Prodigal Gene Prediction (Optional but Heavy)

**Risk:** Gene prediction path (`src/commons/ProdigalWrapper.cpp`) uses heap allocation pattern that could fail at scale.

**Files:** `src/commons/ProdigalWrapper.cpp:17-51` (malloc for ~56 MB buffers per instance)

**Issue:** If masking is enabled and Prodigal path is used, `ProdigalWrapper` + `IndexCreator` memory could exceed RAM budget.

**Mitigation:** Document mutual exclusivity of masking + Prodigal at scale, or implement shared buffer pool.

**Priority:** MEDIUM (CDS-info path is optimization, so failure is degradation not showstopper).

---

## Summary Table

| Concern | Type | Impact | Effort to Fix | Priority |
|---------|------|--------|---------------|----------|
| Redundant FASTA I/O | Tech Debt | Critical (22 days → 10-12h) | Medium | **CRITICAL** |
| Sort Dominance | Tech Debt | High (7-10h after I/O fix) | High | **HIGH** (after FASTA) |
| Per-Seq Memory Alloc | Tech Debt | Low | Low | Medium |
| Fixed Split Count | Tech Debt | Medium | Low | Medium |
| Translation Overhead | Performance | Medium | Low-High | Medium |
| No CUDA | Performance | High (2-3h with CUDA) | High | High (after FASTA + sort) |
| Batch Load Imbalance | Performance | Medium | Medium | Medium |
| Hard Exit Errors | Bug | Medium | Low | Medium |
| Resource Leaks | Bug | Medium | Low | Medium |
| Taxonomy Input Validation | Security | Medium | Low | Medium |
| Test Gaps (Random Access) | Testing | High Risk | Medium | **CRITICAL** (during impl) |
| Unresolved CUDA Path | Decision | High Impact | — | Blocker |

---

*Concerns audit: 2026-03-04*
