# Metabuli Scaling Analysis: core_nt / nt / nr Level Databases

**Date:** 2026-03-04
**Status:** Active Development — feat/fasta-random-access
**Goal:** Evaluate enhancements to scale Metabuli for reference-level databases (core_nt, nt, nr)
**Primary Target:** core_nt (~900 GB uncompressed, ~20M batches, 2382 FASTA files)
**Baseline Build Time:** ~22 days (current implementation, core_nt)
**Build Time Target:** Hours (sub-12h)

---

## 1. Metabuli Architecture Overview

Metabuli is a metagenomic taxonomic classifier that uses a novel "metamer" k-mer structure combining amino acid (AA) and DNA information in a single 64-bit key:

```
Bits 63-24:  8 amino acids × 5 bits = 40 bits  (protein-level, sensitivity)
Bits 23-0:   8 codons × 3 bits      = 24 bits  (DNA-level, specificity)
```

This dual-layer encoding is the core innovation — it provides protein-level sensitivity for detecting homology while using synonymous codon variation for species/strain-level discrimination.

### Key Pipeline Stages (Database Build)

```
Read FASTA → Six-Frame Translation → Metamer Assembly → Sort → Filter/LCA → Write Index
                 ↑                       ↑                 ↑
           (bottleneck #2)         (bottleneck #3)   (bottleneck #1)
```

### Key Source Files

| File | Role |
|------|------|
| `src/commons/KmerScanner.h` | Core translation + k-mer scanning (MetamerScanner, KmerScanner_dna2aa) |
| `src/commons/SyncmerScanner.h` | Syncmer-based scanning (50% DB reduction, 2x speed) |
| `src/commons/KmerExtractor.cpp` | Six-frame k-mer extraction, threading, buffer management |
| `src/commons/IndexCreator.h/cpp` | Database build pipeline, sort, filter, merge, flush logic |
| `src/commons/KmerMatcher.h/cpp` | Query-time k-mer matching, Hamming distance scoring |
| `src/commons/Taxonomer.cpp` | Taxonomic assignment from matches |
| `src/commons/Match.h` | Match structure with AA + DNA Hamming scoring |
| `src/commons/Kmer.h` | Kmer struct (16 bytes: 8-byte value + 8-byte union) |
| `src/commons/GeneticCode.h` | Codon translation tables (3D lookup: nuc2aa[8][8][8]) |
| `src/commons/common.h` | Buffer<T>, BlockingQueue, utility structures |
| `src/workflow/build.cpp` | Database build workflow entry point |
| `src/workflow/classify.cpp` | Classification workflow entry point |

---

## 2. Metabuli vs. DIAMOND: Why Metabuli Is Not Redundant

Both tools operate in amino acid space, but they answer fundamentally different questions and produce different outputs.

### What DIAMOND Does
- Translates query DNA → AA, then aligns against a **protein database** (nr)
- Output: per-read protein alignments with percent identity
- Operates **purely** in amino acid space — no DNA-level information retained
- Best for: functional annotation ("what proteins are present?")

### What Metabuli Does — The Dual-Layer Trick
- Translates query DNA → metamers encoding **both** AA identity and codon usage
- Matching happens in two stages:
  1. **AA match (sensitivity):** Upper 40 bits compared — finds hits even with synonymous DNA divergence
  2. **DNA Hamming distance (specificity):** Lower 24 bits compared via `getHammingDistanceSum()` — distinguishes organisms sharing the same proteins

### The Codon-Layer Scoring (Match.h:32-44)

```cpp
float getScore() const {
    int currentHamming = GET_2_BITS(rightEndHamming >> (cnt * 2));
    if (currentHamming == 0)
        score += 3.0f;      // exact codon match → high confidence (same species)
    else
        score += 2.0f - 0.5f * currentHamming;  // synonymous mutation → lower
}
```

- Exact codon match scores **3.0** (strong species-level evidence)
- Synonymous mutation scores **1.0-1.5** (same protein, different organism)
- This gradient is what enables strain-level discrimination

### Practical Discrimination Differences

| Scenario | DIAMOND | Metabuli |
|----------|---------|----------|
| Two E. coli strains sharing a gene | Same AA hit, cannot distinguish | Different codon usage → strain resolved |
| Horizontal gene transfer | Same protein → same hit | Codon bias reveals host species |
| Closely related species (Salmonella/E. coli) | Often identical protein hits | Synonymous codon patterns separate them |
| Distant homology (phylum level) | Alignment-based, sensitive | AA k-mer match (no alignment, faster) |
| **Output type** | Per-read protein alignments | Per-read taxonomic classification |

### Bottom Line

- **DIAMOND + nt/nr:** "What proteins are in my sample?" (functional)
- **Metabuli + core_nt:** "What organisms are in my sample, at what resolution?" (taxonomic with strain-level discrimination)

The codon layer in Metabuli exploits information that DIAMOND discards entirely. For nucleotide reference databases, this is a unique capability.

---

## 3. Identified Bottlenecks for core_nt Scale

### 3.1 Redundant FASTA I/O (Dominant Bottleneck — ~22 days)

**Location:** `IndexCreator::extractKmerFromSixFrames()` (IndexCreator.cpp:953-994)

Each `AccessionBatch` is defined as (speciesID × FASTA file) — all sequences for one species within one file form a batch. Each batch independently opens its FASTA file and **linearly scans from byte 0** to find its sequences by ordinal position:

```cpp
while (kseq->ReadEntry()) {
    if (seqCnt == accessionBatches[batchIdx].orders[idx]) {
        // process this one
    }
    seqCnt++;  // skip everything else
}
```

**Measured at core_nt scale:**

```
2,382 FASTA files
~900 GB total → ~378 MB average per file
~20 million batches / 2,382 files → ~8,400 batches per file on average

Effective I/O per file: 8,400 × 378 MB = ~3.1 TB
Total effective I/O:    3.1 TB × 2,382 files = ~7.5 petabytes

At 500 MB/s NVMe:  174 days raw I/O (OS page cache reduces to ~22 days observed)
Single sequential read of all 900 GB: ~30 minutes
```

The OS page cache rescues repeated reads of the same ~378 MB files, but 8,400 threads each opening the same file still causes enormous cache pressure. The fix collapses effective I/O from 7.5 PB back to 900 GB.

### 3.2 Six-Frame Translation Overhead

**Location:** `KmerExtractor::extractKmer_dna2aa()` (KmerExtractor.cpp:375-405) calling `MetamerScanner::next()` (KmerScanner.h:82-117)

Per codon, per frame:
- 3 `atcg[]` character mapping lookups (one per nucleotide)
- 1 call to `getAA()` → 3D table lookup `nuc2aa[x][y][z]`
- 1 call to `getCodon()` → 3D table lookup `nuc2num[x][y][z]`
- = **6 dependent memory lookups per codon** (forward), **9 for reverse** (adds `iRCT[]`)
- All 6 frames processed **sequentially** per sequence

**The `atcg[]` redundancy:** each nucleotide position is read by all frames that include it in a codon. For 3 forward frames this means 3N `atcg[]` lookups for N nucleotides. Pre-converting the raw sequence to an integer array once (N lookups) before the frame loop eliminates this redundancy. Note: this does **not** reduce the `nuc2aa`/`nuc2num` codon lookups — those are genuinely different per frame since each frame groups nucleotides differently. The savings are on the character-to-integer normalization step only (~20-35% translation speedup, not 2x).

### 3.3 Sort Dominance

**Location:** `IndexCreator::createIndex()` (IndexCreator.cpp:351-353)

```cpp
SORT_PARALLEL(kmerBuffer.buffer,
              kmerBuffer.buffer + kmerBuffer.startIndexOfReserve,
              Kmer::compareTargetKmer);
```

Sorts hundreds of millions to billions of 16-byte `Kmer` structs. Each flush cycle repeats a full sort. After fixing the I/O bottleneck (§3.1), this becomes the dominant remaining cost.

### 3.4 Flush Cycle Overhead

**Corrected estimate for core_nt at 900 GB:**

```
900 GB × 2.5 k-mers/nucleotide (IndexCreator.cpp:964) = ~2.25 trillion k-mers
128 GB RAM @ 16 bytes/k-mer → ~8 billion k-mers per flush
2.25T / 8B = ~280 flush cycles

Per flush:  sort ~60-90s + filter ~20-30s + write ~20-30s ≈ 120s
280 cycles × 120s = ~9-10 hours of compute after I/O is fixed
```

Note: earlier estimates of "10-15 flush cycles" were based on an incorrect core_nt size assumption of 50-80 GB. The correct figure is ~280 cycles at 900 GB.

### 3.5 Fixed Split Count

`splitNum = 4096` regardless of database size. For core_nt (~500+ GB), each split averages ~100 MB — too coarse for efficient query-time skip optimization.

### 3.6 Per-Sequence Memory Allocation

**Location:** `extractKmerFromSixFrames()` (IndexCreator.cpp:968-975)

```cpp
maskedSeq = new char[e.sequence.l + 1];  // malloc per sequence
// ... use ...
delete[] maskedSeq;                       // free per sequence
```

At core_nt scale (millions of sequences across 20M batches), this causes significant heap churn. The fix (one resizable buffer per thread) is a natural part of the FASTA random access implementation — the per-thread `seqBuf` vector replaces both KSeq's internal buffer and the per-sequence `maskedSeq` allocation.

### 3.7 AccessionBatch Load Imbalance

Batches are grouped by species. For core_nt, some species (e.g., E. coli) have enormous representation — a single batch can be several GB, causing thread starvation.

---

## 4. Proposed Enhancements

### 4.1 FASTA Random Access Indexing

**Impact: Critical | Effort: Medium | Status: In Progress (feat/fasta-random-access)**

**The problem:** Each of the ~20M batches opens its FASTA file and scans from byte 0. With ~8,400 batches per file on average, each file is effectively read 8,400× — producing ~7.5 PB of effective I/O for 900 GB of data.

**The fix:** One pre-pass over each FASTA file records the byte offset of every `>` header. Stored as `fastaOffsets[fileIdx][ordinal] = byte_offset`. Batches then `fseek()` directly to each needed sequence. Requires uncompressed FASTA (gzip files would need bgzip+.gzi index for random access).

**Implementation design:**

```
IndexCreator.h:
  vector<vector<uint64_t>> fastaOffsets;  // [fileIdx][ordinal] = byte offset
  void buildFastaOffsetIndex();

Pipeline insertion point:
  getObservedAccessions()       ← fastaPaths populated here
  buildFastaOffsetIndex()       ← NEW: one parallel scan across all 2382 files
  getTaxonomyOfAccessions()
  getAccessionBatches()
  [flush loop → extractKmerFromSixFrames() uses fastaOffsets]
```

**Index build cost:** ~2382 files × 378 MB = 900 GB scanned once, parallelized across files.
At 500 MB/s with 32 threads: ~minutes.

**Modified inner loop** replaces `KSeqFactory` + sequential scan (IndexCreator.cpp:953-995) with:
```cpp
FILE* fp = fopen(fastaPaths[fileIdx].c_str(), "r");
vector<char> seqBuf;  // reused across all sequences in this batch (solves §3.6)
for (size_t idx = 0; idx < batch.orders.size(); idx++) {
    fseek(fp, fastaOffsets[fileIdx][batch.orders[idx]], SEEK_SET);
    // lightweight single-entry reader: skip header, read sequence lines
}
fclose(fp);
```

**Note:** `fillTargetKmerBuffer()` (IndexCreator.cpp:1014) has the same linear scan pattern and requires the same fix.

**Expected outcome:** ~22 days → ~10-12 hours (I/O component: 174 days → 30 minutes).

### 4.2 Pre-Convert Nucleotides to Integers Once Per Sequence

**Impact: Medium | Effort: Low**

**Clarification on what this optimization actually does:** The six reading frames (0, 1, 2 on forward strand; 3, 4, 5 on reverse complement) cannot share codon translations — each frame groups nucleotides differently, producing genuinely different codons. What *can* be shared is the `atcg[]` character normalization step.

Currently `atcg[seq[i]]` is called 3N times for 3 forward frames (each nucleotide is accessed once per frame that includes it). Pre-converting to an `int8_t` array does this N times once, then all 6 frames read integers instead of raw characters. The `nuc2aa`/`nuc2num` lookups are unchanged.

Saves: 3N → N `atcg[]` lookups for forward, similarly for reverse. ~20-35% translation speedup, not 2x. True 2x requires combining with SIMD (§4.5).

### 4.3 Flatten 3D Lookup Table

**Impact: Medium | Effort: Low**

Replace `nuc2aa[8][8][8]` with `nuc2aa_flat[512]`:
```cpp
// Current: 3 pointer-chase cache accesses
nuc2aa[nuc2int(nuc1)][nuc2int(nuc2)][nuc2int(nuc3)]
// Proposed: 1 cache line access
nuc2aa_flat[(nuc2int(nuc1) << 6) | (nuc2int(nuc2) << 3) | nuc2int(nuc3)]
```

### 4.4 Reuse Masking Buffers Per Thread

**Impact: Low (but easy) | Effort: Low**

Allocate one `maskedSeq` buffer per thread, resize only when needed. Eliminates per-sequence malloc/free. Naturally implemented as part of §4.1 — the per-batch `seqBuf` vector in the random access reader replaces both KSeq's internal buffer and the per-sequence allocation.

### 4.5 SIMD Batch Translation

**Impact: High | Effort: High**

With AVX2/NEON, translate 8-16 codons simultaneously using shuffle-based lookups. Process ~48 nucleotides per SIMD instruction vs. 3 currently. Depends on §4.2 (pre-converted integer array) as a prerequisite.

### 4.6 Dynamic Split Count

**Impact: Medium (query time) | Effort: Low**

Scale `splitNum` with database size: `max(4096, dbSizeGB * 40)`. Better query-time skip granularity for large databases.

### 4.7 External/Prefix-Based Sorting

**Impact: High | Effort: High**

Write k-mers to per-prefix temporary files based on the upper bits of the value, then sort each prefix file independently. At core_nt scale with ~280 flush cycles, this becomes important after the I/O fix — it is the primary path to reducing compute from ~10h to ~2-3h. Previously deprioritized under the incorrect assumption of 10-15 flush cycles.

---

## 5. CUDA Acceleration Analysis

### 5.1 Why CUDA Helps Metabuli More Than DNA-Only Tools

For DNA-only k-mer tools, extraction is trivial (bit-shifts). The bottleneck is sorting — CUDA helps but modestly.

For Metabuli, the six-frame translation is a **lookup-intensive, massively parallel operation** that CPUs handle poorly (branch-heavy, latency-bound) but GPUs handle well:

- Lookup tables are tiny: `nuc2aa` (2 KB), `nuc2num` (2 KB), `atcg` (256 B), `iRCT` (256 B) — all fit in GPU shared memory with L1-speed access
- Each codon translates independently — embarrassingly parallel
- 6 frames can process simultaneously (vs. sequential on CPU)
- `getAA()` and `getCodon()` can be fused into a single lookup

### 5.2 GPU-Suitable Stages

| Stage | GPU Suitability | Approach | Expected Speedup |
|-------|----------------|----------|-----------------|
| Codon translation | Excellent | Custom kernel, tables in shared memory | 15-30x |
| K-mer assembly | Good | One thread per valid position | 10-20x |
| Sorting | Excellent | CUB `DeviceRadixSort` (drop-in) | 10-15x |
| Filter/compact | Good | CUB `DeviceSelect::Flagged` | 5-10x |
| LCA computation | Medium | Flattened taxonomy tree on GPU | 3-5x |
| FASTA parsing | Poor | Stays on CPU | 1x |
| Disk I/O | N/A | Stays on CPU | 1x |

### 5.3 Proposed CUDA Architecture

```
CPU Thread Pool           PCIe Bus               GPU
─────────────            ─────────              ───────
Read FASTA chunks  ──→  DMA transfer  ──→  Kernel 1: Bulk codon translation
(double-buffered)                           Kernel 2: K-mer assembly
                                            Kernel 3: Radix sort (CUB)
                                            Kernel 4: Filter + compact
                          ←── DMA ←──────  Transfer sorted/filtered buffer
Write to index  ←──────
```

**Double-buffering:** While GPU processes batch N, CPU reads batch N+1. PCIe 4.0 x16 = ~25 GB/s, easily saturates the pipeline.

**GPU memory:** A100 80 GB HBM can hold ~5 billion k-mers (16 bytes each) — enough for a significant chunk without flushing.

### 5.4 Kernel Design

**Kernel 1 — Bulk Codon Translation:**
```
Input:  char* sequences (concatenated), uint32_t* offsets/lengths
Output: int8_t* aminoAcids_fwd, int8_t* aminoAcids_rc
- One thread per codon position
- __shared__ int nuc2aa_flat[512]  (loaded once per block)
- __shared__ char atcg[256], iRCT[256]
- Each thread: read 3 nucleotides → single lookup → write 1 amino acid
```

**Kernel 2 — K-mer Assembly:**
```
Input:  int8_t* aminoAcids, valid-window bitmap
Output: Kmer* buffer (value + taxID + speciesID)
- One thread per valid k-mer position per frame
- Shift-and-OR 8 AA into upper 40 bits + 8 codons into lower 24 bits
- Use prefix-sum for output compaction (skip windows with N's)
```

### 5.5 Implementation Complexity

| Component | CUDA Difficulty | Libraries |
|-----------|----------------|-----------|
| Codon translation kernel | Easy | Custom, ~100 lines |
| K-mer assembly kernel | Medium | Custom, ~200 lines |
| Radix sort | Easy | CUB `DeviceRadixSort` (drop-in) |
| Stream compaction | Easy | CUB `DeviceSelect` |
| LCA on GPU | Medium | Custom, flattened tree |
| Double-buffer pipeline | Medium | CUDA streams + pinned memory |
| Build system | Low | CMake `enable_language(CUDA)` |

### 5.6 Estimated Speedups for core_nt

core_nt = ~900 GB of uncompressed sequence data (2,382 FASTA files, ~20M batches).
Baseline: ~22 days.

**After FASTA random access fix only:**

| Stage | Current | After Fix |
|-------|---------|-----------|
| FASTA I/O (redundant scans) | ~20+ days | ~30 min |
| Sort (280 flush cycles × ~60-90s) | — | ~7-10 h |
| Translation + extraction | — | ~1-2 h |
| **Total** | **~22 days** | **~10-12 h** |

**After FASTA fix + CUDA sort + CUDA translation:**

| Stage | % of post-fix time | CUDA speedup | New time |
|-------|-------------------|-------------|----------|
| Sort | ~70% | 10-15x | ~45-60 min |
| Translation + assembly | ~15% | 15-30x | ~5-10 min |
| I/O (FASTA + disk write) | ~15% | 1x | ~90 min |
| **End-to-end** | | | **~2-3 h** |

---

## 6. Priority Roadmap

| Priority | Enhancement | Impact | Effort | Dependencies |
|----------|------------|--------|--------|-------------|
| 1 | FASTA random access indexing | Critical — eliminates ~20 days of I/O | Medium | None |
| 2 | External/prefix-based sorting | High — reduces 280 flush cycles | High | Architectural change |
| 3 | CUDA: CUB radix sort | High — 10-15x sort speedup | Medium | CUDA build setup |
| 4 | CUDA: translation kernel | High — 15-30x translation speedup | Medium | Priority 3 |
| 5 | Pre-convert nucleotides to integers once | Medium — ~20-35% translation gain | Low | None |
| 6 | Reuse masking buffers per thread | Low (part of Priority 1 impl) | Low | None |
| 7 | Flatten 3D lookup table to 1D | Medium — better cache behavior | Low | None |
| 8 | Dynamic split count | Medium — better query perf on large DBs | Low | None |
| 9 | SIMD batch translation (CPU fallback) | High — 4-8x translation on CPU | High | Priority 5 |

### Recommended Path to Sub-12h Build

**Step 1 — FASTA random access (Priority 1):** Self-contained change, no hot-path risk. Expected outcome: 22 days → ~10-12 hours. This is the current work in `feat/fasta-random-access`.

**Step 2 — Instrument the build:** With I/O fixed, get a real timing breakdown (extraction vs. sort vs. filter vs. write per flush cycle). Confirms whether Priority 2 or Priority 3 is the better next investment.

**Step 3 — CUDA or external sort:** If sort dominates (expected), CUDA radix sort (Priority 3) is lower effort than external sorting (Priority 2) and gets to ~2-3h. External sorting reduces flush count and pairs well with CUDA for the full win.

---

## 7. Open Questions

- [ ] Actual per-stage timing breakdown from core_nt build after FASTA fix — **pending Phase 4 cloud run** (see Section 8)
- [ ] Target hardware for CUDA (A100? V100? Consumer GPU?)
- [ ] Whether Prodigal (gene prediction) path is used for core_nt or only the six-frame path
- [ ] Whether query-time (classification) performance is also a concern at this scale

**Answered:**
- [x] core_nt file size: ~900 GB uncompressed sequence data
- [x] core_nt structure: 2,382 FASTA files, ~20M batches, ~8,400 batches/file average
- [x] FASTA files are uncompressed — `fseek()` random access is directly applicable
- [x] Acceptable build time target: hours (sub-12h initially, sub-4h with CUDA)
- [x] Flush cycle count at core_nt scale: ~280 (not 10-15 as initially estimated)
- [x] Root cause of 22-day build time: redundant FASTA I/O (~7.5 PB effective reads for 900 GB of data)

---

## 8. Benchmark Results

**Status:** Pending cloud run

**Run date:** TBD
**Instance:** AWS r7i.32xlarge (128 vCPUs, 1024 GB RAM, EBS gp3)
**Configuration:** core_nt, 2,382 FASTA files, ~900 GB
**Metabuli commit:** TBD (run `git rev-parse HEAD` before starting)
**Metabuli branch:** feat/fasta-random-access
**Benchmark script:** `./scripts/benchmark_core_nt.sh`

---

### 8.1 Stage Timings — Single Flush Run (--threads 100 --max-ram 1000)

| Stage | Predicted (Section 5.6) | Actual |
|-------|-------------------------|--------|
| Offset pre-pass | ~30 min | — |
| K-mer extraction | ~1–2 h | — |
| Sort (1 flush) | ~60–90 s | — |
| Filter (1 flush) | ~20–30 s | — |
| Write (1 flush) | ~20–30 s | — |
| **Total** | **~10–12 h** | **—** |

*Fill actual column from `benchmark_ram1000.log`. Convert seconds to hours for Total row.*

---

### 8.2 Per-Flush-Cycle Summary — Multi-Flush Run (--threads 100 --max-ram 128, ~280 cycles)

| Stage | Min (s) | Max (s) | Avg (s) |
|-------|---------|---------|---------|
| K-mer extraction | — | — | — |
| Sort k-mers | — | — | — |
| Filter k-mers | — | — | — |
| Write k-mers | — | — | — |

*Fill from: `awk -f scripts/parse_bench_log.awk benchmark_ram128.log`*

---

### 8.3 Before / After Comparison

| Metric | Before (estimated) | After (measured) |
|--------|-------------------|-----------------|
| Total build time | ~22 days | — |
| Primary I/O cost | ~20+ days (7.5 PB effective reads) | — |
| Offset pre-pass cost | N/A | — |
| Sort cost (per flush × cycles) | ~7–10 h estimated | — |
| Translation + extraction | ~1–2 h estimated | — |
| **Next bottleneck** | Sort (predicted) | — |

*After filling: state the measured next bottleneck based on per-stage breakdown.*

---

### 8.4 Reproduction

```bash
# Build the binary
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build --target metabuli -j$(nproc)

# Single-flush run (clean baseline)
./scripts/benchmark_core_nt.sh ./build/metabuli /data/db_1000 /data/fasta.list /data/acc2taxid.tsv /data/taxonomy 1000 100

# Multi-flush run (per-cycle variance)
./scripts/benchmark_core_nt.sh ./build/metabuli /data/db_128  /data/fasta.list /data/acc2taxid.tsv /data/taxonomy 128 100

# Parse per-cycle stats from multi-flush log
awk -f scripts/parse_bench_log.awk /data/db_128/benchmark_ram128.log
```
