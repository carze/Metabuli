---
phase: 01-testing-framework
plan: "01"
subsystem: test-data
tags: [test-fixtures, fasta, taxonomy, regression]
dependency_graph:
  requires: []
  provides:
    - test/data/seq1.fasta
    - test/data/seq2.fasta
    - test/data/seq3.fasta
    - test/data/accession2taxid.tsv
    - test/data/taxonomy/names.dmp
    - test/data/taxonomy/nodes.dmp
    - test/data/taxonomy/merged.dmp
  affects:
    - "01-02: regression harness (consumes these files)"
tech_stack:
  added: []
  patterns:
    - "NCBI 4-column accession2taxid format (tab-delimited, mandatory header)"
    - "NCBI taxdump format for names.dmp/nodes.dmp"
    - "Synthetic ACGT FASTA sequences (repeating patterns, 500-700 bp)"
key_files:
  created:
    - test/data/seq1.fasta
    - test/data/seq2.fasta
    - test/data/seq3.fasta
    - test/data/accession2taxid.tsv
    - test/data/taxonomy/names.dmp
    - test/data/taxonomy/nodes.dmp
    - test/data/taxonomy/merged.dmp
    - test/data/.gitignore
  modified: []
decisions:
  - "Synthetic repeating ACGT patterns used (e.g. ACGTACGT..., GGCCGGCC...) — no real biological sequences"
  - "Species taxids: A=1001, B=1002, C=1003, D=1004; root=1; all species direct children of root"
  - "test/data/.gitignore added to override root *.tsv/*.dmp exclusions (deviation Rule 3)"
metrics:
  duration: "3 minutes"
  completed_date: "2026-03-04"
  tasks_completed: 2
  files_created: 8
---

# Phase 1 Plan 1: Synthetic Test Corpus Summary

**One-liner:** 10-accession synthetic FASTA corpus with NCBI-format accession2taxid and taxdump files enabling deterministic Metabuli regression builds.

## What Was Built

Created the static test fixture data that the Phase 1 regression harness (plan 01-02) will run against. All 7 files are committed to `test/data/` and use exact formats verified from Metabuli source code (`IndexCreator.cpp` line 629 sscanf pattern).

### File Inventory

| File | Contents |
|------|----------|
| `test/data/seq1.fasta` | 4 sequences: ACC_A1, ACC_A2 (taxid 1001), ACC_B1, ACC_B2 (taxid 1002) |
| `test/data/seq2.fasta` | 4 sequences: ACC_B3, ACC_B4 (taxid 1002, cross-file), ACC_C1, ACC_C2 (taxid 1003) |
| `test/data/seq3.fasta` | 2 sequences: ACC_D1, ACC_D2 (taxid 1004) |
| `test/data/accession2taxid.tsv` | 11 lines: 1 mandatory header + 10 rows, 4-column NCBI format, tab-delimited |
| `test/data/taxonomy/names.dmp` | 5 taxids: root (1) + species A-D (1001-1004) |
| `test/data/taxonomy/nodes.dmp` | 5 taxids: root is own parent, species are direct children of root |
| `test/data/taxonomy/merged.dmp` | Empty file (zero bytes) — must exist to avoid hard failure in validateDatabase |

### Key Design Properties

- Species B (taxid 1002) spans both seq1.fasta and seq2.fasta — exercises the multi-file lookup path that the offset index must handle
- All accession names (ACC_A1 etc.) match exactly between FASTA headers and accession2taxid.tsv column 1
- All taxids in accession2taxid.tsv appear in nodes.dmp
- accession2taxid.tsv uses real tab characters (verified — sscanf format `%s\t%*s\t%d\t%*d` requires tabs)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] Root .gitignore excluded *.tsv and *.dmp files**
- **Found during:** Task 2 commit
- **Issue:** Root `.gitignore` contains `*.tsv` and `*.dmp` patterns (intended for large NCBI genome dump files), which blocked committing the test fixture taxonomy and accession files
- **Fix:** Created `test/data/.gitignore` with negation patterns (`!*.tsv`, `!*.dmp`, `!taxonomy/*.dmp`) to override root rules for the test data directory without modifying the root .gitignore
- **Files modified:** `test/data/.gitignore` (created)
- **Commit:** c98d874b

## Success Criteria Verification

- [x] 3 FASTA files exist with correct accession headers and ACGT sequence content
- [x] 10 accessions across 4 species, species B (taxid 1002) in both seq1 and seq2
- [x] accession2taxid.tsv uses real tabs, has header line, covers all 10 accessions
- [x] All 4 taxonomy files exist; merged.dmp exists (0 bytes)
- [x] No hardcoded absolute paths in any data file

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: FASTA corpus | eadeb3e3 | test/data/seq1.fasta, seq2.fasta, seq3.fasta |
| Task 2: Taxonomy + accession data | c98d874b | test/data/.gitignore, accession2taxid.tsv, taxonomy/{names,nodes,merged}.dmp |
