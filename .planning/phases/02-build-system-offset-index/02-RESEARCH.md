# Phase 2: Build System + Offset Index - Research

**Researched:** 2026-03-05
**Domain:** C++ CMake build system (_FILE_OFFSET_BITS=64), POSIX large-file I/O (fseeko/ftello), OpenMP parallel pre-pass, gzip magic-byte detection
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- `fgetc` per byte — simple, spec-compliant. The pre-pass runs once; 30-min wall time at 500 MB/s is acceptable
- Open/close fresh `FILE*` per file per thread — no shared state, simplest correct implementation
- Gzip detection via magic bytes (0x1F 0x8B) inline inside `buildFastaOffsetIndex()`, not via extension-based utilities — catches renamed .gz files, self-contained
- `static_assert(sizeof(off_t) == 8, "...")` goes directly in `IndexCreator.h` — guards the TU that uses `fseeko`/`ftello`
- Unconditional (no platform ifdef) — always passes on macOS/Windows (off_t already 64-bit), catches misconfigured 32-bit Linux builds
- Hard `exit()` with clear error message if any sampled offset doesn't point to `>` — consistent with all other fatal errors in the codebase; corrupt index is a bug not a recoverable condition
- ~100 pairs total, fixed count regardless of database size — fast, deterministic overhead
- Truly random sample each build (no fixed seed) — prevents bugs from hiding behind a stable sample pattern
- Print one line when starting: `"Building FASTA offset index..."`
- Print one summary line when done: file count, total sequence count, elapsed seconds
- No per-file output — consistent with how other pipeline stages announce themselves

### Claude's Discretion
- Exact error message wording for static_assert and spot-check exit
- OpenMP schedule clause (dynamic,1 is specified in OFFIDX-02)
- Internal data structure for collecting offsets per file (vector<uint64_t> per file, pre-allocated or push_back)
- Where exactly in `createIndex()` to call `buildFastaOffsetIndex()` (between `getObservedAccessions()` and `getTaxonomyOfAccessions()` per OFFIDX-06)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BUILD-01 | CMakeLists.txt defines `_FILE_OFFSET_BITS=64` for UNIX targets | CMake `target_compile_definitions` pattern documented; exact target is `metabuli` in `src/CMakeLists.txt` |
| BUILD-02 | `static_assert(sizeof(off_t) == 8, ...)` compile-time guard | Placement in `IndexCreator.h` after existing `#ifdef OPENMP` block; `<sys/types.h>` include requirement documented |
| OFFIDX-01 | `IndexCreator` stores `vector<vector<uint64_t>> fastaOffsets` field | Field placement in `IndexCreator.h` protected section; uses existing `fastaPaths` field for sizing |
| OFFIDX-02 | `buildFastaOffsetIndex()` parallel pre-pass with OpenMP `schedule(dynamic, 1)` | OpenMP guard pattern `#ifdef OPENMP` already established in `IndexCreator.h`; `schedule(dynamic,1)` matches existing `getObservedAccessions` pattern |
| OFFIDX-03 | Files opened in binary mode (`"rb"`) during pre-pass | `ftello()` returns physical byte positions in binary mode; text mode applies CRLF translation on Windows affecting offsets |
| OFFIDX-04 | Offset recorded before consuming `>` character (pre-read position) | Use `ftello()` before `fgetc()` for each `>` encounter; loop structure documented in Code Examples |
| OFFIDX-05 | Gzip detection via magic bytes (0x1F 0x8B); empty vector as sentinel | Read 2 bytes with `fgetc` before scanning; reopen fresh `FILE*` for scan pass; sentinel design documented |
| OFFIDX-06 | `buildFastaOffsetIndex()` called between `getObservedAccessions()` and `getTaxonomyOfAccessions()` | Call site is `indexReferenceSequences()` at line 486-487 of `IndexCreator.cpp`; `fastaPaths` already populated at that point |
| OFFIDX-07 | Spot-check validation samples ~100 random (fileIdx, ordinal) pairs | `rand()` with no fixed seed; `fseeko()` + `fgetc()` verification; `exit(EXIT_FAILURE)` on mismatch; implementation pattern documented |
</phase_requirements>

## Summary

Phase 2 introduces two independent but coupled changes: (1) a CMake build system fix that ensures `off_t` is 64-bit on all UNIX platforms, and (2) a new `buildFastaOffsetIndex()` function that scans all FASTA files in a parallel pre-pass to populate a `fastaOffsets[fileIdx][ordinal]` lookup table. Neither change touches the k-mer extraction inner loops — those are Phase 3.

The CMake change is a one-liner: `target_compile_definitions(metabuli PRIVATE $<$<NOT:$<PLATFORM_ID:Windows>>:_FILE_OFFSET_BITS=64>)` added to `src/CMakeLists.txt` after the `mmseqs_setup_derived_target(metabuli)` call. The `_FILE_OFFSET_BITS=64` macro is the standard POSIX mechanism on 32-bit Linux to promote `off_t` from 32 to 64 bits, enabling `fseeko`/`ftello` to address files larger than 2 GB. On macOS and Windows, `off_t` is already 64-bit regardless, so the macro is harmless. The `static_assert` acts as a compile-time guarantee that the macro took effect.

The offset index pre-pass follows the existing OpenMP parallelism pattern in `getObservedAccessions()` exactly: one thread per file, `schedule(dynamic, 1)`, results written to per-file vectors using `#pragma omp critical` or thread-local accumulation. The core loop opens each file in `"rb"` mode, reads 2 magic bytes to detect gzip, skips gzip files by leaving `fastaOffsets[i]` empty, then scans byte-by-byte with `fgetc`, recording `ftello()` before consuming each `>` character. After all files are processed, ~100 random (fileIdx, ordinal) pairs are spot-checked via `fseeko` + `fgetc` to confirm each stored offset points to `>`.

**Primary recommendation:** Add `_FILE_OFFSET_BITS=64` via `target_compile_definitions` on the `metabuli` target using a generator expression to exclude Windows. Keep the pre-pass implementation self-contained in `buildFastaOffsetIndex()` with no shared mutable state between threads (each thread writes only to its own `fastaOffsets[i]` vector).

## Standard Stack

### Core
| Component | Version/API | Purpose | Why Standard |
|-----------|-------------|---------|--------------|
| `_FILE_OFFSET_BITS=64` | POSIX.1-2001 | Promote `off_t` to 64-bit on 32-bit Linux | POSIX standard mechanism; glibc honors it at compile time |
| `fseeko` / `ftello` | POSIX.1-2001 | 64-bit file positioning | Drop-in replacement for `fseek`/`ftell` using `off_t` instead of `long` |
| `CMake target_compile_definitions` | CMake ≥3.15 (project already requires this) | Add preprocessor macro to specific target | Modern CMake; avoids polluting global `CMAKE_C_FLAGS` |
| CMake generator expression `$<NOT:$<PLATFORM_ID:Windows>>` | CMake ≥3.15 | Exclude Windows from UNIX-only macro | Idiomatic CMake platform filtering |
| `#pragma omp parallel for schedule(dynamic, 1)` | OpenMP (existing) | Parallelize pre-pass across files | Matches existing pattern in `getObservedAccessions()`; dynamic scheduling handles variable file sizes |
| `rand()` / `srand(time(NULL))` | C stdlib | Random spot-check sampling with no fixed seed | Simple; sufficient for ~100 samples; no fixed seed per CONTEXT decision |

### Supporting
| Component | Version/API | Purpose | When to Use |
|-----------|-------------|---------|-------------|
| `<sys/types.h>` | POSIX | Provides `off_t` type for `static_assert` | Include in `IndexCreator.h` alongside existing includes |
| `<ctime>` | C++ stdlib | `time(nullptr)` for elapsed-time summary | Already included in `IndexCreator.h` |
| `vector<uint64_t>` | C++ stdlib | Per-file offset storage | One `vector<uint64_t>` per file in `fastaOffsets` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `fgetc` byte scan | `fread` 64 KB blocks + `memchr` | 10-20x faster I/O throughput but requires index arithmetic and buffer boundary handling — deferred to v2 PERF-01 |
| `rand()` for spot-check | `<random>` mt19937 | mt19937 is higher quality but overkill for 100-sample correctness check |
| `vector<uint64_t>` per file | flat array + file-size estimate | Vector handles unknown sequence counts without pre-allocation overhead |

**Installation:** No new dependencies. All components are POSIX or already in use.

## Architecture Patterns

### Recommended Project Structure (changes only)

```
src/
├── commons/
│   ├── IndexCreator.h          # +fastaOffsets field, +buildFastaOffsetIndex() decl, +static_assert, +sys/types.h
│   └── IndexCreator.cpp        # +buildFastaOffsetIndex() impl, call site in indexReferenceSequences()
└── CMakeLists.txt              # +target_compile_definitions for _FILE_OFFSET_BITS=64
```

### Pattern 1: CMake Target Compile Definition (UNIX-only)

**What:** Add `_FILE_OFFSET_BITS=64` as a private compile definition on the `metabuli` target, conditioned on non-Windows platforms.

**When to use:** Any POSIX large-file API that requires 64-bit `off_t` on 32-bit Linux.

**Where to add it:** In `src/CMakeLists.txt`, after the `mmseqs_setup_derived_target(metabuli)` call. The `mmseqs-framework` target already propagates `OPENMP=1` and other compile definitions via `mmseqsSetupDerivedTarget` — add `_FILE_OFFSET_BITS=64` directly on `metabuli` as a `PRIVATE` definition because it does not need to propagate to consumers.

```cmake
# Source: src/CMakeLists.txt — after mmseqs_setup_derived_target(metabuli)
target_compile_definitions(metabuli PRIVATE
    $<$<NOT:$<PLATFORM_ID:Windows>>:_FILE_OFFSET_BITS=64>
)
```

### Pattern 2: static_assert for off_t Size

**What:** Compile-time guard that fires if `_FILE_OFFSET_BITS=64` was not honored.

**When to use:** In any TU that uses `fseeko`/`ftello`. Place in `IndexCreator.h` so it covers `IndexCreator.cpp`.

**Where to add it:** After the existing `#ifdef OPENMP` / `#include <omp.h>` block in `IndexCreator.h`, before the class definition. Requires `<sys/types.h>` (for `off_t`) to be included.

```cpp
// Source: IndexCreator.h — after existing includes, before class IndexCreator
#include <sys/types.h>   // off_t
static_assert(sizeof(off_t) == 8, "off_t must be 64-bit: compile with _FILE_OFFSET_BITS=64 on 32-bit Linux");
```

### Pattern 3: IndexCreator Field Addition

**What:** Add `fastaOffsets` as a protected field in `IndexCreator`.

**Where:** In the `IndexCreator` class protected section in `IndexCreator.h`, near the existing `fastaPaths` field.

```cpp
// Source: IndexCreator.h protected section — near fastaPaths declaration (line 138)
vector<string> fastaPaths;
vector<vector<uint64_t>> fastaOffsets;   // fastaOffsets[fileIdx][ordinal] = byte offset of '>'
```

### Pattern 4: buildFastaOffsetIndex() — Parallel Pre-Pass

**What:** One OpenMP thread per file. Each thread opens its file in binary mode, detects gzip via magic bytes, skips gzip files (leaves vector empty), then scans byte-by-byte recording `ftello()` before each `>`.

**Key invariant:** `fastaOffsets[i]` is empty iff file `i` is gzip (or failed to open). Non-empty means every `ordinal` in range `[0, fastaOffsets[i].size())` is a valid index.

**When to call it:** In `indexReferenceSequences()`, after `getObservedAccessions()` populates `fastaPaths`, and before `getTaxonomyOfAccessions()`.

```cpp
// Source: IndexCreator.cpp — declaration in IndexCreator.h
void IndexCreator::buildFastaOffsetIndex() {
    cout << "Building FASTA offset index..." << endl;
    time_t start = time(nullptr);

    fastaOffsets.resize(fastaPaths.size());  // resize outer vector once

    #ifdef OPENMP
    #pragma omp parallel for schedule(dynamic, 1) \
        default(none) shared(cout)
    #endif
    for (size_t i = 0; i < fastaPaths.size(); ++i) {
        FILE* fp = fopen(fastaPaths[i].c_str(), "rb");
        if (!fp) {
            // leave fastaOffsets[i] empty — treated as gzip/unavailable sentinel
            continue;
        }

        // Gzip magic-byte detection: 0x1F 0x8B
        int b0 = fgetc(fp);
        int b1 = fgetc(fp);
        if (b0 == 0x1F && b1 == 0x8B) {
            // Gzip file — skip, leave vector empty as fallback sentinel
            fclose(fp);
            continue;
        }

        // Rewind and scan for '>' headers
        rewind(fp);
        vector<uint64_t> localOffsets;
        int c;
        while ((c = fgetc(fp)) != EOF) {
            if (c == '>') {
                // Record position of '>' (ftello called after fgetc advances past it,
                // so use the position BEFORE the fgetc call)
                // Correct approach: record BEFORE consuming '>'
                // See Code Examples §Offset Recording for the correct pattern
            }
        }
        fclose(fp);
        fastaOffsets[i] = std::move(localOffsets);
    }

    size_t totalSeqs = 0;
    for (const auto& v : fastaOffsets) totalSeqs += v.size();
    time_t elapsed = time(nullptr) - start;
    cout << "FASTA offset index built: " << fastaPaths.size() << " files, "
         << totalSeqs << " sequences, " << elapsed << " s" << endl;
}
```

**Note:** The pseudocode above shows structure; the correct offset-before-fgetc pattern is in Code Examples §Offset Recording.

### Pattern 5: Spot-Check Validation

**What:** After the pre-pass, sample ~100 random (fileIdx, ordinal) pairs. For each, `fseeko` to the stored offset and confirm the character at that position is `>`.

**Exit behavior:** `exit(EXIT_FAILURE)` with `cerr` message if any check fails — consistent with `calculateBufferSize()` and other fatal errors in the codebase.

```cpp
// Source: IndexCreator.cpp — called at end of buildFastaOffsetIndex()
// Build a list of valid (fileIdx, ordinal) pairs with non-empty offset vectors
vector<pair<size_t,size_t>> validPairs;
for (size_t i = 0; i < fastaOffsets.size(); ++i) {
    for (size_t j = 0; j < fastaOffsets[i].size(); ++j) {
        validPairs.emplace_back(i, j);
    }
}
if (validPairs.empty()) return;  // all gzip, nothing to check

srand(static_cast<unsigned>(time(nullptr)));  // no fixed seed per CONTEXT decision
size_t checkCount = std::min((size_t)100, validPairs.size());
for (size_t k = 0; k < checkCount; ++k) {
    size_t idx = static_cast<size_t>(rand()) % validPairs.size();
    auto [fi, ord] = validPairs[idx];
    FILE* fp = fopen(fastaPaths[fi].c_str(), "rb");
    if (!fp) {
        cerr << "Spot-check: cannot open " << fastaPaths[fi] << endl;
        exit(EXIT_FAILURE);
    }
    if (fseeko(fp, static_cast<off_t>(fastaOffsets[fi][ord]), SEEK_SET) != 0) {
        cerr << "Spot-check: fseeko failed for file " << fi << " ordinal " << ord << endl;
        fclose(fp);
        exit(EXIT_FAILURE);
    }
    int c = fgetc(fp);
    fclose(fp);
    if (c != '>') {
        cerr << "Spot-check FAILED: offset " << fastaOffsets[fi][ord]
             << " in " << fastaPaths[fi]
             << " points to '" << (char)c << "', expected '>'" << endl;
        exit(EXIT_FAILURE);
    }
}
```

### Pattern 6: Call Site in indexReferenceSequences()

**What:** Insert `buildFastaOffsetIndex()` call between `getObservedAccessions()` and `getTaxonomyOfAccessions()` in `indexReferenceSequences()`.

**Why this location:** `fastaPaths` is populated by `getObservedAccessions()` (line 484 of `IndexCreator.cpp`). The offset index must be built before Phase 3 uses it in `fillTargetKmerBuffer()`/`extractKmerFromSixFrames()`. Placing it before `getTaxonomyOfAccessions()` keeps the logical grouping of "preparation" steps together.

```cpp
// Source: IndexCreator.cpp — indexReferenceSequences(), after getObservedAccessions() call
getObservedAccessions(fnaListFileName, observedAccessionsVec, accession2index);
cout << "Number of observed accessions: " << observedAccessionsVec.size() << endl;

buildFastaOffsetIndex();  // NEW: populate fastaOffsets[fileIdx][ordinal]

getTaxonomyOfAccessions(observedAccessionsVec, accession2index, acc2taxidFileName);
```

### Anti-Patterns to Avoid

- **`ftello()` called AFTER `fgetc()`:** Records position AFTER the `>` character, so `fseeko` to that offset would land on the first character of the header name, not `>`. Must call `ftello()` before `fgetc()`.
- **Shared `FILE*` across threads:** Opening one `FILE*` per file and sharing it across OpenMP threads causes data races on the internal file position. Each thread must open its own `FILE*`.
- **`fseek`/`ftell` instead of `fseeko`/`ftello`:** `fseek` uses `long` offset (32-bit on most 32-bit Linux), silently truncating offsets > 2 GB. Always use `fseeko`/`ftello`.
- **Omitting `rewind()` after magic-byte check:** After reading 2 bytes for magic detection, file position is at byte 2. Must `rewind(fp)` before the scanning loop or the first two bytes of the file are skipped.
- **Using `static` schedule instead of `dynamic`:** FASTA files vary widely in size. Static scheduling assigns equal file counts per thread; dynamic adapts to actual work and avoids one thread finishing 10 large files while another idles. OFFIDX-02 specifies `schedule(dynamic, 1)`.
- **Adding `_FILE_OFFSET_BITS=64` globally via `CMAKE_C_FLAGS`:** This pollutes all targets including the mmseqs-framework and third-party libs that already handle large files. Use `target_compile_definitions(metabuli PRIVATE ...)`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 64-bit file offset type | Custom `int64_t` offset arithmetic | `off_t` + `fseeko`/`ftello` with `_FILE_OFFSET_BITS=64` | `off_t` is exactly what POSIX defines for file offsets; hand-rolled arithmetic misses the type alias on all platforms |
| Gzip detection | Extension checking (`.gz` suffix) | Magic bytes `0x1F 0x8B` | Files can be renamed; extension check misses renamed gzip files and gives false positives for non-gzip `.gz` paths |
| Parallel file scan | Manual pthread pool | `#pragma omp parallel for schedule(dynamic,1)` | OpenMP already present and guarded in `IndexCreator`; introducing pthreads adds thread lifecycle complexity for no gain |

**Key insight:** The `_FILE_OFFSET_BITS=64` + `fseeko`/`ftello` combination is the standard, portable solution for large file support on UNIX. It requires no new libraries — just the right compile-time macro and the right function variants.

## Common Pitfalls

### Pitfall 1: Off-By-One in Offset Recording (Pre/Post fgetc)

**What goes wrong:** If `ftello()` is called AFTER `fgetc()`, the stored offset points to the byte immediately following `>` (the first character of the header name). On seek, `fgetc()` reads the header name's first char, not `>`. Spot-check fails; Phase 3 seeks to wrong positions.

**Why it happens:** Natural loop structure reads the character first, then records position. The CONTEXT decision explicitly specifies "position recorded before consuming the character."

**How to avoid:** Use the "save-then-read" pattern:
```cpp
off_t pos = ftello(fp);   // record position BEFORE consuming the character
int c = fgetc(fp);        // now consume it
if (c == '>') {
    localOffsets.push_back(static_cast<uint64_t>(pos));
}
```

**Warning signs:** Spot-check failures where the character at the stored offset is the first letter of a FASTA sequence name (A/T/G/C typically) rather than `>`.

### Pitfall 2: Missing rewind() After Magic Byte Check

**What goes wrong:** After reading 2 bytes to check gzip magic, `fp` is positioned at byte 2. The scan loop starts from byte 2, missing any `>` in the first two bytes of the file (which would be extremely unusual for a FASTA file but is still incorrect behavior).

**Why it happens:** Magic byte check is done with two `fgetc()` calls that advance the file pointer.

**How to avoid:** Call `rewind(fp)` immediately after the magic byte check, before the scanning loop.

**Warning signs:** For a FASTA file where a sequence header starts at byte 0, the ordinal=0 offset would be missing or wrong.

### Pitfall 3: CMake OPENMP vs _FILE_OFFSET_BITS Definition Scope

**What goes wrong:** Adding `_FILE_OFFSET_BITS=64` to `CMAKE_C_FLAGS` or `CMAKE_CXX_FLAGS` globally propagates it to mmseqs-framework, prodigal, fasta_validator, and other submodules. These already handle large files in their own way; forced redefinition can cause ODR issues.

**Why it happens:** Global flags are the "easy" path when unfamiliar with CMake target-scoped definitions.

**How to avoid:** Use `target_compile_definitions(metabuli PRIVATE ...)` — `PRIVATE` means the definition is only visible when compiling `metabuli`'s own sources, not propagated to targets linked against `metabuli`.

**Warning signs:** Build errors in mmseqs or prodigal sources about `_FILE_OFFSET_BITS` redefinition.

### Pitfall 4: OpenMP Thread Safety — fastaOffsets Write Contention

**What goes wrong:** If multiple threads write to `fastaOffsets` via `push_back` on the same outer vector index, or resize the outer vector inside the parallel region, undefined behavior results.

**Why it happens:** `fastaOffsets.resize(fastaPaths.size())` creates the inner vectors as empty. Each thread writes only to `fastaOffsets[i]` where `i` is its loop index — that index is unique per thread in `schedule(dynamic,1)`. No contention exists as long as the resize happens before the parallel region.

**How to avoid:** Call `fastaOffsets.resize(fastaPaths.size())` once before `#pragma omp parallel for`. Each thread accesses only its own `fastaOffsets[i]`.

**Warning signs:** Crashes or corrupted offset vectors when running with multiple threads.

### Pitfall 5: _FILE_OFFSET_BITS=64 Must Be Set Before Any System Headers

**What goes wrong:** If any included header includes `<stdio.h>` or `<sys/types.h>` before `_FILE_OFFSET_BITS=64` is defined, the type alias for `off_t` is already locked in as 32-bit for that translation unit.

**Why it happens:** The macro must be visible before glibc feature test macros evaluate it.

**How to avoid:** CMake `target_compile_definitions` passes the flag as a `-D` compile flag, which is applied before any source file includes are processed. This is the correct mechanism — no manual `#define` in source files is needed.

**Warning signs:** `static_assert(sizeof(off_t) == 8)` fires on a 32-bit Linux build even after adding the CMake definition.

## Code Examples

### Offset Recording (Correct Pattern — ftello Before fgetc)

```cpp
// Source: POSIX fseeko/ftello specification + OFFIDX-04 requirement
// Called inside the scanning loop of buildFastaOffsetIndex()
int c;
while (true) {
    off_t pos = ftello(fp);          // record position BEFORE consuming
    c = fgetc(fp);
    if (c == EOF) break;
    if (c == '>') {
        localOffsets.push_back(static_cast<uint64_t>(pos));
    }
}
```

### Gzip Detection (Inline Magic Bytes)

```cpp
// Source: RFC 1952 (gzip format) — magic bytes 0x1F 0x8B
// Called at start of per-file processing in buildFastaOffsetIndex()
int b0 = fgetc(fp);
int b1 = fgetc(fp);
if (b0 == 0x1F && b1 == 0x8B) {
    fclose(fp);
    continue;   // leave fastaOffsets[i] empty as gzip sentinel
}
rewind(fp);   // reset before scan — CRITICAL
```

### CMake _FILE_OFFSET_BITS Definition

```cmake
# Source: CMake documentation — generator expression platform filter
# In src/CMakeLists.txt, after mmseqs_setup_derived_target(metabuli)
target_compile_definitions(metabuli PRIVATE
    $<$<NOT:$<PLATFORM_ID:Windows>>:_FILE_OFFSET_BITS=64>
)
```

### static_assert Placement in IndexCreator.h

```cpp
// Source: C++17 static_assert — in IndexCreator.h after includes
#include <sys/types.h>   // off_t
static_assert(sizeof(off_t) == 8,
    "off_t must be 64-bit — compile with _FILE_OFFSET_BITS=64 on 32-bit Linux");
```

### buildFastaOffsetIndex() Signature and Call Site

```cpp
// Source: IndexCreator.h — protected section, alongside other protected methods
void buildFastaOffsetIndex();

// Source: IndexCreator.cpp — indexReferenceSequences() call site
getObservedAccessions(fnaListFileName, observedAccessionsVec, accession2index);
cout << "Number of observed accessions: " << observedAccessionsVec.size() << endl;
buildFastaOffsetIndex();
getTaxonomyOfAccessions(observedAccessionsVec, accession2index, acc2taxidFileName);
```

### Fatal Error Pattern (Existing Codebase Standard)

```cpp
// Source: IndexCreator.cpp calculateBufferSize() (line 235-238) — established pattern
cerr << "Spot-check FAILED: offset " << fastaOffsets[fi][ord]
     << " in " << fastaPaths[fi]
     << " points to '" << (char)c << "', expected '>'" << endl;
exit(EXIT_FAILURE);
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `fseek`/`ftell` (32-bit `long` offset) | `fseeko`/`ftello` (64-bit `off_t`) | POSIX.1-2001 LFS extension | Enables seeking past 2 GB in FASTA files; required for core_nt-scale builds |
| Global `add_definitions(-D_FILE_OFFSET_BITS=64)` | `target_compile_definitions(TARGET PRIVATE ...)` | CMake 2.8+ (target-based) | Scoped to specific target; no pollution of third-party submodule builds |

**Not deprecated or changed in this phase:**
- KSeqWrapper sequential scan (still used in `getObservedAccessions()` — unchanged)
- `extractKmerFromSixFrames()` / `fillTargetKmerBuffer()` inner loops (Phase 3)

## Open Questions

1. **`par.makeLibrary` code path in indexReferenceSequences()**
   - What we know: When `par.makeLibrary` is true, `getObservedAccessions()` is called with the result of `addToLibrary()`, which rewrites files into per-species FASTA files before populating `fastaPaths`. The call to `buildFastaOffsetIndex()` must happen after `fastaPaths` is populated in both branches.
   - What's unclear: Whether the `addToLibrary()` code path is exercised by the regression test (it is not — the test uses the non-library path). The offset index pre-pass should still be called in the `makeLibrary` branch for completeness.
   - Recommendation: Place the `buildFastaOffsetIndex()` call after the `if/else` block (after `fastaPaths` is populated regardless of which branch ran) to handle both cases.

2. **Thread count for pre-pass vs. k-mer extraction**
   - What we know: `omp_set_num_threads(par.threads)` is called in `createIndex()` (line 341) before k-mer extraction. The pre-pass in `indexReferenceSequences()` does not explicitly set thread count.
   - What's unclear: Whether OpenMP thread count is inherited from a previous `omp_set_num_threads()` call at that point in the call stack.
   - Recommendation: Add `#ifdef OPENMP \n omp_set_num_threads(par.threads); \n #endif` at the top of `buildFastaOffsetIndex()` to be explicit. This mirrors the pattern used in `createIndex()`.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash shell script (existing) |
| Config file | none — standalone script |
| Quick run command | `./test/regression_fasta_access.sh ./build/metabuli` |
| Full suite command | `./test/regression_fasta_access.sh ./build/metabuli` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BUILD-01 | `_FILE_OFFSET_BITS=64` defined → `off_t` is 64-bit | compile | `cmake --build build 2>&1` (build succeeds without error) | ✅ CMake build |
| BUILD-02 | `static_assert(sizeof(off_t) == 8)` fires on misconfigured builds | compile | N/A — compile-time; build success confirms guard present | ✅ compile-time |
| OFFIDX-01 | `fastaOffsets` field exists in `IndexCreator` | smoke (regression) | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing |
| OFFIDX-02 | Pre-pass runs in parallel across files | smoke (regression) | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing |
| OFFIDX-03 | Binary mode open ensures correct byte positions | smoke (regression) | `./test/regression_fasta_access.sh ./build/metabuli` — spot-check validates offsets | ✅ existing |
| OFFIDX-04 | Offset records `>` position (pre-read) | smoke (spot-check) | `./test/regression_fasta_access.sh ./build/metabuli` — spot-check inside build | ✅ existing |
| OFFIDX-05 | Gzip sentinel: empty vector for gzip files | manual-only | No gzip FASTA in test corpus; can verify with `file test/data/*.fasta` | N/A — manual |
| OFFIDX-06 | `buildFastaOffsetIndex()` called in correct pipeline position | smoke (regression) | `./test/regression_fasta_access.sh ./build/metabuli` — build pipeline runs to completion | ✅ existing |
| OFFIDX-07 | Spot-check validates 100 random offset pairs | smoke (build stderr) | `./test/regression_fasta_access.sh ./build/metabuli` — would exit non-zero if spot-check fails | ✅ existing |

**Note on OFFIDX-05:** The test corpus contains only uncompressed FASTA files (`seq1.fasta`, `seq2.fasta`, `seq3.fasta`). Gzip detection and the empty-vector sentinel path cannot be exercised by the existing regression test. This is acceptable for Phase 2 — the code path is simple (2-byte read + `continue`), and manual testing with a renamed `.gz` file can confirm the behavior if needed.

### Sampling Rate
- **Per task commit:** `./test/regression_fasta_access.sh ./build/metabuli`
- **Per wave merge:** `./test/regression_fasta_access.sh ./build/metabuli`
- **Phase gate:** Regression script passes (PASS output, exit 0) before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements that can be automatically tested. The regression script from Phase 1 (`test/regression_fasta_access.sh`) is sufficient: it runs the build pipeline end-to-end, invokes `validatedb`, and byte-compares outputs. Since `buildFastaOffsetIndex()` runs inside the build pipeline and its spot-check calls `exit(EXIT_FAILURE)` on failure, any offset correctness issue will cause the binary to exit non-zero before writing output files, causing the regression script to fail at the build step.

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection — `src/commons/IndexCreator.h`, `src/commons/IndexCreator.cpp`, `src/CMakeLists.txt`, `src/commons/CMakeLists.txt`, root `CMakeLists.txt`
- `lib/mmseqs/src/CMakeLists.txt` — verified how `OPENMP=1` is set via `target_compile_definitions(mmseqs-framework PUBLIC -DOPENMP=1)` and propagated to `metabuli` via `mmseqs_setup_derived_target`
- `lib/mmseqs/cmake/MMseqsSetupDerivedTarget.cmake` — verified `COMPILE_DEFINITIONS` propagation mechanism
- `src/commons/common.h` — verified `fseek`/`fread`/`FILE*` patterns (existing `ReadBuffer`, `WriteBuffer` templates)

### Secondary (MEDIUM confidence)
- POSIX.1-2001 LFS specification — `_FILE_OFFSET_BITS=64` behavior on glibc; `fseeko`/`ftello` semantics
- RFC 1952 — gzip magic bytes `0x1F 0x8B`
- CMake 3.15 documentation — `target_compile_definitions`, generator expressions `$<PLATFORM_ID:...>`

### Tertiary (LOW confidence)
- None — all findings are verified against codebase or POSIX/RFC standards

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified directly from codebase inspection and POSIX standard
- Architecture: HIGH — all integration points confirmed by reading actual source files; no assumptions made
- Pitfalls: HIGH — derived from code analysis (existing patterns + known POSIX LFS gotchas)
- CMake pattern: HIGH — verified by reading `MMseqsSetupDerivedTarget.cmake` and how `OPENMP` is already handled

**Research date:** 2026-03-05
**Valid until:** 2026-09-05 (stable — all findings based on codebase internals and POSIX standard, not fast-moving ecosystem)
