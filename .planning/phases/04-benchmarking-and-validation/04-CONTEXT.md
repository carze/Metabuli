# Phase 4: Benchmarking and Validation - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Run the fixed implementation (Phases 1-3 complete) on the full core_nt dataset at cloud scale. Collect per-stage wall-clock timings, document the before/after build time comparison, and identify the next bottleneck. No new algorithmic work — this phase is measurement and documentation.

</domain>

<decisions>
## Implementation Decisions

### Dataset
- Full core_nt (~900 GB, 2,382 files) — not a subset
- Run on a cloud instance (AWS/GCP/Azure)
- `--threads 100 --max-ram 1000`
- Run twice: once at `--max-ram 1000` (single-flush, no cycle overhead) and once at `--max-ram 128` (multi-flush, ~280 cycles) to observe per-flush-cycle behavior

### Pre-pass timing instrumentation
- Add `time()` instrumentation to `buildFastaOffsetIndex()` — consistent with the existing `time(nullptr)` pattern used for extraction/sort/filter/write stages
- Output style: one line, `"Offset index built in X s"` — matches existing stage timer format
- Add total end-to-end build wall-clock at the end of `build.cpp` — `"Build complete in X s"`

### Before baseline
- Use the documented ~22-day estimate from SCALING_ANALYSIS.md — this is grounded in measured batch counts (8,400 batches × 378 MB × 2,382 files). No re-run of old implementation needed.
- Benchmark report states actual timings only — no next-step recommendation in this phase

### Results documentation
- Update `SCALING_ANALYSIS.md` in-place: add a new `## 8. Benchmark Results` section with actual timings side-by-side with the predicted values from Section 5.6
- Per-flush-cycle data (multi-flush run): present as summary stats table — min/max/avg per stage across cycles, not 280 rows of raw data
- Commit a reproducible benchmark script to `scripts/` or `test/` that runs the build and captures stdout

### Claude's Discretion
- Exact instance type / sizing on cloud provider
- Script location (`scripts/` vs `test/benchmark/`)
- How to handle capturing stdout from a multi-hour run (nohup, tmux, tee)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `IndexCreator.cpp` flush loop: already has `time_t start = time(nullptr)` before each stage (extraction, sort, filter, write) with `cout << "Stage : " << time(nullptr) - start << " s"` output — the pre-pass timer should use the exact same pattern
- `build.cpp`: entry point where `buildFastaOffsetIndex()` is called — total build timer goes here (before `getObservedAccessions()`, compared at end)

### Established Patterns
- Per-stage timing: `time_t start = time(nullptr)` / `cout << double(time(nullptr) - start) << " s"` — use this pattern for new instrumentation, not `chrono`
- Stage label format: left-padded to 20 chars: `"Offset index build  : "` (match `"K-mer extraction    : "`, `"Sort k-mers         : "` etc.)

### Integration Points
- New timer code touches: `src/commons/IndexCreator.cpp` (pre-pass) and `src/workflow/build.cpp` (total build)
- `SCALING_ANALYSIS.md` is untracked in git — needs to be committed as part of this phase

</code_context>

<specifics>
## Specific Ideas

- Two-run structure: `--max-ram 1000` for single-flush clean timing, `--max-ram 128` for per-cycle variance data
- Section 8 in SCALING_ANALYSIS.md should have a table with "Predicted" vs "Actual" columns for each stage — directly comparable with Section 5.6

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-benchmarking-and-validation*
*Context gathered: 2026-03-06*
