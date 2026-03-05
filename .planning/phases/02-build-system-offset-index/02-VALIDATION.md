---
phase: 2
slug: build-system-offset-index
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash shell script (existing) |
| **Config file** | none — standalone script |
| **Quick run command** | `./test/regression_fasta_access.sh ./build/metabuli` |
| **Full suite command** | `./test/regression_fasta_access.sh ./build/metabuli` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./test/regression_fasta_access.sh ./build/metabuli`
- **After every plan wave:** Run `./test/regression_fasta_access.sh ./build/metabuli`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | BUILD-01, BUILD-02 | compile | `cmake --build build 2>&1` | ✅ CMake build | ⬜ pending |
| 2-01-02 | 01 | 1 | OFFIDX-01 | smoke | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing | ⬜ pending |
| 2-01-03 | 01 | 1 | OFFIDX-02, OFFIDX-03, OFFIDX-04 | smoke | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing | ⬜ pending |
| 2-01-04 | 01 | 1 | OFFIDX-05 | manual | See Manual-Only Verifications | N/A | ⬜ pending |
| 2-01-05 | 01 | 1 | OFFIDX-06 | smoke | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing | ⬜ pending |
| 2-01-06 | 01 | 1 | OFFIDX-07 | smoke | `./test/regression_fasta_access.sh ./build/metabuli` | ✅ existing | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — existing infrastructure covers all phase requirements.

The regression script from Phase 1 (`test/regression_fasta_access.sh`) is sufficient: it runs the build pipeline end-to-end, invokes `validatedb`, and byte-compares outputs. Since `buildFastaOffsetIndex()` runs inside the build pipeline and its spot-check calls `exit(EXIT_FAILURE)` on failure, any offset correctness issue will cause the binary to exit non-zero, failing the regression script.

*Existing infrastructure covers all automatically-testable phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Gzip sentinel: empty vector for gzip files | OFFIDX-05 | No gzip FASTA in test corpus | Copy a test FASTA, rename to `.gz` (without actually compressing), run build pipeline, confirm no crash and gzip file is silently skipped (check magic bytes: `xxd test/data/test.gz \| head -1` should NOT show `1f 8b` for this test; for real gzip test: create one with `gzip -k seq1.fasta` and verify offset vector is empty) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
