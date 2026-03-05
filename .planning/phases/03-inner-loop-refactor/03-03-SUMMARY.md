---
phase: 03-inner-loop-refactor
plan: "03"
subsystem: docs
tags: [readme, documentation, gzip, fasta, limitation]

# Dependency graph
requires:
  - phase: 03-inner-loop-refactor
    provides: "gzip FASTA random access context (offset index skips .gz files)"
provides:
  - "README.md gzip FASTA limitation note near NCBI/custom taxonomy database section"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Document limitations near the relevant user action (build command section)"

key-files:
  created: []
  modified:
    - README.md

key-decisions:
  - "Positioned note as [!NOTE] callout immediately after the [!IMPORTANT] FASTA requirements block for maximum proximity and visibility"
  - "No performance numbers included — limitation framed as workaround requirement, not benchmark"

patterns-established:
  - "Use [!NOTE] GitHub callout for non-blocking limitation notes adjacent to [!IMPORTANT] requirement blocks"

requirements-completed: [DOCS-01]

# Metrics
duration: 6min
completed: 2026-03-05
---

# Phase 3 Plan 03: README gzip FASTA Limitation Note Summary

**[!NOTE] callout added to README.md stating gzip FASTA files fall back to sequential scan and must be decompressed with gunzip before large database builds**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-05T18:39:00Z
- **Completed:** 2026-03-05T18:45:38Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Located the "NCBI or custom taxonomy based database" section and its [!IMPORTANT] FASTA requirements block
- Inserted a [!NOTE] callout immediately after the requirements block
- Note states gzip limitation, gunzip workaround, and sequential scan fallback in 2 sentences with no performance numbers

## Task Commits

Each task was committed atomically:

1. **Task 1: Add gzip limitation note to README.md** - `16eecd57` (docs)

## Files Created/Modified
- `README.md` - Added [!NOTE] callout after line 418 ([!IMPORTANT] block) in the NCBI/custom taxonomy database section

## Decisions Made
- Positioned as a separate [!NOTE] callout (not a fourth item in [!IMPORTANT]) to keep the requirements block clean and the limitation visually distinct
- Framed as limitation + workaround (not a hard requirement), matching the CONTEXT.md tone decision

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- DOCS-01 satisfied; README now accurately documents gzip FASTA limitation for database builders
- No blockers for subsequent phases

---
*Phase: 03-inner-loop-refactor*
*Completed: 2026-03-05*
