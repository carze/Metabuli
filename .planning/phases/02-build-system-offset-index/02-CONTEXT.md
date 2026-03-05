# Phase 2: Build System + Offset Index - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `_FILE_OFFSET_BITS=64` to the CMake build system and implement `buildFastaOffsetIndex()` — a parallel pre-pass that scans all FASTA files once and populates `fastaOffsets[fileIdx][ordinal]` with byte offsets of `>` header characters. Includes gzip detection, spot-check validation, and wiring into the build pipeline. Does NOT modify the inner loops (`extractKmerFromSixFrames`, `fillTargetKmerBuffer`) — those are Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Pre-pass I/O strategy
- `fgetc` per byte — simple, spec-compliant. The pre-pass runs once; 30-min wall time at 500 MB/s is acceptable
- Open/close fresh FILE* per file per thread — no shared state, simplest correct implementation
- Gzip detection via magic bytes (0x1F 0x8B) inline inside `buildFastaOffsetIndex()`, not via extension-based utilities — catches renamed .gz files, self-contained

### static_assert placement
- `static_assert(sizeof(off_t) == 8, "...")` goes directly in `IndexCreator.h` — guards the TU that uses `fseeko`/`ftello`
- Unconditional (no platform ifdef) — always passes on macOS/Windows (off_t already 64-bit), catches misconfigured 32-bit Linux builds

### Spot-check failure behavior
- Hard `exit()` with clear error message if any sampled offset doesn't point to `>` — consistent with all other fatal errors in the codebase; corrupt index is a bug not a recoverable condition
- ~100 pairs total, fixed count regardless of database size — fast, deterministic overhead
- Truly random sample each build (no fixed seed) — prevents bugs from hiding behind a stable sample pattern

### Progress output
- Print one line when starting: `"Building FASTA offset index..."`
- Print one summary line when done: file count, total sequence count, elapsed seconds
- No per-file output — consistent with how other pipeline stages announce themselves

### Claude's Discretion
- Exact error message wording for static_assert and spot-check exit
- OpenMP schedule clause (dynamic,1 is specified in OFFIDX-02)
- Internal data structure for collecting offsets per file (vector<uint64_t> per file, pre-allocated or push_back)
- Where exactly in `createIndex()` to call `buildFastaOffsetIndex()` (between `getObservedAccessions()` and `getTaxonomyOfAccessions()` per OFFIDX-06)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `fastaPaths` field (vector<string>) already in `IndexCreator` — the list of FASTA files to scan is available
- `#ifdef OPENMP / #include <omp.h>` pattern already in `IndexCreator.h` — parallel pre-pass follows the same guard
- `Debug(Debug::ERROR)` logging macro — use for error output in spot-check failure path
- `fgetc`/FILE* I/O patterns already used in KSeqWrapper — same stdio approach

### Established Patterns
- Fatal errors: `exit(EXIT_FAILURE)` with `cerr` or `Debug(Debug::ERROR)` output — no exceptions
- Progress output: `std::cout` with direct string + stats, e.g. `cout << "..." << count << endl`
- OpenMP parallelism: `#pragma omp parallel for schedule(dynamic, 1)` with `#ifdef OPENMP` guard
- No automated formatter — 4-space indent, opening braces on same line

### Integration Points
- `IndexCreator.h`: Add `vector<vector<uint64_t>> fastaOffsets` field + `buildFastaOffsetIndex()` declaration
- `IndexCreator.cpp`: Implement `buildFastaOffsetIndex()`; call it from `createIndex()` between `getObservedAccessions()` and `getTaxonomyOfAccessions()`
- `src/CMakeLists.txt` or `src/commons/CMakeLists.txt`: Add `_FILE_OFFSET_BITS=64` for UNIX targets via `target_compile_definitions`

</code_context>

<specifics>
## Specific Ideas

No specific references — open to standard approaches within the decisions above.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-build-system-offset-index*
*Context gathered: 2026-03-05*
