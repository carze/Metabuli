---
phase: 02-build-system-offset-index
plan: 01
subsystem: infra
tags: [cmake, cpp, off_t, fseeko, compile-time-guard, offset-index]

# Dependency graph
requires:
  - phase: 01-testing-framework
    provides: regression test harness that will validate correctness of Phase 3 changes
provides:
  - _FILE_OFFSET_BITS=64 CMake compile definition on all non-Windows targets
  - static_assert(sizeof(off_t) == 8) compile-time guard in IndexCreator.h
  - vector<vector<uint64_t>> fastaOffsets field in IndexCreator protected section
  - void buildFastaOffsetIndex() declaration in IndexCreator protected section
affects: [02-build-system-offset-index, 03-implementation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CMake PRIVATE compile definitions via generator expressions to exclude Windows"
    - "static_assert for platform portability enforcement at compile time"
    - "Interface-first ordering: header contracts declared before implementation"

key-files:
  created: []
  modified:
    - src/CMakeLists.txt
    - src/commons/IndexCreator.h

key-decisions:
  - "Use target_compile_definitions with PRIVATE scope (not add_definitions) to avoid polluting linked submodule builds"
  - "Generator expression $<$<NOT:$<PLATFORM_ID:Windows>>:_FILE_OFFSET_BITS=64> excludes Windows where off_t is already 64-bit"
  - "Place static_assert immediately after #include <sys/types.h> so the assertion fires before any class definition"

patterns-established:
  - "PRIVATE compile definitions: new per-binary flags go via target_compile_definitions(target PRIVATE ...) not add_definitions()"
  - "Compile-time portability guards: use static_assert on platform types rather than runtime checks"

requirements-completed: [BUILD-01, BUILD-02, OFFIDX-01]

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 2 Plan 01: Build System + Offset Index Header Summary

**CMake `_FILE_OFFSET_BITS=64` compile definition and `IndexCreator.h` contracts for 64-bit file offset random access, establishing the interface Plan 02-02 implements**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T16:35:08Z
- **Completed:** 2026-03-05T16:38:01Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `target_compile_definitions(metabuli PRIVATE $<$<NOT:$<PLATFORM_ID:Windows>>:_FILE_OFFSET_BITS=64>)` to `src/CMakeLists.txt` after `mmseqs_setup_derived_target(metabuli)`, ensuring all non-Windows builds get 64-bit `off_t`
- Added `#include <sys/types.h>` and `static_assert(sizeof(off_t) == 8, ...)` to `IndexCreator.h` to catch misconfigured 32-bit Linux builds at compile time with a clear diagnostic message
- Declared `vector<vector<uint64_t>> fastaOffsets` field and `void buildFastaOffsetIndex()` method in the `IndexCreator` protected section, establishing the interface Plan 02-02 implements

## Task Commits

Each task was committed atomically:

1. **Task 1: Add _FILE_OFFSET_BITS=64 to src/CMakeLists.txt** - `da71579b` (chore)
2. **Task 2: Add sys/types.h, static_assert, fastaOffsets, buildFastaOffsetIndex to IndexCreator.h** - `b9194e06` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `src/CMakeLists.txt` - Added `target_compile_definitions` block for `_FILE_OFFSET_BITS=64` on non-Windows targets
- `src/commons/IndexCreator.h` - Added `<sys/types.h>` include, `static_assert(sizeof(off_t) == 8)`, `fastaOffsets` field, and `buildFastaOffsetIndex()` declaration

## Decisions Made

- Used `PRIVATE` scope on `target_compile_definitions` so the flag is not propagated to linked libraries (mmseqs-framework, prodigal, fasta_validator etc.) which have their own build configurations
- Generator expression `$<$<NOT:$<PLATFORM_ID:Windows>>:...>` used on Windows exclusion — on Windows, `off_t` is not 64-bit via this macro but the platform uses `_fseeki64`/`_ftelli64` instead, so the definition is both unnecessary and potentially confusing
- `static_assert` placed immediately after `#include <sys/types.h>` so it fires before any class or struct definition uses `off_t`

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `src/CMakeLists.txt` and `src/commons/IndexCreator.h` contracts are in place
- Plan 02-02 can now implement `IndexCreator::buildFastaOffsetIndex()` in `IndexCreator.cpp` against these stable declarations
- The `fastaOffsets` field is available for Plans 02-03 and 02-04 to populate and consume
- Build is clean — no new warnings introduced by these changes

---
*Phase: 02-build-system-offset-index*
*Completed: 2026-03-05*
