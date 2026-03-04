---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Completed 01-01-PLAN.md (synthetic test corpus)
last_updated: "2026-03-04T19:23:08.317Z"
last_activity: 2026-03-04 — Roadmap revised; Testing Framework promoted to Phase 1 (test baseline before implementation); Phase 1 ready to plan
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 2
  completed_plans: 1
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

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 3 risk]: Ordinal mismatch between pre-pass and `getObservedAccessions()` KSeqWrapper behavior is the most dangerous failure mode — consider consolidating into single file scan during Phase 3 planning
- [Phase 4 dependency]: Benchmark requires access to core_nt or a >=100 GB representative subset; confirm data availability before Phase 4

## Session Continuity

Last session: 2026-03-04T19:23:08.315Z
Stopped at: Completed 01-01-PLAN.md (synthetic test corpus)
Resume file: None
