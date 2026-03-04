# Architecture Research: FASTA Offset Index

**Domain:** FASTA random access indexing for large-scale k-mer pipeline
**Researched:** 2026-03-04
**Confidence:** HIGH (codebase analysis) / MEDIUM (FAI format comparisons)

---

## Recommended Architecture

### Data Structure: In-Memory `vector<vector<uint64_t>>`

```cpp
// IndexCreator.h
vector<vector<uint64_t>> fastaOffsets;  // [fileIdx][ordinal] = byte offset of '>'
```

**Memory cost at core_nt scale:**
- 2,382 files × ~8,400 avg sequences × 8 bytes = **~160 MB**
- Upper bound (if sequence count peaks at 20,000/file): **~380 MB**
- On a 128 GB build machine: 0.1-0.3% of RAM budget — entirely acceptable

**Why not on-disk persistence (.fao files):**
- Pre-pass cost: 2,382 files × 378 MB at 500 MB/s with 32 threads = **~57 seconds** — negligible vs. a 10-12 hour build
- Disk caching adds invalidation complexity: file modification timestamps, format versioning, path changes
- Defer on-disk caching to a future `updateDB` optimization where repeated partial builds justify it
- In-memory is the correct choice for Phase 1

### Pipeline Insertion Point

```
getObservedAccessions()        ← fastaPaths populated here
buildFastaOffsetIndex()        ← NEW: parallel scan of all files
getTaxonomyOfAccessions()
getAccessionBatches()
[flush loop → extractKmerFromSixFrames() and fillTargetKmerBuffer() use fastaOffsets]
```

---

## buildFastaOffsetIndex() Design

### Parallelization: One Thread Per File

Files are independent — the offset build is embarrassingly parallel across files. `schedule(dynamic, 1)` handles file size variance (some files 10 MB, some 2 GB — dynamic load balancing prevents thread starvation):

```cpp
void IndexCreator::buildFastaOffsetIndex() {
    fastaOffsets.resize(fastaPaths.size());

    #pragma omp parallel for schedule(dynamic, 1) default(none) \
        shared(fastaPaths, fastaOffsets)
    for (size_t i = 0; i < fastaPaths.size(); ++i) {
        // Skip gzip files — leave fastaOffsets[i] empty as sentinel for fallback
        if (fastaPaths[i].size() >= 3 &&
            fastaPaths[i].substr(fastaPaths[i].size() - 3) == ".gz") {
            continue;
        }

        FILE* fp = fopen(fastaPaths[i].c_str(), "rb");
        if (!fp) continue;  // warn, don't fail — validateDatabase will catch corrupt files

        vector<uint64_t>& offsets = fastaOffsets[i];
        offsets.reserve(8192);  // reasonable first estimate; grows as needed

        char linebuf[65536];
        uint64_t lineStart = (uint64_t)ftello(fp);
        while (fgets(linebuf, sizeof(linebuf), fp)) {
            if (linebuf[0] == '>') {
                offsets.push_back(lineStart);  // offset of '>' character
            }
            lineStart = (uint64_t)ftello(fp);
        }
        fclose(fp);
    }
}
```

**Critical details:**
- Open in `"rb"` (binary mode) — text mode CRLF→LF conversion on Windows makes `ftello` offsets inconsistent with physical bytes
- `ftello` on a buffered `FILE*` reads the internal position counter — no syscall, not a bottleneck
- Store offset of `>` (not first base) — allows existing KSeq-derived parsing to work after `fseeko`

---

## Modified Inner Loop: extractKmerFromSixFrames()

**Current code** (IndexCreator.cpp:953-994) — linear scan from byte 0:
```cpp
KSeqWrapper* kseq = KSeqFactory(fastaPaths[whichFasta].c_str());
size_t seqCnt = 0;
while (kseq->ReadEntry()) {
    if (seqCnt == accessionBatches[batchIdx].orders[idx]) {
        // process this sequence
    }
    seqCnt++;  // skip everything else — THIS IS THE BOTTLENECK
}
delete kseq;
```

**Proposed replacement** — random access via fseeko:
```cpp
// Gzip fallback: if no offsets built, use original sequential path
if (fastaOffsets[whichFasta].empty()) {
    // [existing KSeq sequential code here as fallback]
    return;
}

// Sort batch orders by file offset for forward-only seeks
// (getAccessionBatches groups by species, not by file position)
vector<size_t> sortedOrders = batch.orders;
sort(sortedOrders.begin(), sortedOrders.end(),
     [&](size_t a, size_t b) {
         return fastaOffsets[whichFasta][a] < fastaOffsets[whichFasta][b];
     });

FILE* fp = fopen(fastaPaths[whichFasta].c_str(), "rb");
vector<char> seqBuf;  // thread-local, reused across all sequences in batch

for (size_t ordinal : sortedOrders) {
    uint64_t offset = fastaOffsets[whichFasta][ordinal];
    fseeko(fp, (off_t)offset, SEEK_SET);

    // Read header line (skip '>')
    char headerBuf[4096];
    fgets(headerBuf, sizeof(headerBuf), fp);

    // Read sequence lines into seqBuf until next '>' or EOF
    seqBuf.clear();
    char linebuf[65536];
    uint64_t beforeLine = (uint64_t)ftello(fp);
    while (fgets(linebuf, sizeof(linebuf), fp)) {
        if (linebuf[0] == '>') break;  // next sequence starts
        size_t len = strlen(linebuf);
        while (len > 0 && (linebuf[len-1] == '\n' || linebuf[len-1] == '\r')) len--;
        seqBuf.insert(seqBuf.end(), linebuf, linebuf + len);
        beforeLine = (uint64_t)ftello(fp);
    }

    // Pass seqBuf.data() / seqBuf.size() to kmerExtractor
    // (replaces maskedSeq new/delete — seqBuf IS the per-thread buffer)
}
fclose(fp);
```

**The same pattern applies to `fillTargetKmerBuffer()`** — both functions have identical sequential scan structure.

---

## Sorting Batch Orders by File Offset

`getAccessionBatches()` groups sequences by species, not by their ordinal position within the FASTA. A single batch's `orders[]` vector may be non-monotonic — e.g., ordinals {5, 1, 8, 3} within a file. Processing them unsorted means interleaved backward seeks, which defeats OS read-ahead prefetching.

**Sort by offset before seeking:**
```cpp
// Sort orders ascending by byte offset — ensures forward-only sequential access
sort(orders.begin(), orders.end(),
     [&](size_t a, size_t b) {
         return fastaOffsets[fileIdx][a] < fastaOffsets[fileIdx][b];
     });
```

This turns random seeks into (mostly) sequential forward reads within each batch, allowing the OS to prefetch the next sequence's data during the seek.

---

## FILE* Lifecycle: Per-Batch Open/Close

**Why not per-file cached handles:**
Multiple threads may process different batches from the same file concurrently. A single cached `FILE*` per file would require a mutex, serializing concurrent access. Per-batch `fopen`/`fclose` pairs are correct — the OS page cache ensures the actual disk bytes are not re-read:

```
Thread 1: fopen fasta_001.fna → fseeko(offset_5) → fread → fclose
Thread 2: fopen fasta_001.fna → fseeko(offset_8) → fread → fclose
// Both threads read from OS page cache after first thread warms it
```

**If profiling shows fopen/fclose overhead is significant:** Implement per-thread handle caching keyed by `fileIdx` (Pattern 2 from STACK.md). Close all cached handles at end of the parallel region.

---

## Gzip Fallback

If `fastaPaths[i]` ends in `.gz`, leave `fastaOffsets[i]` empty (as a sentinel). The modified inner loop checks for empty before attempting `fseeko`:

```cpp
if (fastaOffsets[whichFasta].empty()) {
    // Fall back to existing KSeq sequential scan
    KSeqWrapper* kseq = KSeqFactory(fastaPaths[whichFasta].c_str());
    // ... existing code ...
    delete kseq;
    return;
}
```

Document limitation: gzip files do not support byte-offset random access without bgzip + `.gzi` index. Users must decompress FASTA files before building large databases.

---

## FAI Format Comparison

| Aspect | htslib FAI | Metabuli fastaOffsets |
|--------|-----------|----------------------|
| Offset target | First **base** character | `>` header character |
| Requires uniform line length | YES | NO |
| Enables sub-sequence access | YES (via LINEWIDTH math) | NO (whole-sequence only) |
| Format | On-disk tab-separated | In-memory `uint64_t` vector |
| Use case | Arbitrary coordinate queries | Whole-sequence extraction by ordinal |

Metabuli's design is correct for its use case — whole-sequence reads don't need FAI's LINEWIDTH trick, and not requiring uniform line lengths is important for NCBI FASTA files.

---

## Memory Layout Summary

```
fastaOffsets                        // vector<vector<uint64_t>>
├── [0] → {offset_0, offset_1, ..., offset_N0}    // fasta_001.fna (N0 sequences)
├── [1] → {offset_0, offset_1, ..., offset_N1}    // fasta_002.fna (N1 sequences)
...
└── [2381] → {offset_0, ..., offset_N2381}        // fasta_2382.fna

Total memory: sum(Ni) × 8 bytes ≈ 160-250 MB for core_nt
Build time: ~57s with 32 threads at 500 MB/s NVMe
```

---

## Component Boundaries

```
buildFastaOffsetIndex()
    reads: fastaPaths (populated by getObservedAccessions)
    writes: fastaOffsets (consumed by extractKmerFromSixFrames, fillTargetKmerBuffer)
    threading: OpenMP parallel for over files

extractKmerFromSixFrames() [modified]
    reads: fastaOffsets[whichFasta][ordinal]
    uses: fseeko → reads sequence → passes bytes to kmerExtractor
    threading: one thread per AccessionBatch; per-batch FILE* handles

fillTargetKmerBuffer() [modified]
    same pattern as extractKmerFromSixFrames
    different kmer extraction path (CDS-annotated vs. six-frame)
```

---

## Open Questions

- What is the maximum sequence count in any single core_nt FASTA file? Affects `offsets.reserve()` sizing — 8192 is a conservative estimate; a quick `grep -c '>' file.fna` on the largest file would give the exact number for better first-allocation.
- Should `buildFastaOffsetIndex()` warn (not fail) if a file has zero sequences? Could indicate corrupt input that would cause silent misclassification downstream.

---

*Architecture research for: Metabuli FASTA random access — Phase 1*
*Researched: 2026-03-04*
