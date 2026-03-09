---
phase: 04-benchmarking-and-validation
plan: "01"
subsystem: benchmarking
tags: [timing, instrumentation, build-workflow, cpp, time_t]

requires:
  - phase: 03-inner-loop-refactor
    provides: "Refactored inner loop with fseeko random access replacing sequential scan"

provides:
  - "Total end-to-end build wall-clock timer emitting 'Build complete in X s' on stdout"
  - "Baseline measurement point for BENCH-01 before/after comparison in SCALING_ANALYSIS.md"

affects:
  - 04-benchmarking-and-validation
  - SCALING_ANALYSIS.md

tech-stack:
  added: []
  patterns:
    - "time_t/time(nullptr) wall-clock timing placed at function scope for multi-path functions"
    - "Timer wraps IndexCreator construction through mergeTargetFiles and validateDb"

key-files:
  created: []
  modified:
    - src/workflow/build.cpp

key-decisions:
  - "buildStart timer placed before IndexCreator construction (not before par.parseParameters) — wraps only the index-building work, not CLI parsing"
  - "time_t/time(nullptr) used (not std::chrono) — consistent with IndexCreator.cpp codebase pattern"
  - "Timer print placed before 'Index creation completed.' on single-flush path, and after validateDb block on multi-flush path"

patterns-established:
  - "Both return paths of build() must have timer print — checked via grep -c 'Build complete in' == 2"

requirements-completed: [BENCH-01]

duration: 15min
completed: 2026-03-09
---

# Phase 4 Plan 01: Build Wall-Clock Timer Summary

**Total end-to-end build timer added to build.cpp using time_t/time(nullptr), emitting "Build complete in X s" on both single-flush and multi-flush return paths — regression harness green.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-09T12:42:37Z
- **Completed:** 2026-03-09T12:57:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Added `time_t buildStart = time(nullptr)` immediately before `IndexCreator idxCre(par, taxonomy, 2)` construction on line 94
- "Build complete in X s" printed on the single-flush early return path (line 106) — covers ~small database builds
- "Build complete in X s" printed on the multi-flush path (line 133) — covers large database builds including mergeTargetFiles
- Regression harness (`test/regression_fasta_access.sh`) exits 0 — byte-identical diffIdx, info, split files across two independent builds confirm instrumentation is non-behavioral

## Task Commits

1. **Task 1: Add total build wall-clock timer to build.cpp** - `202d3452` (feat)
2. **Task 2: Regression check** - No commit (verification-only task, no file changes)

**Plan metadata:** (pending final docs commit)

## Files Created/Modified

- `src/workflow/build.cpp` - Added `buildStart` timer and two "Build complete in X s" print statements

## Decisions Made

- Timer placed before `IndexCreator` construction (not before `par.parseParameters`) — wraps only the index-building work, not CLI parsing or taxonomy loading. This matches the "total end-to-end build wall-clock" intent from CONTEXT.md.
- Used `time_t` / `time(nullptr)` rather than `std::chrono::steady_clock` — consistent with the codebase-wide pattern established in `IndexCreator.cpp`.
- "Build complete in X s" line printed before "Index creation completed." on the single-flush path to match the locked label format from CONTEXT.md.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Binary path: The plan's verify command used `./build/metabuli` but the actual binary location is `./build/src/metabuli`. Corrected the path for the regression harness invocation. This is a non-code issue (the cmake build structure puts the target in `build/src/`).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Timer is live in the binary — next build run against core_nt or representative subset will emit "Build complete in X s" to stdout
- SCALING_ANALYSIS.md Section 8.3 "After (measured)" column can be filled in once a full database build is executed
- No blockers — Phase 4 Plan 02 (if it exists) can proceed immediately

---
*Phase: 04-benchmarking-and-validation*
*Completed: 2026-03-09*
