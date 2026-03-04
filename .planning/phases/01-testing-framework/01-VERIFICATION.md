---
phase: 01-testing-framework
verified: 2026-03-04T00:00:00Z
status: passed
score: 10/10 must-haves verified
gaps: []
human_verification:
  - test: "Run regression harness end-to-end against the built binary"
    expected: "Script prints PASS and exits 0"
    why_human: "Requires a compiled Metabuli binary; cannot execute the binary in a static code review. SUMMARY.md documents human confirmed PASS after fixes were applied (commits d81e6ec9, 23dd0332)."
---

# Phase 1: Testing Framework Verification Report

**Phase Goal:** Establish a regression harness that proves the FASTA random-access refactor produces byte-identical database builds.
**Verified:** 2026-03-04
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

The phase goal requires two things to be true simultaneously:

1. A synthetic FASTA corpus that correctly exercises Metabuli's build pipeline (including cross-file species lookup and multi-file accession resolution).
2. A shell harness that builds the same database twice with the unmodified binary and proves byte-identical output across `diffIdx`, `info`, and `split`.

Both are verified below.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Three FASTA files exist in test/data/ with valid ACGT sequence content and FASTA headers | VERIFIED | seq1.fasta (4 seqs, 50,000 bp each), seq2.fasta (4 seqs), seq3.fasta (2 seqs) — all pass ACGT-only check |
| 2 | At least one species (same taxid) has sequences distributed across seq1.fasta and seq2.fasta (multi-file lookup path) | VERIFIED | ACC_B1, ACC_B2 in seq1.fasta and ACC_B3, ACC_B4 in seq2.fasta — all taxid 1002 |
| 3 | accession2taxid.tsv has a mandatory header line and uses 4-column NCBI format: accession TAB accession.version TAB taxid TAB gi | VERIFIED | 11 lines (1 header + 10 rows), each data row has exactly 4 tab-separated columns confirmed programmatically |
| 4 | All 10 accessions in the FASTA files are present in accession2taxid.tsv with correct taxids | VERIFIED | Set comparison: FASTA accessions == a2t accessions, zero missing in either direction |
| 5 | names.dmp, nodes.dmp, and merged.dmp exist in test/data/taxonomy/ in valid NCBI taxdump format | VERIFIED | All 3 files present; names.dmp has 5 entries (taxids 1, 1001-1004); nodes.dmp has 5 entries with correct parent/rank fields |
| 6 | merged.dmp exists (even if empty) — missing this file causes hard failure in validateDatabase | VERIFIED | File exists at 0 bytes; tracked by git (confirmed via git ls-files) |
| 7 | Script accepts binary path as first positional argument | VERIFIED | Line 5: `BINARY="${1:?Usage: $0 <path-to-metabuli-binary>}"` |
| 8 | Script builds the same database twice using --threads 1 --max-ram 1 into separate mktemp directories | VERIFIED | Two identical build invocations with `$BUILD1` and `$BUILD2`; both use same flags |
| 9 | Script runs metabuli validatedb on both builds and exits with FAIL message if either fails (REGTEST-03) | VERIFIED | Lines 35-42: validatedb on BUILD1 and BUILD2 with appropriate FAIL messages |
| 10 | Script byte-compares diffIdx, info, and split via cmp -s; on mismatch prints first differing byte offset and exits non-zero (REGTEST-04) | VERIFIED | Lines 46-52: two-step cmp (silent for exit code, non-silent with awk for byte offset extraction) |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `test/data/seq1.fasta` | 4 sequences for species A (taxid 1001) and B (taxid 1002) | VERIFIED | 4 headers: ACC_A1, ACC_A2, ACC_B1, ACC_B2; 50,000 bp each; valid ACGT only |
| `test/data/seq2.fasta` | 4 sequences for species B (taxid 1002, cross-file) and C (taxid 1003) | VERIFIED | 4 headers: ACC_B3, ACC_B4, ACC_C1, ACC_C2; 50,000 bp each |
| `test/data/seq3.fasta` | 2 sequences for species D (taxid 1004) | VERIFIED | 2 headers: ACC_D1, ACC_D2; 50,000 bp each |
| `test/data/accession2taxid.tsv` | 4-column NCBI format, header, all 10 accessions | VERIFIED | 11 lines; real tab delimiters; accession set matches FASTA headers exactly |
| `test/data/taxonomy/names.dmp` | 5 taxids (root + species A-D) in NCBI taxdump format | VERIFIED | 5 lines; taxids 1, 1001, 1002, 1003, 1004; NCBI pipe-delimited format |
| `test/data/taxonomy/nodes.dmp` | 5 taxids with parent-child hierarchy | VERIFIED | 5 lines; root (1) is own parent; all species are direct children of root; 12-column format |
| `test/data/taxonomy/merged.dmp` | Empty file, must exist | VERIFIED | 0 bytes; tracked in git |
| `test/regression_fasta_access.sh` | Complete regression harness covering REGTEST-02/03/04 | VERIFIED | 55 lines; executable (0o100755); passes `bash -n` syntax check; all structural elements present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| FASTA headers (ACC_* before whitespace) | accession2taxid.tsv column 1 | Accession match — getObservedAccessions() strips version suffix at '.' | WIRED | Exact set equality: all 10 FASTA accessions appear in a2t col 1, zero missing in either direction |
| accession2taxid.tsv taxid column 3 | taxonomy/nodes.dmp taxid | taxid must exist in taxonomy or sequences are skipped | WIRED | All a2t taxids (1001-1004) are present in nodes.dmp; confirmed programmatically |
| regression_fasta_access.sh SCRIPT_DIR computation | test/data/seq*.fasta (absolute paths at runtime) | fasta.list generated from SCRIPT_DIR | WIRED | Line 8: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; printf writes absolute paths at lines 18-21 |
| regression_fasta_access.sh cmp without -s | REGTEST-04 byte offset requirement | cmp captures output with byte position | WIRED | Line 48: `cmp "$BUILD1/$FILE" "$BUILD2/$FILE" 2>&1 | awk '{print $5}' | tr -d ','` — non-silent cmp extracts byte offset |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REGTEST-01 | 01-01-PLAN.md | Mini-corpus of ~3 FASTA files, ~4 species, ~10 accessions committed to test/data/ with at least one cross-file species | SATISFIED | test/data/ contains 3 FASTA files, 10 accessions, 4 species; species B (taxid 1002) spans seq1 and seq2 |
| REGTEST-02 | 01-02-PLAN.md | Shell script builds database twice with --threads 1 --max-ram 1 and byte-compares diffIdx, info, split with cmp -s | SATISFIED | regression_fasta_access.sh builds into BUILD1 and BUILD2 with identical flags and compares the three output files |
| REGTEST-03 | 01-02-PLAN.md | metabuli validatedb passes on both builds confirming internal consistency | SATISFIED | Script calls `"$BINARY" validatedb "$BUILD1"` and `"$BINARY" validatedb "$BUILD2"` before comparison; exits non-zero on failure with FAIL message |
| REGTEST-04 | 01-02-PLAN.md | Regression script exits non-zero and prints first differing byte offset if any output file differs | SATISFIED | Two-step cmp: `cmp -s` for exit code, then `cmp ... | awk '{print $5}' | tr -d ','` for byte offset in the FAIL message |

All four requirements declared across both plans are accounted for. No orphaned requirements found for Phase 1 in REQUIREMENTS.md (traceability table maps exactly REGTEST-01 through REGTEST-04 to Phase 1, all marked Complete).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | — | — | — | No TODOs, FIXMEs, stubs, or placeholder implementations found in any phase 1 artifact |

Specific checks passed:

- No TODO/FIXME/XXX/HACK/PLACEHOLDER comments in regression_fasta_access.sh
- No hardcoded absolute paths in regression_fasta_access.sh (all paths derived from SCRIPT_DIR at runtime)
- No empty return stubs or no-op handlers
- Script does not compare taxID_list or db.parameters (correctly excluded per CONTEXT.md decision)

### Deviations Captured (Auto-Fixed During Execution)

Two bugs were discovered during human verification and corrected before the phase was declared complete:

1. **Short repetitive FASTA sequences triggered Prodigal segfault** — the original 500 bp repeating patterns were below Prodigal's minimum viable input length. Fixed by replacing all sequences with 50,000 bp pseudo-random content (commit 23dd0332). Note: the PLAN specified 500-1000 bp; actual implementation uses 50,000 bp. This is a plan deviation that was necessary for correctness and is fully documented.

2. **Wrong metabuli subcommand name** — PLAN and CONTEXT.md referenced `validateDatabase` (source file name) but the binary registers the CLI command as `validatedb`. Fixed in commit d81e6ec9. The script correctly uses `validatedb`.

Both deviations are documented in 01-02-SUMMARY.md and committed atomically. Neither affects goal achievement.

### Human Verification Required

#### 1. End-to-end regression harness run

**Test:** From the repo root, run `./test/regression_fasta_access.sh ./build/src/metabuli` against a compiled Metabuli binary.
**Expected:** Script prints `PASS` and exits 0. Both build directories are cleaned up. No FAIL messages on stderr.
**Why human:** Requires a compiled Metabuli binary. Cannot execute binaries in static verification. SUMMARY.md documents that a human confirmed PASS after the two bug fixes were applied.

### Gaps Summary

No gaps. All automated checks pass. The one human verification item (binary execution) was confirmed by the human operator during the phase's Task 2 checkpoint — the 01-02-SUMMARY.md states "Human verification (Task 2) confirmed PASS with exit code 0" and documents the correct commits. Static verification confirms the script's structure, data formats, and wiring are all correct.

---

_Verified: 2026-03-04_
_Verifier: Claude (gsd-verifier)_
