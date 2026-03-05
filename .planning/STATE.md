---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Completed 03-02-PLAN.md (fillTargetKmerBuffer fseeko refactor)
last_updated: "2026-03-05T19:00:16.024Z"
last_activity: 2026-03-04 — Roadmap revised; Testing Framework promoted to Phase 1 (test baseline before implementation); Phase 1 ready to plan
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 7
  completed_plans: 7
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-04)

**Core value:** Replace redundant sequential FASTA scanning with offset-indexed random access so that 900 GB of reference data is read once instead of ~7,500 times — reducing database build time from ~22 days to ~10-12 hours
**Current focus:** Phase 1 — Testing Framework

## Current Position

Phase: 1 of 4 (Testing Framework)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-03-04 — Roadmap revised; Testing Framework promoted to Phase 1 (test baseline before implementation); Phase 1 ready to plan

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: none yet
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 3 | 2 tasks | 8 files |
| Phase 01 P02 | 45 | 2 tasks | 4 files |
| Phase 02-build-system-offset-index P01 | 3 | 2 tasks | 2 files |
| Phase 02-build-system-offset-index P02 | 2 | 2 tasks | 1 files |
| Phase 03-inner-loop-refactor P03 | 6 | 1 tasks | 1 files |
| Phase 03-inner-loop-refactor P01 | 15 | 2 tasks | 1 files |
| Phase 03-inner-loop-refactor P02 | 4 | 1 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-planning]: Use `fseeko`/`ftello` + per-batch FILE* handles (not mmap, not pread) for cross-platform 64-bit random access
- [Pre-planning]: Fix both `extractKmerFromSixFrames()` AND `fillTargetKmerBuffer()` — both have identical sequential scan bottleneck
- [Pre-planning]: Per-thread `seqBuf` vector replaces KSeq buffer + per-sequence maskedSeq malloc
- [Pre-planning]: Parallel offset index build across files (embarrassingly parallel, dynamic OpenMP scheduling)
- [Pre-planning]: Regression harness must be green on sequential baseline BEFORE inner loops are changed
- [2026-03-04 revision]: Testing Framework moved to Phase 1 — test harness must be green on unmodified code first; that baseline is what correctness is measured against
- [Phase 01]: test/data/.gitignore added to override root *.tsv/*.dmp exclusions for committed test fixtures
- [Phase 01]: 50,000 bp pseudo-random sequences required — Prodigal segfaults on short repetitive sequences
- [Phase 01]: validatedb (not validateDatabase) is the correct metabuli subcommand name
- [Phase 02-build-system-offset-index]: Use target_compile_definitions PRIVATE scope for _FILE_OFFSET_BITS=64 to avoid polluting linked submodule builds
- [Phase 02-build-system-offset-index]: Generator expression excludes Windows from _FILE_OFFSET_BITS=64 (platform uses _fseeki64/_ftelli64 instead)
- [Phase 02-build-system-offset-index]: static_assert(sizeof(off_t)==8) placed immediately after sys/types.h include in IndexCreator.h to catch misconfigured 32-bit builds at compile time
- [Phase 02-build-system-offset-index]: Spot-check validPairs built by iterating all (fileIdx, ordinal) pairs for uniform random coverage; gzip files silently skipped (not error); srand(time(nullptr)) no fixed seed
- [Phase 03-inner-loop-refactor]: Positioned gzip note as [!NOTE] callout immediately after the [!IMPORTANT] FASTA requirements block; no performance numbers, framed as limitation + workaround
- [Phase 03-01]: readFastaSequence placed as file-scope static (not class method) so Plan 02 can reuse without header changes
- [Phase 03-01]: Sort permutation via iota+sort on index vector avoids mutating parallel arrays (orders/taxIDs/lengths)
- [Phase 03-01]: seqBuf declared inside omp parallel block (per-thread) — zero heap allocation per sequence in fseeko path
- [Phase 03-02]: seqBuf and rcBuf declared inside omp parallel block (per-thread) for fillTargetKmerBuffer — not in shared() list
- [Phase 03-02]: Header re-seek for cdsInfoMap key: fseeko back to curOff + fgets after readFastaSequence body load (no data structure changes needed)
- [Phase 03-02]: Forward Prodigal masking order: getPredictedGenes/getExtendedORFs on raw seqBuf, mask in-place AFTER, extractTargetKmers on masked seqBuf

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 3 risk]: Ordinal mismatch between pre-pass and `getObservedAccessions()` KSeqWrapper behavior is the most dangerous failure mode — consider consolidating into single file scan during Phase 3 planning
- [Phase 4 dependency]: Benchmark requires access to core_nt or a >=100 GB representative subset; confirm data availability before Phase 4

## Session Continuity

Last session: 2026-03-05T18:56:20.924Z
Stopped at: Completed 03-02-PLAN.md (fillTargetKmerBuffer fseeko refactor)
Resume file: None
