# Pitfalls Research: fseek-Based FASTA Random Access

**Domain:** C++ multi-threaded FASTA random access pitfalls
**Researched:** 2026-03-04
**Confidence:** HIGH

---

## Critical Pitfalls

### 1. fseek() Silently Truncates Offsets Above 2 GB

**Warning sign:** No compiler error. Wrong sequences silently fetched for any offset > 2 GB.

`fseek(FILE*, long, int)` — `long` is 32 bits on Windows (MSVC) and in 32-bit ABIs. Core_nt files reach hundreds of GB. The **existing codebase already has this bug** in `KmerMatcher.cpp:262,264,900`:
```cpp
fseek(kmerInfoFp, 4 * (long)(kmerInfoBufferIdx), SEEK_SET);  // truncates on Windows for >2 GB
```

**Prevention:**
```cmake
# CMakeLists.txt
if(UNIX)
    add_compile_definitions(_FILE_OFFSET_BITS=64)
endif()
```

```cpp
// Compile-time guard — catches misconfigured builds
static_assert(sizeof(off_t) == 8, "Need 64-bit off_t; set _FILE_OFFSET_BITS=64");

// Use fseeko everywhere — never fseek for FASTA files
fseeko(fp, static_cast<off_t>(fastaOffsets[fileIdx][ordinal]), SEEK_SET);
```

On macOS, `off_t` is always 64-bit. On Linux it requires `_FILE_OFFSET_BITS=64`. Store offsets as `uint64_t`, cast to `(off_t)` only at `fseeko` call site.

**Phase:** CMakeLists.txt + pre-pass setup

---

### 2. Shared FILE* Across Threads — Silent Data Race

**Warning sign:** Intermittent wrong sequences, no crash. Extremely hard to debug.

glibc's per-`FILE*` lock protects individual calls, not seek+read pairs. Thread A seeks, Thread B seeks, Thread A reads — gets Thread B's position.

**Prevention:** Each OpenMP thread opens its own `FILE*` per batch:
```cpp
#pragma omp for schedule(dynamic, 1)
for (size_t batchIdx = 0; batchIdx < accessionBatches.size(); batchIdx++) {
    FILE* fp = fopen(fastaPaths[fileIdx].c_str(), "rb");  // thread-local
    if (!fp) { /* log and continue */ continue; }
    for (size_t idx = 0; idx < batch.orders.size(); idx++) {
        fseeko(fp, fastaOffsets[fileIdx][batch.orders[idx]], SEEK_SET);
        // read header, accumulate sequence
    }
    fclose(fp);
}
```

Multiple independent `FILE*` handles to the same file are fully safe on Linux/macOS/Windows/NFS. The OS does **not** serialize concurrent reads from distinct file descriptions on local filesystems.

**Phase:** Batch processing OMP loop

---

### 3. Text Mode File Open Corrupts Offsets on Windows

**Warning sign:** Works on Linux, wrong sequences on Windows.

Text mode (`"r"`) on Windows translates `\r\n` → `\n`, making `ftello()` positions incompatible with actual file layout. After a seek to a stored offset, the file pointer is in the wrong position.

**Prevention:** Always use binary mode:
```cpp
FILE* fp = fopen(fastaPaths[i].c_str(), "rb");  // "rb" everywhere, not "r"
```

Then strip `\r` explicitly from header and sequence lines after `fgets`:
```cpp
size_t len = strlen(linebuf);
while (len > 0 && (linebuf[len-1] == '\n' || linebuf[len-1] == '\r')) len--;
```

**Phase:** Pre-pass file open + batch processing

---

### 4. Off-by-One: Record Offset BEFORE Reading '>'

**Warning sign:** After `fseeko`, file pointer is one byte past the `>`. Parser reads header starting at second character — accession name is truncated.

**WRONG:**
```cpp
int c = fgetc(fp);
if (c == '>') {
    off_t pos = ftello(fp);  // points to char AFTER '>'
    offsets.push_back(pos);
}
```

**RIGHT:**
```cpp
off_t pos = ftello(fp);         // record BEFORE reading
int c = fgetc(fp);
if (c == '>') {
    offsets.push_back(static_cast<uint64_t>(pos));  // points to '>' itself
}
```

Or using `fgets`:
```cpp
uint64_t lineStart = (uint64_t)ftello(fp);
while (fgets(linebuf, sizeof(linebuf), fp)) {
    if (linebuf[0] == '>') {
        offsets.push_back(lineStart);  // offset BEFORE fgets consumed the line
    }
    lineStart = (uint64_t)ftello(fp);
}
```

**Phase:** Pre-pass offset recording

---

### 5. Ordinal Mismatch Between Pre-Pass and getObservedAccessions()

**Warning sign:** Build completes but produces wrong k-mers. Silent data corruption.

`getObservedAccessions()` uses KSeqWrapper which handles blank lines, CRLF, BOM. If the pre-pass uses different logic, ordinals diverge — wrong sequence fetched for every mismatched entry. This is the most dangerous pitfall because it produces a valid-looking but incorrect database.

**Prevention options (choose one):**
1. **Coordinate pre-pass with `getObservedAccessions()`** — build `fastaOffsets` during the same file scan as accession discovery (single source of truth, no divergence possible)
2. **Spot-check validation** — after building offsets, for a random sample of (fileIdx, ordinal) pairs: `fseeko` to stored offset, assert next character is `>`, extract accession name, compare to `fastaOffsets[fileIdx][ordinal]` accession name

**Phase:** Pre-pass design — ideally resolved in architecture, not just testing

---

### 6. Gzip Files Produce Garbage Offsets

**Warning sign:** Offset pre-pass completes normally. Database build fails or produces wrong results for any `.gz` FASTA file.

`fopen` on a `.gz` file returns compressed bytes. Pre-pass finds `0x3E` bytes randomly in compressed data, producing wrong ordinal→offset mappings.

**Prevention:**
```cpp
// Magic-byte detection
FILE* probe = fopen(path.c_str(), "rb");
uint8_t magic[2];
fread(magic, 1, 2, probe);
fclose(probe);
bool isGzip = (magic[0] == 0x1F && magic[1] == 0x8B);

if (isGzip) {
    // Leave fastaOffsets[i] empty as sentinel for fallback to KSeq sequential path
    Debug(Debug::WARNING) << "FASTA file " << path
        << " is gzip-compressed. Random access disabled; using sequential scan.\n";
    continue;
}
```

In the modified inner loop, check `fastaOffsets[whichFasta].empty()` and fall back to KSeqWrapper.

**Phase:** Pre-pass file open

---

## Moderate Pitfalls

### 7. Multi-Line FASTA Sequences Require Accumulation Loop

NCBI core_nt wraps sequences at 70 characters/line. A single `fgets` after seeking gives a 70-bp fragment, not the full genome.

**Prevention:**
```cpp
// After seeking to sequence start and skipping header line:
seqBuf.clear();
char linebuf[65536];
uint64_t beforeLine = (uint64_t)ftello(fp);
while (fgets(linebuf, sizeof(linebuf), fp)) {
    if (linebuf[0] == '>') {
        // fseeko back to beforeLine if needed (next batch may need this position)
        break;
    }
    size_t len = strlen(linebuf);
    while (len > 0 && (linebuf[len-1] == '\n' || linebuf[len-1] == '\r')) len--;
    seqBuf.insert(seqBuf.end(), linebuf, linebuf + len);
    beforeLine = (uint64_t)ftello(fp);
}
// seqBuf now contains the complete sequence
```

Pre-reserve `seqBuf` to `accession.seqLen` to avoid reallocation for each sequence.

**Phase:** Batch processing sequence reader

---

### 8. Blank Lines Between Sequences Corrupt Ordinal Counter

Some FASTA files have blank lines between records. The pre-pass ordinal counter must count only `>` lines:

```cpp
// Count only sequences (lines starting with '>'), not blank lines
if (linebuf[0] == '>') {
    offsets.push_back(lineStart);
    // ordinal = offsets.size() - 1
}
// blank lines and sequence lines: do NOT increment a separate counter
```

**Phase:** Pre-pass offset recording

---

### 9. fgetc() Throughput Too Slow for 900 GB Pre-Pass

`fgetc()` through glibc's stdio locking machinery per byte becomes CPU-bound at large scale.

**Prevention:** Use `fread()` in 64 KB blocks, parse with `memchr()` for `>` within each buffer:
```cpp
const size_t CHUNK = 65536;
vector<char> chunk(CHUNK);
uint64_t filePos = 0;
size_t bytesRead;
while ((bytesRead = fread(chunk.data(), 1, CHUNK, fp)) > 0) {
    char* p = chunk.data();
    char* end = p + bytesRead;
    while (p < end) {
        char* gt = (char*)memchr(p, '>', end - p);
        if (!gt) break;
        offsets.push_back(filePos + (gt - chunk.data()));
        p = gt + 1;
    }
    filePos += bytesRead;
}
```

**Note:** This changes from line-by-line to byte-scanning — requires careful handling of `>` bytes that appear in quality scores (FASTQ, not FASTA — not applicable here) or sequence data (impossible in valid FASTA; only `>` in header lines).

**Phase:** Pre-pass performance optimization (do after correctness is confirmed)

---

## Low Severity Pitfalls

### 10. Byte Order Mark (BOM) at File Start

Files downloaded via Windows tools may have UTF-8 BOM (`0xEF 0xBB 0xBF`) at byte 0. The pre-pass would find `0xEF` at position 0, not `>`, silently shifting all ordinals by 1.

**Prevention:** Check and skip BOM at file start:
```cpp
uint8_t bom[3];
if (fread(bom, 1, 3, fp) == 3 &&
    bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF) {
    // BOM detected and consumed — continue from byte 3
} else {
    rewind(fp);  // Not a BOM — reset to start
}
```

NCBI standard FASTA files are clean (no BOM). This is belt-and-suspenders.

**Phase:** Pre-pass file open

---

### 11. fastaOffsets Memory Pre-Allocation

Without pre-allocation, each inner `vector<uint64_t>` reallocates repeatedly as sequences are added.

**Prevention:**
```cpp
// After getObservedAccessions() populates per-file sequence counts:
fastaOffsets.resize(fastaPaths.size());
for (size_t i = 0; i < fastaPaths.size(); ++i) {
    fastaOffsets[i].reserve(seqCountPerFile[i]);  // or 8192 as safe default
}
```

Total memory: 20M sequences × 8 bytes ≈ 160 MB. Pre-allocating eliminates realloc copies.

**Phase:** Pre-pass initialization

---

### 12. Embedded Whitespace in Legacy Sequences

Some older FASTA files (pre-NCBI standardization) embed spaces or tabs in sequence data. The sequence accumulation loop must strip these, matching `kseq.h` behavior:

```cpp
// During sequence accumulation:
for (size_t j = 0; j < len; j++) {
    char c = linebuf[j];
    if (c != ' ' && c != '\t') {
        seqBuf.push_back(c);
    }
}
```

NCBI core_nt files do not contain embedded whitespace. Low priority but match existing KSeq behavior.

**Phase:** Batch processing sequence reader

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Severity |
|---------|-----------------|----------|
| fseek() 32-bit truncation | CMakeLists.txt setup | CRITICAL |
| Shared FILE* thread race | OMP batch loop design | CRITICAL |
| Text mode CRLF corruption | Pre-pass file open | CRITICAL |
| Off-by-one at '>' | Pre-pass offset recording | CRITICAL |
| Ordinal mismatch with getObservedAccessions | Pre-pass design | CRITICAL |
| Gzip silent garbage offsets | Pre-pass file format detection | CRITICAL |
| Multi-line sequence truncation | Batch sequence reader | MODERATE |
| Blank-line ordinal drift | Pre-pass counter logic | MODERATE |
| fgetc() throughput | Pre-pass optimization pass | MODERATE |
| BOM corruption | Pre-pass file open | LOW |
| fastaOffsets reallocation | Pre-pass initialization | LOW |
| Embedded whitespace | Batch sequence reader | LOW |

---

## Critical Code Patterns Summary

```cpp
// BAD: existing pattern in KmerMatcher.cpp — DO NOT COPY
fseek(kmerInfoFp, 4 * (long)(kmerInfoBufferIdx), SEEK_SET);  // 32-bit truncation

// GOOD: new pattern for FASTA random access
fseeko(fp, static_cast<off_t>(fastaOffsets[fileIdx][ordinal]), SEEK_SET);

// BAD: shared FILE* across threads
FILE* fp = fopen(path.c_str(), "r");  // text mode + shared = double bug
// ... multiple threads use fp ...

// GOOD: per-batch, binary mode
FILE* fp = fopen(fastaPaths[fileIdx].c_str(), "rb");
// used by one thread only within this batch iteration
fclose(fp);

// BAD: off-by-one
int c = fgetc(fp);
if (c == '>') {
    off_t pos = ftello(fp);  // one byte PAST '>'
    offsets.push_back(pos);
}

// GOOD: record before reading
off_t pos = ftello(fp);
int c = fgetc(fp);
if (c == '>') offsets.push_back((uint64_t)pos);
```

---

*Pitfalls research for: Metabuli FASTA random access — Phase 1*
*Researched: 2026-03-04*
