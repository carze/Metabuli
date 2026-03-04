# Project Research Summary

**Project:** Metabuli FASTA Random Access Refactor
**Domain:** C++ bioinformatics pipeline I/O refactor with regression testing
**Researched:** 2026-03-04
**Confidence:** HIGH

## Executive Summary

Metabuli's database build pipeline currently scans each FASTA file sequentially from byte 0 to find every target sequence, even when only a handful of sequences from a file are needed in a given batch. At core_nt scale (2,382 files, ~900 GB total), this produces catastrophic I/O amplification. The correct solution is a two-phase approach: first, a parallel pre-pass that builds an in-memory byte-offset index (`vector<vector<uint64_t>>`) mapping each sequence ordinal to its `>` character position; then, modified inner loops that `fseeko` directly to each needed sequence instead of scanning from the start. The recommended I/O primitive is `fseeko` + thread-local `FILE*` handles — not `mmap` (900 GB VAS exhaustion) and not `pread` (Windows portability gap). This approach fits the existing `FILE*` codebase, is cross-platform (Linux/macOS/Windows Cygwin), and costs ~57 seconds for the pre-pass with 32 threads, negligible against a 10-12 hour total build.

The refactor is a localized change: only `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` in `IndexCreator.cpp` are modified. The k-mer computation, LCA filtering, and write logic are untouched. This constraint makes correctness verification tractable — byte-identical `diffIdx`, `info`, and `split` output files compared against the unmodified sequential build are a sufficient and rigorous regression gate. Functional (classification-level) equivalence alone is not sufficient because two databases can differ in k-mer content for untested organisms while producing identical TSV output on a training query set.

The primary risks are all in the pre-pass and per-batch FILE* management: using `fseek` instead of `fseeko` (silent 32-bit truncation on any file >2 GB), sharing `FILE*` across OpenMP threads (silent data races), opening files in text mode on Windows (CRLF corruption of offsets), and ordinal mismatch between the new pre-pass and the existing `getObservedAccessions()` scan (silent wrong-sequence delivery). All six critical pitfalls have well-understood preventions and must be addressed before any performance benchmarking.

## Key Findings

### Recommended Stack

The entire implementation uses only POSIX C99 APIs that already exist in the codebase: `fseeko`/`ftello` for 64-bit file positioning, `fopen`/`fclose`/`fgets` for file I/O, and OpenMP `#pragma omp parallel for schedule(dynamic, 1)` for the pre-pass. No new libraries are introduced. The only build system change required is adding `_FILE_OFFSET_BITS=64` to `CMakeLists.txt` for Linux to ensure `off_t` is 64-bit — without this, `fseeko` silently truncates offsets above 2 GB on 32-bit Linux. All offsets are stored as `uint64_t` (not `off_t`, which varies by platform) and cast to `(off_t)` only at the `fseeko` call site.

**Core technologies:**
- `fseeko` / `ftello` + thread-local `FILE*`: 64-bit random file access — fits existing FILE* codebase, cross-platform on Linux/macOS/Windows Cygwin
- `vector<vector<uint64_t>> fastaOffsets`: in-memory offset index — ~160-380 MB at core_nt scale, no invalidation complexity of on-disk persistence
- `OpenMP schedule(dynamic, 1)`: parallel pre-pass over 2,382 files — embarrassingly parallel, dynamic scheduling handles file size variance (10 MB to 2 GB)
- `_FILE_OFFSET_BITS=64` in CMakeLists.txt: ensures 64-bit `off_t` on Linux — belt-and-suspenders protection against 2 GB truncation

**What was explicitly ruled out:**
- `mmap`: 900 GB VAS exhaustion at core_nt scale, Windows portability complexity, no performance advantage over fseeko for whole-sequence reads
- `pread`: atomic seek+read, but not available on native MSVC; bypasses stdio buffering
- `fseek` (with `long`): 32-bit on MSVC 64-bit and 32-bit Linux without `_FILE_OFFSET_BITS=64` — already present as a latent bug in `KmerMatcher.cpp`

### Expected Features

The "features" for this refactor are regression testing capabilities that prove correctness before and after the I/O change. The primary deliverable is a regression test harness, not new user-facing functionality.

**Must have (table stakes):**
- Byte-identical `diffIdx` binary comparison — any divergence in delivered sequence bytes produces different k-mers; `cmp` is the correct tool
- Byte-identical `info` binary comparison — TaxID assignments are position-sensitive; ordinal mismatch silently corrupts the taxonomy layer
- Byte-identical `split` binary comparison — entirely derived from `diffIdx`/`info`; if both are identical, `split` is identical automatically
- `--threads 1` determinism — multi-thread OMP scheduling is non-deterministic across buffer sizes; single-thread builds eliminate this variable for regression comparison
- Small FASTA test corpus in `test/data/` — running core_nt in CI is not feasible; curated mini-corpus (~20 MB, 3 files, ~10 accessions) must exercise all critical code paths
- `validateDatabase` pass — existing Metabuli tool checks k-mer count vs. info entry count; free consistency check

**Should have (strengthen confidence):**
- Classification equivalence test — run `metabuli classify` against both old/new DBs; independent sanity check for reviewers
- K-mer count per-species comparison — parse `info` (raw `uint32_t` array) and compare per-taxID counts
- CDS-annotated path coverage — include one species with Prodigal CDS annotation to exercise `fillTargetKmerBuffer` code path, not just `extractKmerFromSixFrames`

**Defer (v2+):**
- Full core_nt regression run — valuable as manual validation before major releases, not CI-feasible
- On-disk `.fao` offset cache — defer until `updateDB` workflow justifies the invalidation complexity
- `pread`-based fast path — Linux-only optimization; defer until fseeko correctness is confirmed and profiling shows fopen/fclose overhead

### Architecture Approach

The refactor inserts one new function, `buildFastaOffsetIndex()`, between `getObservedAccessions()` and `getTaxonomyOfAccessions()` in IndexCreator's build pipeline. This function performs a parallel scan of all FASTA files and populates `fastaOffsets[fileIdx][ordinal]` with the byte offset of each `>` character. The modified `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` then sort each batch's orders by ascending file offset (to produce forward-only seeks that benefit from OS read-ahead) and use `fseeko` + per-batch `FILE*` handles instead of the current KSeqWrapper sequential scan. Gzip files are detected by magic bytes and silently fall back to the existing KSeq sequential path.

**Major components:**
1. `buildFastaOffsetIndex()` (new) — parallel pre-pass over all `fastaPaths`, populates `fastaOffsets`; called once after `getObservedAccessions()`
2. `fastaOffsets` member (new) — `vector<vector<uint64_t>>` in `IndexCreator.h`; read-only after build, consumed by both inner loops
3. `extractKmerFromSixFrames()` (modified) — replaces KSeqWrapper sequential scan with fseeko random access; gzip fallback preserved
4. `fillTargetKmerBuffer()` (modified) — same pattern as `extractKmerFromSixFrames`; CDS-annotated code path

**Key architectural decisions:**
- Per-batch `fopen`/`fclose` (not per-thread cached handles) — multiple threads may process different batches from the same file concurrently; per-batch avoids mutex serialization; OS page cache ensures no physical re-read
- Sort orders by byte offset before seeking — `getAccessionBatches()` groups by species, not file position; sorting enables forward-only seeks and OS read-ahead
- Store offset of `>` (not first base) — allows existing KSeq-derived header parsing to work after seeking; Metabuli does not need sub-sequence access (unlike htslib FAI)

### Critical Pitfalls

1. **`fseek` 32-bit truncation** — The existing `KmerMatcher.cpp` already uses `fseek` with `long`, which silently truncates offsets above 2 GB on MSVC 64-bit and 32-bit Linux. Do not copy this pattern. Add `_FILE_OFFSET_BITS=64` to CMakeLists.txt, add `static_assert(sizeof(off_t) == 8, ...)`, use `fseeko` exclusively, store offsets as `uint64_t`.

2. **Shared `FILE*` across threads** — glibc's per-FILE* lock protects individual calls, not seek+read pairs. Thread A seeks, Thread B seeks, Thread A reads B's position. Result: intermittent wrong sequences, no crash, extremely hard to debug. Prevention: each thread opens its own `FILE*` per batch.

3. **Text mode file open on Windows** — `fopen(path, "r")` on Windows translates `\r\n` to `\n`, making `ftello` offsets inconsistent with physical byte positions. The stored offset points to the wrong location after a seek. Always use `"rb"`, strip `\r` explicitly with `strlen`-based trim.

4. **Off-by-one at `>` character** — Recording `ftello` AFTER consuming `>` (e.g., via `fgetc`) stores the offset of the second character, not the `>` itself. After seeking, the header line is read starting from the second character, truncating the accession name. Record position BEFORE reading.

5. **Ordinal mismatch with `getObservedAccessions()`** — If the pre-pass counts sequences using different logic than `getObservedAccessions()` (which uses KSeqWrapper with BOM handling, CRLF normalization, blank line skipping), ordinals diverge silently and wrong sequences are delivered to k-mer extraction. This produces a valid-looking but incorrect database — the most dangerous failure mode. Best prevention: run the offset pre-pass during the same file scan as accession discovery.

6. **Gzip files produce garbage offsets** — `fopen` on a `.gz` file returns compressed bytes; the pre-pass finds random `0x3E` bytes and produces wrong ordinal-to-offset mappings. Detect gzip by magic bytes (`0x1F 0x8B`), leave `fastaOffsets[i]` empty as a sentinel, fall back to KSeq sequential path for that file.

## Implications for Roadmap

Based on the combined research, this project decomposes cleanly into three sequential phases. Phase ordering is driven by correctness dependencies: the offset index is a prerequisite for the modified inner loops; the regression harness must be built before the refactor can be validated; and performance optimization is only meaningful once correctness is confirmed.

### Phase 1: Build System + Offset Index Infrastructure

**Rationale:** The CMake change (`_FILE_OFFSET_BITS=64`) and the `fastaOffsets` data structure are prerequisites for all subsequent work. The `static_assert` catches misconfigured builds immediately. `buildFastaOffsetIndex()` can be implemented and tested in isolation before any inner loop changes — call it, dump a sample of offsets, manually verify with a hex editor.

**Delivers:** `_FILE_OFFSET_BITS=64` in CMakeLists.txt; `static_assert` on `sizeof(off_t)`; `fastaOffsets` member in `IndexCreator.h`; `buildFastaOffsetIndex()` function called after `getObservedAccessions()`; gzip magic-byte detection and empty-sentinel fallback

**Addresses:** fseek 32-bit truncation (pitfall 1), gzip garbage offsets (pitfall 6), BOM handling (pitfall 10), blank-line ordinal drift (pitfall 8)

**Avoids:** Modifying any k-mer extraction code until the index is verified correct

### Phase 2: Regression Test Harness

**Rationale:** Before modifying `extractKmerFromSixFrames()` or `fillTargetKmerBuffer()`, establish the byte-identical regression gate. The harness must exist and pass with the unmodified sequential code first (green baseline), then detect any divergence introduced by the refactor. Building the harness after the refactor means debugging both the refactor and the harness simultaneously.

**Delivers:** Mini FASTA test corpus in `test/data/` (~20 MB, 3 files, 10 accessions, exercising all required code paths); `test/regression_fasta_access.sh` script; `validateDatabase` call on both DBs; CI job running regression on every PR to the refactor branch; stored SHA-256 expected hashes

**Addresses:** Byte-identical diffIdx/info/split comparison (all table stakes from FEATURES.md); coverage of multi-file batches, buffer flushes, and low-complexity masking

**Avoids:** Relying on classification-level equivalence as the primary gate (anti-feature from FEATURES.md)

### Phase 3: Inner Loop Refactor

**Rationale:** With the offset index verified and the regression harness green, the inner loop changes are straightforward and fully gated. `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` are modified in parallel (same pattern). The regression script is the acceptance criterion.

**Delivers:** Modified `extractKmerFromSixFrames()` using fseeko random access with per-batch FILE* handles; modified `fillTargetKmerBuffer()` with same pattern; batch orders sorted by file offset for forward-only seeks; gzip fallback to KSeq sequential path; green regression script on both modified functions

**Addresses:** Shared FILE* thread race (pitfall 2), text mode CRLF corruption (pitfall 3), off-by-one at `>` (pitfall 4), ordinal mismatch (pitfall 5), multi-line sequence accumulation (pitfall 7)

**Uses:** `fseeko` + thread-local `FILE*` (STACK.md Pattern 1), per-batch open/close (ARCHITECTURE.md FILE* Lifecycle section)

### Phase 4: Validation and Optional Enhancements

**Rationale:** After the refactor passes the binary regression gate, add the secondary confidence-builders and performance optimizations if warranted by profiling.

**Delivers:** Classification equivalence test (run classify on small query set against both DBs); k-mer count per-species comparison (parse `info` uint32_t array); CDS-annotated path test using Prodigal fixture; optionally, fread/memchr block-scan optimization for pre-pass if fgetc throughput is a measured bottleneck

**Addresses:** Should-have features from FEATURES.md; pitfall 9 (fgetc throughput) if profiling warrants it

### Phase Ordering Rationale

- Phase 1 before Phase 3: `fastaOffsets` must exist and be populated before inner loops can use it
- Phase 2 before Phase 3: Regression gate must be green before the code under test is changed — this is the standard pattern for refactor safety
- Phase 4 last: Enhancements and optimizations are only meaningful once correctness is confirmed; profiling on incorrect code produces misleading data
- Gzip fallback (Phase 1) enables Phase 3 to be merged without blocking users with compressed inputs

### Research Flags

Phases with well-documented patterns (skip additional research-phase):
- **Phase 1:** `fseeko`/`ftello`/`_FILE_OFFSET_BITS=64` are fully documented in POSIX.1-2001 and glibc feature_test_macros(7); implementation is mechanical
- **Phase 2:** Binary diff with `cmp` + sha256sum is the established bioinformatics regression pattern (htslib, DIAMOND precedent); test corpus construction is straightforward
- **Phase 3:** Inner loop pattern is fully specified in ARCHITECTURE.md; all edge cases covered in PITFALLS.md

Phases that may need targeted research during planning:
- **Phase 3 (ordinal mismatch, pitfall 5):** The exact interaction between `getObservedAccessions()` KSeqWrapper behavior and the new pre-pass logic requires careful code-reading during implementation. Consider whether to consolidate the two scans into one pass rather than running them separately.
- **Phase 4 (fread/memchr optimization):** Only if fgetc throughput is measured as a bottleneck — PITFALLS.md pitfall 9 notes this changes from line-oriented to byte-scanning logic and requires care.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs are POSIX/C99 with official specs; codebase verified (azure-pipelines.yml confirms Cygwin; KmerMatcher.cpp confirms existing fseek pattern); no speculative recommendations |
| Features | HIGH | Regression testing strategy based on well-established binary-diff patterns from htslib and DIAMOND; table stakes and anti-features are well-reasoned from first principles |
| Architecture | HIGH (codebase) / MEDIUM (FAI comparison) | Component boundaries and data flow derived directly from IndexCreator.cpp source analysis; FAI format comparison is informational, not load-bearing for design decisions |
| Pitfalls | HIGH | All 6 critical pitfalls have direct evidence: pitfall 1 has a live example in KmerMatcher.cpp; pitfalls 2-6 are well-documented C/POSIX behaviors with official spec citations |

**Overall confidence:** HIGH

### Gaps to Address

- **Maximum sequence count per file in core_nt:** The pre-pass uses `offsets.reserve(8192)` as a conservative default. A quick `grep -c '>' largest_file.fna` on the actual corpus would give the exact number for better first-allocation. Low priority — `vector` grows as needed; this is only an optimization.

- **Whether `buildFastaOffsetIndex()` should be consolidated with `getObservedAccessions()`:** PITFALLS.md pitfall 5 identifies ordinal mismatch as the most dangerous failure mode. Consolidating the two scans into one pass eliminates the risk entirely but requires restructuring `getObservedAccessions()`. The research recommends option 1 (consolidation) but leaves the final decision to implementation-time code review.

- **Exact `--max-ram` threshold for forcing multiple buffer flushes in the test corpus:** The FEATURES.md recommendation of `--max-ram 1` with a ~20 MB corpus should work, but verify that the corpus actually triggers at least 2 `writeTargetFiles` + `mergeTargetFiles` cycles in practice.

## Sources

### Primary (HIGH confidence)
- POSIX.1-2001 / C99 §7.19 — `fseeko`, `ftello`, `off_t` semantics
- glibc `feature_test_macros(7)` — `_FILE_OFFSET_BITS=64`
- Microsoft docs `_fseeki64` — `fseek(long)` truncation on MSVC 64-bit confirmed
- C11 §7.21.2; POSIX thread safety classification — `FILE*` thread safety rules
- POSIX.1-2008 §2.9.7 — `pread` atomicity
- Cygwin POSIX compliance docs — `fseeko`/`off_t` availability on Windows
- hts-specs repository `fai.md`, SAMtools docs — FAI offset format
- `src/commons/IndexCreator.cpp` (codebase) — existing sequential scan structure confirmed
- `src/commons/KmerMatcher.cpp:262,264,900` (codebase) — existing `fseek(long)` bug confirmed
- `azure-pipelines.yml`, `util/build_windows.sh` (codebase) — Cygwin build path confirmed

### Secondary (MEDIUM confidence)
- htslib BGZ reader overhaul, DIAMOND chunked FASTA reader — precedent for byte-level checksum regression gates (referenced in FEATURES.md; not directly cited to specific commits)

---
*Research completed: 2026-03-04*
*Ready for roadmap: yes*
