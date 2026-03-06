---
phase: 4
slug: benchmarking-and-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (existing regression harness) |
| **Config file** | none — self-contained script |
| **Quick run command** | `bash test/regression_fasta_access.sh ./build/metabuli` |
| **Full suite command** | `bash test/regression_fasta_access.sh ./build/metabuli` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash test/regression_fasta_access.sh ./build/metabuli`
- **After every plan wave:** Run `bash test/regression_fasta_access.sh ./build/metabuli`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 04-01 | 1 | BENCH-01 | smoke | `cmake --build build --target metabuli && grep "Total build time" /dev/stdin` | ✅ | ⬜ pending |
| 4-01-02 | 04-01 | 1 | BENCH-01 | regression | `bash test/regression_fasta_access.sh ./build/metabuli` | ✅ | ⬜ pending |
| 4-02-01 | 04-02 | 1 | BENCH-01 | smoke | `bash -n scripts/benchmark_core_nt.sh && awk -f scripts/parse_bench_log.awk /dev/null && ls scripts/benchmark_core_nt.sh scripts/parse_bench_log.awk` | ❌ W0 | ⬜ pending |
| 4-02-02 | 04-02 | 1 | BENCH-02 | smoke | `grep "## 8. Benchmark Results" SCALING_ANALYSIS.md` | ❌ W0 | ⬜ pending |
| 4-03-01 | 04-03 | 2 | BENCH-01 | smoke | `cmake --build build --target metabuli && bash -n scripts/benchmark_core_nt.sh` | ✅ | ⬜ pending |
| 4-03-02 | 04-03 | 2 | BENCH-01 | manual | Cloud benchmark run (human action) | manual-only | ⬜ pending |
| 4-03-03 | 04-03 | 2 | BENCH-02 | manual | `grep -c "| — |" SCALING_ANALYSIS.md` confirms placeholders replaced | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scripts/benchmark_core_nt.sh` — covers BENCH-01 (benchmark script committed)
- [ ] `scripts/parse_bench_log.awk` — log parser for extracting per-stage timings
- [ ] Cloud instance provisioning and data staging (manual prerequisite — not automatable)
- [ ] Captured benchmark logs (only exist after cloud run — cannot be pre-staged)

*Note: The existing regression harness at `test/regression_fasta_access.sh` covers instrumentation correctness; cloud execution is the only path to satisfying the full BENCH-01 requirement at core_nt scale.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| core_nt-scale build completes successfully | BENCH-01 | Requires cloud instance with 900 GB data; cannot be automated locally | Provision AWS r7i.32xlarge, stage core_nt data, run benchmark script, verify exit code 0 |
| Before/after table has actual timings | BENCH-02 | Requires cloud run completion to have real timing data | Review Section 8.3 table in SCALING_ANALYSIS.md; confirm all "—" placeholders replaced with actual values |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
