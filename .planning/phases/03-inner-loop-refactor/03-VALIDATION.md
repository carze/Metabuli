---
phase: 3
slug: inner-loop-refactor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Shell regression script (bash) |
| **Config file** | `test/regression_fasta_access.sh` |
| **Quick run command** | `./test/regression_fasta_access.sh ./build/src/metabuli` |
| **Full suite command** | `./test/regression_fasta_access.sh ./build/src/metabuli` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./test/regression_fasta_access.sh ./build/src/metabuli`
- **After every plan wave:** Run `./test/regression_fasta_access.sh ./build/src/metabuli`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| TBD | 01 | 1 | EXTKMER-01 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 01 | 1 | EXTKMER-02 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 01 | 1 | EXTKMER-03 | integration | gzip corpus test (Wave 0 gap) | ❌ W0 | ⬜ pending |
| TBD | 01 | 1 | EXTKMER-04 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 02 | 1 | FILLTGT-01 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 02 | 1 | FILLTGT-02 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 02 | 1 | FILLTGT-03 | integration | gzip corpus test (Wave 0 gap) | ❌ W0 | ⬜ pending |
| TBD | 02 | 1 | FILLTGT-04 | integration | `./test/regression_fasta_access.sh ./build/src/metabuli` | ✅ | ⬜ pending |
| TBD | 03 | 1 | DOCS-01 | manual | `grep -i gzip README.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Gzip fallback corpus — at least one `.gz` FASTA in `test/data/` with corresponding test invocation in `regression_fasta_access.sh` to cover EXTKMER-03 / FILLTGT-03. **Note:** KSeq path is unchanged by design; this is optional validation rather than blocking. The existing script fully covers the fseeko path.
- [ ] DOCS-01 is manual-only; no automated test. Reviewer inspects `README.md` after documentation task.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| README.md contains gzip limitation note | DOCS-01 | Documentation review, no automated assertion | After documentation task: `grep -i gzip README.md` — verify limitation + workaround text is present near database building section |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
