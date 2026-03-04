---
phase: 1
slug: testing-framework
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-04
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash script (no external test framework) |
| **Config file** | none |
| **Quick run command** | `ls test/data/ test/data/taxonomy/` |
| **Full suite command** | `./test/regression_fasta_access.sh ./build/src/metabuli` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `ls test/data/ test/data/taxonomy/` (verify files exist)
- **After every plan wave:** Run `./test/regression_fasta_access.sh ./build/src/metabuli`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | REGTEST-01 | smoke | `ls test/data/seq*.fasta test/data/taxonomy/names.dmp` | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | REGTEST-01 | smoke | `ls test/data/taxonomy/` | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | REGTEST-02 | regression | `./test/regression_fasta_access.sh ./build/src/metabuli` | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | REGTEST-03 | smoke | `./test/regression_fasta_access.sh ./build/src/metabuli` | ❌ W0 | ⬜ pending |
| 1-02-03 | 02 | 2 | REGTEST-04 | manual | inject mismatch, verify non-zero exit + offset | manual-only | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/data/seq1.fasta` — corpus file 1 (REGTEST-01)
- [ ] `test/data/seq2.fasta` — corpus file 2, cross-file species (REGTEST-01)
- [ ] `test/data/seq3.fasta` — corpus file 3 (REGTEST-01)
- [ ] `test/data/accession2taxid.tsv` — 4-column NCBI format with header (REGTEST-01)
- [ ] `test/data/taxonomy/names.dmp` — taxonomy names (REGTEST-01)
- [ ] `test/data/taxonomy/nodes.dmp` — taxonomy nodes (REGTEST-01)
- [ ] `test/data/taxonomy/merged.dmp` — merged nodes (can be empty, must exist) (REGTEST-01)
- [ ] `test/regression_fasta_access.sh` — regression harness (REGTEST-02, REGTEST-03, REGTEST-04)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Non-zero exit + byte offset printed on mismatch | REGTEST-04 | Requires injecting a known difference between builds | After running full script successfully, manually corrupt one output file and re-run; verify non-zero exit and offset is printed |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
