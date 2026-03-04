# Stack Research

**Domain:** C++ FASTA random access — I/O API selection for multi-threaded, cross-platform bioinformatics pipeline
**Researched:** 2026-03-04
**Confidence:** HIGH

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `fseeko` / `ftello` + thread-local `FILE*` | POSIX.1-2001 / C99 extension | Byte-offset random access into uncompressed FASTA files | Fits existing `FILE*` codebase pattern; `off_t` is 64-bit on all target platforms when configured correctly; thread-safe when each thread owns its own handle |
| `uint64_t` offset table (`vector<vector<uint64_t>>`) | C++17 stdlib | Store one byte offset per FASTA ordinal, per file | Exact match for `fastaOffsets[fileIdx][ordinal]` access pattern |
| OpenMP `#pragma omp parallel for schedule(dynamic)` | OpenMP 3.0+ | Parallelize the offset-building pre-pass across 2,382 files | Files are independent — embarrassingly parallel |

### Supporting APIs

| API | Purpose | When to Use |
|-----|---------|-------------|
| POSIX `pread(2)` | Atomic seek+read without FILE* buffering layer | Linux/macOS only; future optimization path after Phase 1 |
| `mmap(2)` | Map entire FASTA into virtual address space | NOT recommended at this scale (see below) |
| Windows `_fseeki64` / `_ftelli64` | Large-file fseek on native MSVC | Only needed if dropping Cygwin; current build uses Cygwin which provides POSIX `fseeko` |

---

## Why fseeko + Thread-Local FILE* (Not mmap or pread)

### Why Not mmap

1. **Virtual address space exhaustion**: 2,382 files × 378 MB avg = 900 GB. Mapping simultaneously requires 900 GB of VAS. Even mapping one file at a time requires careful `munmap` discipline and creates TLB pressure.
2. **No performance advantage over fseeko at this scale**: When seeking large distances in large files, TLB miss cost of a new mapping rivals the syscall overhead.
3. **Windows portability**: `mmap` is POSIX. Windows uses `CreateFileMapping` + `MapViewOfFile`. Metabuli uses Cygwin for Windows builds, but adding mmap creates complexity for a hypothetical future native MSVC build.
4. **Existing codebase uses `FILE*` everywhere** — introducing mmap creates a second I/O paradigm.

### Why Not pread

`pread(fd, buf, count, offset)` is atomic (no separate seek+read race) and multiple threads can share a single `int fd` safely. However:
1. **Not available on Windows** (Cygwin provides it, but native MSVC doesn't).
2. **Bypasses stdio buffering** — requires manual buffering for variable-length sequence reads.

**Verdict:** Use `fseeko` + thread-local `FILE*` for Phase 1. Document `pread` as the Linux-only fast path upgrade for a future pass.

### The Recommended Pattern

```cpp
// Pre-pass: build offset index (once, parallel across files)
vector<vector<uint64_t>> fastaOffsets(fastaPaths.size());

#pragma omp parallel for schedule(dynamic, 1)
for (size_t i = 0; i < fastaPaths.size(); ++i) {
    FILE* fp = fopen(fastaPaths[i].c_str(), "rb");
    char linebuf[65536];
    uint64_t lineStart = (uint64_t)ftello(fp);
    while (fgets(linebuf, sizeof(linebuf), fp)) {
        if (linebuf[0] == '>') {
            fastaOffsets[i].push_back(lineStart);
        }
        lineStart = (uint64_t)ftello(fp);
    }
    fclose(fp);
}

// Extraction loop: random access per batch, per thread
FILE* fp = fopen(fastaPaths[whichFasta].c_str(), "rb");
fseeko(fp, (off_t)fastaOffsets[whichFasta][ordinal], SEEK_SET);
// Read header + sequence into thread-local seqBuf using existing FASTA parsing
fclose(fp);
```

---

## fseeko vs fseek: Large File Offsets

### The Problem With fseek

`fseek(FILE*, long, int)` uses `long`. On 32-bit Linux and 64-bit Windows (MSVC), `long` is 32 bits — maximum offset ~2 GB. NCBI FASTA files can exceed this easily.

### The Solution

**Always use `fseeko` with `off_t`.**

Add to `CMakeLists.txt`:
```cmake
if(UNIX)
    add_compile_definitions(_FILE_OFFSET_BITS=64)
endif()
```

This ensures `off_t` is 64-bit on 32-bit Linux. No-op on 64-bit Linux and macOS. Belt-and-suspenders protection.

**Store all offsets as `uint64_t`** (not `off_t` — type varies by platform). Cast to `(off_t)` only at the `fseeko` call site.

Use `ftello` (not `ftell`) for offset building — same 64-bit vs 32-bit issue.

---

## Offset Building: ftello-Based Scanning

```cpp
// Open in binary mode — critical on Windows to avoid CRLF->LF conversion
// that would make ftello offsets inconsistent with physical file bytes
FILE* fp = fopen(path, "rb");

char linebuf[65536];
uint64_t lineStart = (uint64_t)ftello(fp);
while (fgets(linebuf, sizeof(linebuf), fp)) {
    if (linebuf[0] == '>') {
        offsets.push_back(lineStart);  // offset of '>' byte
    }
    lineStart = (uint64_t)ftello(fp);
}
```

`ftello` on a buffered `FILE*` reads the internal position counter — no syscall. Not a performance concern for the pre-pass. **Always use `"rb"` (binary mode)** — text mode silently converts `\r\n` to `\n` on Windows, making `ftello` offsets inconsistent with physical file positions.

---

## How htslib Handles FASTA Indexing (FAI Format)

The htslib `.fai` format stores:
```
NAME    LEN    OFFSET    LINEBASES    LINEWIDTH
```

Where `OFFSET` is the byte offset of the **first base character** (not the `>`), enabling O(1) sub-sequence access via `OFFSET + (i/LINEBASES)*LINEWIDTH + (i%LINEBASES)`. This requires uniform line lengths.

**What Metabuli should do differently:**
- Store offset of the `>` character (not the first base) — Metabuli reads full sequences, so positioning at `>` and letting the existing parser read the rest is the correct interface.
- Do not require uniform line lengths — store per-sequence offsets, let the sequential reader handle variable-length lines after seeking.
- FAI's LINEWIDTH trick enables sub-sequence O(1) access — not needed for Phase 1 (whole-sequence reads only).

---

## Thread Safety of FILE*

A single `FILE*` handle is **not thread-safe**. Use one of:

**Pattern 1: One FILE* per thread, opened per batch (simplest)**
```cpp
FILE* fp = fopen(fastaPaths[whichFasta].c_str(), "rb");
fseeko(fp, (off_t)offset, SEEK_SET);
// ... read sequence ...
fclose(fp);
```

**Pattern 2: Per-thread cached FILE* handles (recommended optimization)**
```cpp
// One cache per thread, keyed by fileIdx
vector<unordered_map<uint32_t, FILE*>> threadFileCache(omp_get_max_threads());

int tid = omp_get_thread_num();
auto& cache = threadFileCache[tid];
FILE* fp;
auto it = cache.find(whichFasta);
if (it == cache.end()) {
    fp = fopen(fastaPaths[whichFasta].c_str(), "rb");
    cache[whichFasta] = fp;
} else {
    fp = it->second;
}
fseeko(fp, (off_t)offset, SEEK_SET);
// Close all handles at end of parallel region
```

Avoids repeated `fopen`/`fclose` when a thread processes multiple batches from the same file.

---

## Platform Portability Matrix

| API | Linux 64-bit | macOS | Windows (Cygwin) | Windows (MSVC native) |
|-----|-------------|-------|-------------------|-----------------------|
| `fseeko` | YES (`_FILE_OFFSET_BITS=64`) | YES | YES | NO → use `_fseeki64` |
| `ftello` | YES | YES | YES | NO → use `_ftelli64` |
| `off_t` 64-bit | YES (`_FILE_OFFSET_BITS=64`) | YES | YES | NO → use `__int64` |
| `pread` | YES | YES | YES (Cygwin) | NO |
| `mmap` | YES | YES | YES (Cygwin) | NO |
| Thread-local `FILE*` | YES | YES | YES | YES |

**Metabuli's Windows build uses Cygwin** (verified in `azure-pipelines.yml`). Cygwin provides `fseeko`, `ftello`, `off_t` (64-bit). `fseeko` + thread-local `FILE*` works on all three platforms.

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `fseek` with `long` offset | 32-bit `long` on MSVC 64-bit = broken for files >2 GB | `fseeko` with `off_t` |
| `ftell` with `long` return | Same truncation | `ftello` |
| Shared `FILE*` across threads | Not thread-safe; UB on concurrent fseek+fread | Per-thread `FILE*` |
| `std::fstream::seekg` with `streamoff` | `streamoff` is `ptrdiff_t` on some platforms (32-bit on 32-bit) | C `fseeko` / `FILE*` directly |
| Text-mode open (`"r"`) | CRLF→LF conversion makes `ftello` offsets wrong on Windows | Always use `"rb"` |
| Mapping all 2,382 files with mmap | 900 GB VAS; TLB pressure | Thread-local FILE* with fseeko |

---

## Sources

- `fseeko`/`ftello`: ISO C99 §7.19, POSIX.1-2001 — HIGH confidence
- `_FILE_OFFSET_BITS=64`: glibc `feature_test_macros(7)` — HIGH confidence
- `fseek(long)` truncation on MSVC 64-bit: Microsoft docs for `_fseeki64` — HIGH confidence
- htslib FAI format: hts-specs repository `fai.md`, SAMtools documentation — HIGH confidence
- `FILE*` thread safety: C11 §7.21.2; POSIX thread safety classification — HIGH confidence
- `pread` atomicity: POSIX.1-2008 §2.9.7 — HIGH confidence
- Cygwin `fseeko`/`off_t`: Cygwin POSIX compliance docs — HIGH confidence
- Codebase verification: `src/commons/IndexCreator.cpp`, `azure-pipelines.yml`, `util/build_windows.sh` — HIGH confidence

---
*Stack research for: Metabuli FASTA random access I/O — Phase 1*
*Researched: 2026-03-04*
