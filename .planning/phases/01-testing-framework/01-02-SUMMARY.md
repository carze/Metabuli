---
phase: 01-testing-framework
plan: 02
subsystem: testing
tags: [bash, regression, determinism, metabuli, fasta, database-build]

# Dependency graph
requires:
  - phase: 01-01
    provides: synthetic FASTA corpus, accession2taxid.tsv, taxonomy files at test/data/
provides:
  - Executable regression harness at test/regression_fasta_access.sh covering REGTEST-02/03/04
  - Green baseline run on unmodified Metabuli binary confirming build determinism
affects:
  - 03-fseeko-refactor (will re-run harness to confirm refactor produces byte-identical output)
  - Any future CI integration of the regression gate

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Regression script derives all paths from SCRIPT_DIR via BASH_SOURCE[0] — no hardcoded paths"
    - "Two-step cmp: silent (-s) for pass/fail, then non-silent to extract byte offset on failure"
    - "Single EXIT trap cleans all temp artifacts (both build dirs + fasta.list)"

key-files:
  created:
    - test/regression_fasta_access.sh
  modified:
    - test/data/seq1.fasta
    - test/data/seq2.fasta
    - test/data/seq3.fasta

key-decisions:
  - "50,000 bp pseudo-random sequences required — Prodigal segfaults on short repetitive sequences"
  - "validatedb (not validateDatabase) is the correct metabuli subcommand name"
  - "Regression harness is standalone (no CI wiring) — per locked decision from CONTEXT.md"

patterns-established:
  - "Regression harness pattern: build twice with --threads 1 --max-ram 1, validate both, byte-compare diffIdx/info/split"
  - "cmp two-step pattern: cmp -s for exit code, then cmp without -s to extract byte offset via awk"

requirements-completed: [REGTEST-02, REGTEST-03, REGTEST-04]

# Metrics
duration: ~45min (including human verification and fixes)
completed: 2026-03-04
---

# Phase 1 Plan 02: Regression Harness Summary

**Bash regression harness that builds Metabuli database twice with --threads 1 and byte-compares diffIdx/info/split to prove build determinism, confirmed green on unmodified binary**

## Performance

- **Duration:** ~45 min (including human verification loop)
- **Started:** 2026-03-04
- **Completed:** 2026-03-04
- **Tasks:** 2 (1 auto, 1 checkpoint:human-verify)
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- Wrote `test/regression_fasta_access.sh` — complete regression harness implementing REGTEST-02 (byte-identical builds), REGTEST-03 (validatedb on both builds), and REGTEST-04 (byte offset on mismatch)
- Replaced 500 bp repetitive FASTA sequences with 50,000 bp pseudo-random sequences — Prodigal was segfaulting on the repetitive input, which was blocking the harness from running end-to-end
- Corrected `validateDatabase` to `validatedb` — the correct metabuli subcommand name
- Confirmed PASS end-to-end on an unmodified Metabuli binary — determinism baseline is established

## Task Commits

Each task was committed atomically:

1. **Task 1: Write regression_fasta_access.sh** - `d9e0fcec` (feat)
2. **Task 2 fix: Replace repetitive FASTA with 50kb pseudo-random sequences** - `23dd0332` (test)
3. **Task 2 fix: Correct validateDatabase to validatedb** - `d81e6ec9` (fix)

Human verification (Task 2) confirmed PASS with exit code 0.

## Files Created/Modified

- `test/regression_fasta_access.sh` - Complete regression harness: builds twice, validates both, byte-compares diffIdx/info/split
- `test/data/seq1.fasta` - Replaced with 50,000 bp pseudo-random sequences (was 500 bp repetitive)
- `test/data/seq2.fasta` - Replaced with 50,000 bp pseudo-random sequences (was 500 bp repetitive)
- `test/data/seq3.fasta` - Replaced with 50,000 bp pseudo-random sequences (was 500 bp repetitive)

## Decisions Made

- **50,000 bp pseudo-random sequences:** Prodigal (called internally by metabuli build) segfaults on short, highly repetitive sequences. The synthetic sequences from plan 01-01 used repeating patterns that triggered this. Replaced with pseudo-random content of realistic length.
- **validatedb not validateDatabase:** The metabuli binary uses `validatedb` as the subcommand name; `validateDatabase` was the name from the source file (validateDatabase.cpp) but the CLI registration uses the shorter form.

## Deviations from Plan

### Auto-fixed Issues (during human verification)

**1. [Rule 1 - Bug] Prodigal segfault on short repetitive FASTA sequences**
- **Found during:** Task 2 (human verification run)
- **Issue:** Metabuli's internal Prodigal call segfaulted when given 500 bp sequences composed of repeated patterns — below Prodigal's minimum viable sequence length for gene prediction
- **Fix:** Replaced seq1/seq2/seq3.fasta sequences with 50,000 bp pseudo-random content
- **Files modified:** test/data/seq1.fasta, test/data/seq2.fasta, test/data/seq3.fasta
- **Verification:** Human ran full regression harness end-to-end — PASS
- **Committed in:** 23dd0332

**2. [Rule 1 - Bug] Wrong metabuli subcommand: validateDatabase vs validatedb**
- **Found during:** Task 2 (human verification run)
- **Issue:** Script used `validateDatabase` (source file name) but the binary registers the command as `validatedb`
- **Fix:** Changed all `validateDatabase` calls in regression_fasta_access.sh to `validatedb`
- **Files modified:** test/regression_fasta_access.sh
- **Verification:** Human confirmed PASS after fix
- **Committed in:** d81e6ec9

---

**Total deviations:** 2 auto-fixed during human verification (2 bugs)
**Impact on plan:** Both fixes were necessary for the harness to run. The fixes corrected mismatches between the plan's assumptions and actual binary behavior — no scope creep.

## Issues Encountered

- Prodigal minimum sequence length requirement was not documented in metabuli README or build.cpp — only discovered through a real binary run. Future synthetic corpora should use sequences of at least 10,000 bp to avoid Prodigal edge cases.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Determinism baseline is fully established: unmodified Metabuli binary produces byte-identical diffIdx/info/split across two independent builds
- `test/regression_fasta_access.sh ./build/src/metabuli` is the correctness gate for Phase 3 (fseeko refactor)
- Phase 3 planning should reference this harness as the acceptance criterion — refactor passes when this script prints PASS on the modified binary

---
*Phase: 01-testing-framework*
*Completed: 2026-03-04*
