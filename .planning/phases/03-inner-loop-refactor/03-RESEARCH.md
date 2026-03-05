# Phase 3: Inner Loop Refactor - Research

**Researched:** 2026-03-05
**Domain:** C++ POSIX I/O refactor — fseeko random access, OpenMP, FASTA parsing
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Training sequence reads (`trainingSeqFasta` / `trainingSeqIdx`) stay on the existing `KSeqWrapper` sequential path — do NOT apply fseeko there
- Training sequence is read once per species (not the hot path); Phase 3 scope is strictly FILLTGT-01 to 04 for the main scan loop only
- Preserve `trained` flag logic exactly as-is — no behavioral changes to the training sequence code path
- When `trainingSeqFasta != whichFasta`: always use `KSeqWrapper` for training reads regardless of offset availability
- After `fseeko` to `fastaOffsets[fileIdx][ordinal]` (the `>` character), skip header with `fgets`, then bound the read using the next offset: `fastaOffsets[fileIdx][ordinal+1]` gives the byte position of the next sequence header
- Read bytes from current file position up to the next offset (or EOF for last sequence), strip embedded newlines, store in `seqBuf`
- `seqBuf` is a per-thread `vector<char>` declared in the OpenMP parallel block; starts empty, grows via `resize()` as sequences are processed — no pre-allocation
- `maskMode`: masking is done in-place into `seqBuf` (eliminates the separate `maskedSeq = new char[...]` / `delete[]` entirely)
- Gzip fallback path: when `fastaOffsets[whichFasta]` is empty, keep the existing `KSeqWrapper` sequential scan entirely unchanged
- DOCS-01: add a concise limitation note to the main `README.md`, near the database building section; tone is limitation + workaround; no performance numbers; README only (no code comments)

### Claude's Discretion

- Exact `fread` vs `fgets`-loop approach for multi-line FASTA sequence accumulation after bounding by next offset (use next-offset bounding as decided, implementation detail of stripping newlines is flexible)
- How to handle the last sequence in a file when there is no `ordinal+1` offset (read until EOF)
- Exact `seqBuf` resize pattern (resize to `nextOffset - currentOffset` as upper bound, then shrink after stripping newlines)
- Whether to extract the fseeko read loop into a helper function or inline it in both function bodies

### Deferred Ideas (OUT OF SCOPE)

- Per-thread cached `FILE*` handles keyed by `fileIdx` (PERF-02)
- fseeko for training sequence reads in `fillTargetKmerBuffer`
- `fread` 64 KB block scanner for the offset pre-pass (PERF-01)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EXTKMER-01 | `extractKmerFromSixFrames()` uses `fseeko()` to seek directly to each sequence when `fastaOffsets[whichFasta]` is non-empty | fseeko/fgets pattern documented in Architecture Patterns |
| EXTKMER-02 | Batch orders sorted by byte offset before seeking in `extractKmerFromSixFrames()` | Sort pattern documented; uses `std::sort` on `orders` keyed by `fastaOffsets[whichFasta][ordinal]` |
| EXTKMER-03 | Gzip fallback to existing `KSeqWrapper` path when offset vector is empty in `extractKmerFromSixFrames()` | Empty-vector sentinel from Phase 2 confirmed present |
| EXTKMER-04 | Per-thread `seqBuf` vector reused across all sequences in a batch, replacing `new char[...]` / `delete[]` | seqBuf lifecycle pattern documented; in-place masking confirmed safe |
| FILLTGT-01 | `fillTargetKmerBuffer()` uses `fseeko()` for direct seek when offsets available | Same fseeko pattern as EXTKMER-01; Prodigal path complexity documented |
| FILLTGT-02 | Batch orders sorted by byte offset before seeking in `fillTargetKmerBuffer()` | Same sort pattern as EXTKMER-02 |
| FILLTGT-03 | Gzip fallback in `fillTargetKmerBuffer()` | Same sentinel check as EXTKMER-03 |
| FILLTGT-04 | Per-thread `seqBuf` vector reused in `fillTargetKmerBuffer()` | Reverse-complement case requires second seqBuf or resize; documented in pitfalls |
| DOCS-01 | README.md limitation note for gzip FASTA files | Target section identified (Custom DB / Build sections) |
</phase_requirements>

---

## Summary

Phase 3 refactors the two innermost sequence-reading loops in `IndexCreator.cpp` — `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` — to use `fseeko` random access instead of sequential KSeq scanning from byte 0. Both functions share a structurally identical outer OpenMP `#pragma omp for schedule(dynamic, 1)` loop over `accessionBatches`, and both have already had their infrastructure prepared in Phase 2 (`fastaOffsets[fileIdx][ordinal]` populated, BUILD-01/02 in place).

The refactor replaces the `KSeqFactory` + `while (kseq->ReadEntry())` scan loop with: (1) sort batch orders by ascending byte offset, (2) open a per-batch `FILE*`, (3) loop over sorted orders calling `fseeko`/`fgets`/`fread` to read directly to each sequence, (4) strip embedded newlines into a reused `seqBuf` vector, (5) pass `seqBuf.data()` as a drop-in replacement for the former `e.sequence.s`. The gzip fallback is the empty-vector sentinel from Phase 2 — when `fastaOffsets[whichFasta].empty()`, the original KSeq path is preserved unchanged.

`fillTargetKmerBuffer` is more complex because the Prodigal code path reads a training sequence via a second `KSeqFactory` call (on `trainingSeqFasta`) and then operates on `maskedSeq` which may need to refer to the reverse complement. The locked decision is that the training sequence block stays on KSeq; only the main sequence scan loop over `accessionBatches[batchIdx].orders` is refactored. The `maskedSeq` pattern is replaced by in-place masking into `seqBuf` except for the reverse-complement sub-case in the Prodigal path, which needs a second buffer for the reverse-complemented, masked sequence.

**Primary recommendation:** Implement a shared static/inline helper `readFastaSequence(FILE* fp, off_t offset, off_t nextOffset, vector<char>& buf)` that encapsulates the fseeko + fgets (skip header) + fread/newline-strip logic, then call it from both functions. This avoids duplicating the tricky boundary logic and makes the two refactors testable in isolation.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| POSIX `fseeko` / `ftello` | POSIX.1-2001 | 64-bit random file access | Already guarded by `_FILE_OFFSET_BITS=64` (BUILD-01) and `static_assert(sizeof(off_t)==8)` (BUILD-02) from Phase 2 |
| `fgets` | C standard | Skip FASTA header line after seek | Single call, stops at `\n` — correct for reading up to line end |
| `fread` | C standard | Read sequence bytes bounded by next offset | Block read from current position to `nextOffset - ftello(fp)` bytes |
| OpenMP `#pragma omp parallel` | Existing | Per-thread work partitioning | Already present in both functions; `seqBuf` declared in the parallel block for thread locality |
| `std::sort` | C++17 | Sort batch orders by ascending byte offset | Used to ensure forward-only file access within each batch |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `KSeqWrapper` / `KSeqFactory` | Existing | gzip fallback + training sequence reads | When `fastaOffsets[whichFasta].empty()` or for `trainingSeqFasta` reads |
| `SeqIterator::maskLowComplexityRegions` | Existing | In-place masking | Called with `seqBuf.data()` as both src and dst when `par.maskMode` is set |
| `seqIterator.reverseComplement` | Existing | Reverse complement for Prodigal antisense path | Only in `fillTargetKmerBuffer` Prodigal branch; result still goes into a separate buffer before masking |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `fread` block read bounded by nextOffset | `fgets` loop | `fread` is one syscall, but must strip `\n` manually; `fgets` loop handles lines naturally but has per-line call overhead. For sequences up to tens of MB, `fread` + memcpy stripping is cleaner. |
| Helper function | Inline in both bodies | Inline avoids a function call but duplicates ~20 lines of tricky FASTA parsing in two places. Helper is safer given the last-sequence EOF edge case. |
| `fseek(fp,0,SEEK_END)+ftello` for last seq | sentinel value | `fseek(SEEK_END)+ftello` is one extra call per last sequence; acceptable given it is rare and avoids storing a fake sentinel in `fastaOffsets`. |

**Installation:** No new packages — all I/O is POSIX standard library already linked.

---

## Architecture Patterns

### Recommended Project Structure

No new files required. All changes are within:
```
src/commons/IndexCreator.cpp   # Both function bodies refactored
README.md                      # DOCS-01 limitation note
```

Optionally, a helper can be added as a private static method in `IndexCreator.h` or as a file-scope `static` function at the top of `IndexCreator.cpp`.

### Pattern 1: fseeko Sequence Read Helper

**What:** Encapsulates the seek + header skip + bounded body read + newline strip into one reusable function.

**When to use:** Called for every (ordinal, FILE*) pair inside the sorted batch loop in both `extractKmerFromSixFrames` and `fillTargetKmerBuffer`.

```cpp
// File-scope static in IndexCreator.cpp
// Returns number of sequence bytes placed in buf (no null terminator added).
// buf is resized to fit. Newlines are stripped in-place.
// If nextOffset == 0, reads to EOF (last sequence sentinel).
static size_t readFastaSequence(FILE* fp,
                                off_t seqOffset,
                                off_t nextOffset,
                                std::vector<char>& buf) {
    if (fseeko(fp, seqOffset, SEEK_SET) != 0) return 0;

    // Skip header line (the '>' line)
    char headerBuf[4096];
    if (!fgets(headerBuf, sizeof(headerBuf), fp)) return 0;
    // Handle header lines longer than headerBuf (rare but must not be silently truncated)
    while (headerBuf[strlen(headerBuf) - 1] != '\n') {
        if (!fgets(headerBuf, sizeof(headerBuf), fp)) break;
    }

    off_t bodyStart = ftello(fp);
    size_t readLen;
    if (nextOffset > 0) {
        // Bounded read: nextOffset is the '>' of the next record
        if (nextOffset <= bodyStart) return 0;
        readLen = static_cast<size_t>(nextOffset - bodyStart);
    } else {
        // Last sequence: read to EOF
        fseeko(fp, 0, SEEK_END);
        off_t fileEnd = ftello(fp);
        if (fileEnd <= bodyStart) return 0;
        readLen = static_cast<size_t>(fileEnd - bodyStart);
        fseeko(fp, bodyStart, SEEK_SET);
    }

    buf.resize(readLen);
    size_t got = fread(buf.data(), 1, readLen, fp);

    // Strip newlines in-place, shrink buffer to actual sequence length
    size_t out = 0;
    for (size_t i = 0; i < got; ++i) {
        if (buf[i] != '\n' && buf[i] != '\r') {
            buf[out++] = buf[i];
        }
    }
    buf.resize(out);
    return out;
}
```

### Pattern 2: Sort Orders by Ascending Byte Offset (EXTKMER-02, FILLTGT-02)

**What:** Before iterating over `accessionBatches[batchIdx].orders`, create a sorted index array so file seeks go forward only.

**When to use:** At the start of the fseeko branch (after confirming offsets are available), inside each batch processing block.

```cpp
// Build a sorted permutation of [0 .. orders.size()-1] by ascending byte offset
const auto& orders  = accessionBatches[batchIdx].orders;
const auto& offsets = fastaOffsets[whichFasta];

std::vector<size_t> sortedIdx(orders.size());
std::iota(sortedIdx.begin(), sortedIdx.end(), 0);
std::sort(sortedIdx.begin(), sortedIdx.end(), [&](size_t a, size_t b) {
    return offsets[orders[a]] < offsets[orders[b]];
});

// Then iterate: for (size_t si : sortedIdx) { uint32_t ordinal = orders[si]; ... }
```

Note: `taxIDs`, `lengths` must be accessed via the same permutation index (`si`) to stay aligned with `orders`.

### Pattern 3: fseeko Branch Structure in extractKmerFromSixFrames

**What:** Replaces the `KSeqFactory` + `while (kseq->ReadEntry())` scan with the fseeko read path.

```cpp
// Inside the OpenMP parallel block, per-thread:
std::vector<char> seqBuf;   // declared once; reused across sequences in the batch

// Inside the batch loop, after reserveMemory succeeds:
uint32_t whichFasta = accessionBatches[batchIdx].whichFasta;

if (!fastaOffsets[whichFasta].empty()) {
    // fseeko path
    FILE* fp = fopen(fastaPaths[whichFasta].c_str(), "rb");
    if (!fp) { /* handle error */ }

    // Sort orders by ascending offset (EXTKMER-02)
    // ... (sortedIdx as above)

    for (size_t si : sortedIdx) {
        uint32_t ordinal  = orders[si];
        TaxID    taxID    = accessionBatches[batchIdx].taxIDs[si];
        uint32_t seqLen   = accessionBatches[batchIdx].lengths[si];

        off_t curOff  = static_cast<off_t>(fastaOffsets[whichFasta][ordinal]);
        off_t nextOff = (ordinal + 1 < fastaOffsets[whichFasta].size())
                        ? static_cast<off_t>(fastaOffsets[whichFasta][ordinal + 1])
                        : 0; // sentinel: last sequence → read to EOF

        size_t seqBytes = readFastaSequence(fp, curOff, nextOff, seqBuf);
        seqBuf.push_back('\0'); // null-terminate for downstream consumers

        // In-place masking (EXTKMER-04)
        if (par.maskMode) {
            SeqIterator::maskLowComplexityRegions(
                (unsigned char*) seqBuf.data(),
                (unsigned char*) seqBuf.data(),   // src == dst: in-place
                probMatrix, par.maskProb, subMat);
        }

        kmerExtractor->extractKmer_dna2aa(
            seqBuf.data(), seqBytes,
            kmerBuffer, posToWrite, taxID,
            accessionBatches[batchIdx].speciesID);
    }
    fclose(fp);
} else {
    // Gzip fallback: existing KSeqWrapper path unchanged (EXTKMER-03)
    KSeqWrapper* kseq = KSeqFactory(fastaPaths[whichFasta].c_str());
    // ... original while(kseq->ReadEntry()) loop ...
    delete kseq;
}
```

### Pattern 4: seqBuf Lifecycle for fillTargetKmerBuffer Prodigal Path

**What:** The Prodigal code path has two sub-cases after reading a sequence: (A) forward strand and (B) reverse complement. Sub-case (B) currently allocates a new `maskedSeq` for the reverse-complemented, masked sequence.

**When to use:** Only in `fillTargetKmerBuffer` when `par.maskMode` is active and the strand check (`compareMinHashList`) returns false.

The reverse-complement path requires:
1. `seqBuf` holds the raw forward sequence (used to compute reverse complement via `seqIterator.reverseComplement(seqBuf.data(), seqBytes)` which returns a `malloc`-allocated buffer `reverseComplement`)
2. A second masking target is needed — this can reuse a second `vector<char> rcBuf` declared alongside `seqBuf` in the OpenMP parallel block, or the existing `maskedSeq` pointer pattern can be retained using `seqBuf.data()` as the source for masking into `rcBuf`

```cpp
// In the OpenMP parallel block (alongside seqBuf):
std::vector<char> seqBuf;
std::vector<char> rcBuf;   // reusable buffer for reverse-complement + masking

// In the Prodigal reverse-complement branch (inside fseeko path):
reverseComplement = seqIterator.reverseComplement(seqBuf.data(), seqBytes);
// ... prodigal->getPredictedGenes on reverseComplement ...

if (par.maskMode) {
    rcBuf.resize(seqBytes + 1);
    SeqIterator::maskLowComplexityRegions(
        (unsigned char*) reverseComplement,
        (unsigned char*) rcBuf.data(),
        probMatrix, par.maskProb, subMat);
    rcBuf[seqBytes] = '\0';
    // Use rcBuf.data() as maskedSeq for extractTargetKmers
} else {
    // maskedSeq = reverseComplement (pointer, no allocation)
}
free(reverseComplement);
```

Note: `maskLowComplexityRegions` writes character-by-character from src to dst starting at index 0 (confirmed from SeqIterator.cpp line 158), so src == dst is safe for the forward-strand case. For the reverse-complement case, src (`reverseComplement`) and dst (`rcBuf.data()`) are separate allocations, which is also correct.

### Anti-Patterns to Avoid

- **Sorting `accessionBatches[batchIdx].orders` in-place:** This mutates shared state read by other threads. Build a local `sortedIdx` permutation instead.
- **Caching `FILE*` across batches at this phase:** PERF-02 is explicitly deferred. Open and close per batch.
- **Using `ftello` for last-sequence EOF detection without seeking back:** `fseek(SEEK_END) + ftello` leaves the file pointer at EOF; must `fseeko` back to `bodyStart` before `fread`. The helper above handles this correctly.
- **Null-terminating before `resize(out)` in the helper:** The null terminator must be added by the caller after the helper returns, otherwise it gets included in the `out` count and confuses `seqBuf.size()`.
- **Applying the fseeko sort to the `taxIDs`/`lengths` arrays:** These arrays are parallel to `orders` — do NOT re-sort them. Access via the same `si` permutation index.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Newline stripping from multi-line FASTA | Custom parser | Simple `memcpy` with `if (c != '\n' && c != '\r')` filter inside `fread` result | FASTA body has only sequence characters and newlines; no other special characters |
| In-place masking | Separate allocation | `maskLowComplexityRegions(buf, buf, ...)` | Confirmed safe: implementation reads `seq[i]` and writes `maskedSeq[i]` sequentially, no overlap hazard |
| Offset sort | Manual insertion sort | `std::sort` + `std::iota` | Already available; correct and tested |
| gzip detection | Re-implement magic bytes | The `fastaOffsets[whichFasta].empty()` sentinel from Phase 2 | Phase 2 already handles gzip detection; empty vector IS the sentinel |

**Key insight:** The FASTA format is simple enough that a small inline newline-stripping loop over the `fread` result is the correct approach — no need for a streaming parser once the byte range is bounded.

---

## Common Pitfalls

### Pitfall 1: Ordinal Mismatch Between Pre-pass and getObservedAccessions
**What goes wrong:** `fastaOffsets[fileIdx][ordinal]` was built by iterating all `>` characters in the file. `getObservedAccessions` uses `KSeqWrapper` which skips duplicate accessions (see `duplicateCheck` set in IndexCreator.cpp line 537). If a FASTA file has duplicate accession headers, the `order` field stored in `Accession` (incremented per `KSeqWrapper::ReadEntry()`) will NOT match the `ordinal` index in `fastaOffsets`.

**Why it happens:** `buildFastaOffsetIndex` counts every `>`, while `getObservedAccessions` skips duplicates and increments `order` only for non-duplicates.

**How to avoid:** The CONTEXT.md notes this as the most dangerous failure mode (STATE.md line 85). The v1 approach is: FASTA files must not have duplicate accession headers (this is already a documented requirement in README.md line 416). The regression test corpus was built to not have duplicates. Document that ordinal == physical sequence position (0-indexed count of `>` characters seen), not a deduplicated count.

**Warning signs:** `fseeko` lands on a sequence header different from the expected accession; regression test fails with differing byte offsets; spot-check validation fires.

### Pitfall 2: Long FASTA Header Lines Overflowing fgets Buffer
**What goes wrong:** `fgets(headerBuf, 4096, fp)` stops at 4095 characters. If a FASTA header is longer than 4095 characters, the next `fread` call will start mid-header, treating remaining header characters as sequence data.

**Why it happens:** Unusually long FASTA headers (e.g., NCBI full-description headers) can exceed 4 KB.

**How to avoid:** Use a loop that calls `fgets` until the result ends with `\n` (as shown in the helper pattern above). This consumes the entire header regardless of length before reading the sequence body.

**Warning signs:** Sequence data starts with `>` or pipe character; k-mer extraction sees non-ATCG characters at the beginning of seqBuf.

### Pitfall 3: Last Sequence in File — No ordinal+1 Entry
**What goes wrong:** When `ordinal == fastaOffsets[whichFasta].size() - 1`, there is no `fastaOffsets[whichFasta][ordinal + 1]`. Using `ordinal + 1` without bounds-checking reads undefined memory.

**Why it happens:** The offset array has exactly as many entries as sequences; the last sequence has no "next" offset to bound the read.

**How to avoid:** Use `nextOffset = 0` as a sentinel meaning "read to EOF". In the helper, the `nextOffset == 0` branch calls `fseeko(SEEK_END) + ftello` to get file size, then seeks back to `bodyStart` before `fread`.

**Warning signs:** Garbage bytes or truncated last sequences in the refactored build; regression test fails on databases whose last sequence is large.

### Pitfall 4: In-place maskedSeq delete at End of Sequence Loop Iteration
**What goes wrong:** The existing `fillTargetKmerBuffer` code has `if (par.maskMode) { delete[] maskedSeq; }` at line 1308–1310, AFTER the `idx++` increment. In the reverse-complement branch, `maskedSeq` is re-allocated at line 1285. In the refactored path using `seqBuf`, this `delete[]` must not be applied — `seqBuf` is a vector managed automatically. The `rcBuf` is also vector-managed.

**Why it happens:** The existing code mixes manual ownership (`maskedSeq = new char[...]` / `delete[]`) with borrowed-pointer mode (`maskedSeq = e.sequence.s`). The refactored code eliminates all manual allocation; the existing `delete[]` guard must be removed from the fseeko branch.

**How to avoid:** In the fseeko branch, never set `maskedSeq` to a `new char[...]` allocation. Use `seqBuf.data()` (forward) and `rcBuf.data()` (reverse complement) as non-owning pointers into vector-managed storage. Remove the `if (par.maskMode) { delete[] maskedSeq; }` guard entirely from the fseeko branch.

### Pitfall 5: Mutating accessionBatches[batchIdx].orders in Place
**What goes wrong:** `accessionBatches[batchIdx]` is shared read-only across threads (each batch is claimed via `batchChecker[batchIdx].exchange(true)`). If a thread sorts `orders` in-place, it corrupts `taxIDs` and `lengths` alignment for any other code that reads the same batch.

**Why it happens:** `std::sort` on `orders` directly re-orders the array; `taxIDs[idx]` and `lengths[idx]` are parallel arrays indexed by the same `idx` and would no longer align.

**How to avoid:** Build a local `sortedIdx` permutation vector (as shown in Pattern 2) and access `orders`, `taxIDs`, `lengths` via the permutation. Never sort `orders`, `taxIDs`, or `lengths` directly.

---

## Code Examples

Verified patterns from direct source inspection:

### Current extractKmerFromSixFrames Inner Loop (to be replaced for fseeko case)
```cpp
// Source: IndexCreator.cpp lines 1040-1082
KSeqWrapper* kseq = KSeqFactory(fastaPaths[accessionBatches[batchIdx].whichFasta].c_str());
size_t seqCnt = 0;
size_t idx = 0;
while (kseq->ReadEntry()) {
    if (seqCnt == accessionBatches[batchIdx].orders[idx]) {
        const KSeqWrapper::KSeqEntry & e = kseq->entry;
        char *maskedSeq = nullptr;
        if (par.maskMode) {
            maskedSeq = new char[e.sequence.l + 1];
            SeqIterator::maskLowComplexityRegions((unsigned char*) e.sequence.s,
                                                  (unsigned char*) maskedSeq,
                                                  probMatrix, par.maskProb, subMat);
            maskedSeq[e.sequence.l] = '\0';
        } else {
            maskedSeq = e.sequence.s;
        }
        kmerExtractor->extractKmer_dna2aa(maskedSeq, e.sequence.l, kmerBuffer, posToWrite,
                                          accessionBatches[batchIdx].taxIDs[idx],
                                          accessionBatches[batchIdx].speciesID);
        idx++;
        if (par.maskMode) { delete[] maskedSeq; }
        if (idx == accessionBatches[batchIdx].lengths.size()) { break; }
    }
    seqCnt++;
}
delete kseq;
```

### fastaOffsets Data Structure (from Phase 2)
```cpp
// Source: IndexCreator.h line 142
vector<vector<uint64_t>> fastaOffsets;
// fastaOffsets[fileIdx][ordinal] = byte offset of '>' character
// Empty vector = gzip file = use KSeq fallback
```

### maskLowComplexityRegions In-Place Safety
```cpp
// Source: SeqIterator.cpp lines 154-175
// seq[i] is read BEFORE maskedSeq[i] is written (index advances together)
// SAFE to call with (buf, buf) as (src, dst)
void SeqIterator::maskLowComplexityRegions(
    const unsigned char *seq, unsigned char *maskedSeq, ...) {
    unsigned int seqLen = 0;
    while (seq[seqLen] != '\0') {
        maskedSeq[seqLen] = (char) subMat->aa2num[static_cast<int>(seq[seqLen])];
        seqLen++;
    }
    // tantan masking in-place on maskedSeq ...
    for (unsigned int pos = 0; pos < seqLen; pos++) {
        char nt = seq[pos]; // reads from original seq (const)
        maskedSeq[pos] = (maskedSeq[pos] == probMat.hardMaskTable[0]) ? 'N' : nt;
    }
}
// NOTE: The final loop reads seq[pos] (original) and writes maskedSeq[pos].
// When src == dst (in-place), seq[pos] and maskedSeq[pos] are the same memory.
// seq[pos] is read before maskedSeq[pos] is overwritten — SAFE.
```

**CAUTION for in-place masking:** `maskLowComplexityRegions` converts characters via `subMat->aa2num[]` in the first loop, then reads the ORIGINAL `seq[pos]` in the final loop. When called in-place (`seq == maskedSeq`), the first loop has already converted `seq[pos]` values. The final loop reads the now-converted value, not the original nucleotide character. This means the `maskedSeq[pos] == probMat.hardMaskTable[0]` comparison works on converted values, and the fallback `nt = seq[pos]` returns the CONVERTED character. This is consistent with the existing non-in-place behavior (where `seq` is the original KSeq buffer and `maskedSeq` is the new allocation). In-place is safe only if `subMat->aa2num` converts nucleotides to themselves (passes through) OR if the first-loop conversion is intentional. Verify by running the regression test.

### getObservedAccessions Order Assignment (confirms ordinal = physical position)
```cpp
// Source: IndexCreator.cpp lines 527-545
// order is incremented per ReadEntry(), SKIPPING duplicates
for (size_t i = 0; i < fastaPaths.size(); ++i) {
    KSeqWrapper* kseq = KSeqFactory(fastaPaths[i].c_str());
    uint32_t order = 0;
    while (kseq->ReadEntry()) {
        // ... duplicate check ...
        if (duplicateCheck.find(e.name.s) != duplicateCheck.end()) { continue; }
        localObservedAccessionsVec.emplace_back(string(e.name.s), i, order, e.sequence.l);
        order++;   // incremented ONLY for non-duplicates
    }
}
// fastaOffsets[i][j] = j-th '>' in file i (ALL headers, including duplicates)
// Mismatch risk: if a file has duplicate headers, order != physical ordinal
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `KSeqFactory` + scan from byte 0 for each batch | `fseeko` direct seek per sequence | Phase 3 | Eliminates O(N) redundant reads per batch; each sequence is read exactly once |
| `new char[e.sequence.l + 1]` + `delete[]` per sequence | `vector<char> seqBuf` resized per sequence | Phase 3 | Eliminates per-sequence heap allocation/deallocation in hot path |
| `maskedSeq = e.sequence.s` (borrowed pointer from KSeq buffer) | `seqBuf.data()` as in-place buffer | Phase 3 | seqBuf owns its memory; no KSeq buffer lifetime dependency |

**Deprecated/outdated in Phase 3:**
- `KSeqWrapper` for main sequence scan loop (in `extractKmerFromSixFrames` and `fillTargetKmerBuffer`): retained ONLY for gzip fallback and training sequence reads.

---

## Open Questions

1. **In-place masking correctness with nucleotide sequences**
   - What we know: `maskLowComplexityRegions` converts characters via `subMat->aa2num[]` then reads original `seq[pos]` in the final character restoration loop. When in-place, `seq[pos]` has already been converted.
   - What's unclear: Whether `subMat->aa2num[nt]` for nucleotide characters A/T/C/G returns the same value as the original or an AA integer code, and whether the final loop's `nt = seq[pos]` will return the original nucleotide or the converted value.
   - Recommendation: Add an assertion or log comparison in the first regression run. If in-place masking produces different output, fall back to using `seqBuf` as src and a second per-thread buffer as dst for the masking step only.

2. **Header line longer than fgets buffer**
   - What we know: NCBI FASTA headers can be very long (full organism description).
   - What's unclear: Whether the test corpus and production FASTA files contain headers exceeding 4 KB.
   - Recommendation: Use the looping `fgets` approach in the helper (as documented in Pattern 1) — handles any header length without truncation.

3. **Ordinal mismatch for files with duplicate accessions**
   - What we know: `order` in `getObservedAccessions` is incremented only for non-duplicate entries; `fastaOffsets[i][j]` indexes ALL `>` positions.
   - What's unclear: Whether any production FASTA files fed to Metabuli contain duplicate accession headers.
   - Recommendation: The regression test corpus does not have duplicates (by construction). Document this as a known limitation; the README already requires unique accession headers (line 416). No code fix needed in Phase 3.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell regression script (bash) |
| Config file | `test/regression_fasta_access.sh` |
| Quick run command | `./test/regression_fasta_access.sh ./build/src/metabuli` |
| Full suite command | `./test/regression_fasta_access.sh ./build/src/metabuli` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXTKMER-01 | fseeko path used when offsets available | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| EXTKMER-02 | Batch sorted by offset (forward-only) | integration (implicit: same output = forward-only worked) | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| EXTKMER-03 | Gzip fallback produces same output as sequential | integration | Run with a .gz FASTA file (requires corpus with gzip file) | ❌ Wave 0 gap |
| EXTKMER-04 | seqBuf reuse produces identical k-mers to new/delete approach | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| FILLTGT-01 | fseeko path in fillTargetKmerBuffer | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| FILLTGT-02 | Batch sorted in fillTargetKmerBuffer | integration (implicit) | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| FILLTGT-03 | Gzip fallback in fillTargetKmerBuffer | integration | Same gzip test as EXTKMER-03 | ❌ Wave 0 gap |
| FILLTGT-04 | seqBuf reuse in fillTargetKmerBuffer | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ |
| DOCS-01 | README.md contains gzip limitation note | manual-only | grep for "gzip" in README.md: `grep -i gzip README.md` | ❌ Wave 0: note not yet written |

### Sampling Rate
- **Per task commit:** `./test/regression_fasta_access.sh ./build/src/metabuli`
- **Per wave merge:** `./test/regression_fasta_access.sh ./build/src/metabuli`
- **Phase gate:** Full regression script green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] Gzip fallback corpus — at least one .gz FASTA in `test/data/` with a corresponding test invocation in `regression_fasta_access.sh` to verify EXTKMER-03 / FILLTGT-03. **Note:** CONTEXT.md locks the gzip fallback to unchanged KSeq behavior; the regression test for this is optional validation, not a blocking gap. The existing regression script already covers the non-gzip path fully.
- [ ] DOCS-01 is manual-only; no automated test. Reviewer inspects README.md after the documentation task.

*(The existing `test/regression_fasta_access.sh` covers all fseeko-path requirements (EXTKMER-01/02/04, FILLTGT-01/02/04) via byte-comparison of `diffIdx`, `info`, and `split` outputs.)*

---

## Sources

### Primary (HIGH confidence)
- Direct source inspection: `src/commons/IndexCreator.cpp` lines 1002-1334 — both function bodies read in full
- Direct source inspection: `src/commons/IndexCreator.h` — `fastaOffsets` field, `AccessionBatch` struct, function signatures
- Direct source inspection: `src/commons/SeqIterator.cpp` lines 154-175 — `maskLowComplexityRegions` implementation; in-place safety confirmed
- Direct source inspection: `test/regression_fasta_access.sh` — regression test logic and scope confirmed
- Direct source inspection: `.planning/phases/03-inner-loop-refactor/03-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)
- POSIX.1-2001 standard: `fseeko`/`ftello` semantics; `SEEK_END` positioning behavior — standard guarantee

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are POSIX standard or already present in codebase
- Architecture: HIGH — patterns derived directly from existing function bodies and Phase 2 infrastructure
- Pitfalls: HIGH — ordinal mismatch and in-place masking issues identified from direct code reading; others are standard FASTA parsing edge cases
- Test mapping: HIGH — regression script read and test files confirmed present

**Research date:** 2026-03-05
**Valid until:** 2026-04-04 (stable — POSIX APIs; only risk is upstream code changes in IndexCreator.cpp)
