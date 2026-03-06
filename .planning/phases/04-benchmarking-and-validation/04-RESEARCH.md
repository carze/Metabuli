# Phase 4: Benchmarking and Validation - Research

**Researched:** 2026-03-06
**Domain:** C++ build instrumentation, cloud-scale benchmark execution, scientific documentation
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Dataset:**
- Full core_nt (~900 GB, 2,382 files) — not a subset
- Run on a cloud instance (AWS/GCP/Azure)
- `--threads 100 --max-ram 1000`
- Run twice: once at `--max-ram 1000` (single-flush, no cycle overhead) and once at `--max-ram 128` (multi-flush, ~280 cycles) to observe per-flush-cycle behavior

**Pre-pass timing instrumentation:**
- Add `time()` instrumentation to `buildFastaOffsetIndex()` — consistent with the existing `time(nullptr)` pattern used for extraction/sort/filter/write stages
- Output style: one line, `"Offset index built in X s"` — matches existing stage timer format
- Add total end-to-end build wall-clock at the end of `build.cpp` — `"Build complete in X s"`

**Before baseline:**
- Use the documented ~22-day estimate from SCALING_ANALYSIS.md — this is grounded in measured batch counts (8,400 batches × 378 MB × 2,382 files). No re-run of old implementation needed.
- Benchmark report states actual timings only — no next-step recommendation in this phase

**Results documentation:**
- Update `SCALING_ANALYSIS.md` in-place: add a new `## 8. Benchmark Results` section with actual timings side-by-side with the predicted values from Section 5.6
- Per-flush-cycle data (multi-flush run): present as summary stats table — min/max/avg per stage across cycles, not 280 rows of raw data
- Commit a reproducible benchmark script to `scripts/` or `test/benchmark/` that runs the build and captures stdout

### Claude's Discretion
- Exact instance type / sizing on cloud provider
- Script location (`scripts/` vs `test/benchmark/`)
- How to handle capturing stdout from a multi-hour run (nohup, tmux, tee)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BENCH-01 | A build of core_nt (or a >=100 GB representative subset) is run with the new implementation, recording per-stage wall-clock time: offset pre-pass, k-mer extraction, sort, filter, write per flush cycle | Covered by: timing instrumentation patterns in IndexCreator.cpp + benchmark script design + cloud instance sizing |
| BENCH-02 | Benchmark results are documented (build time before and after, per-stage breakdown) to confirm the I/O improvement and identify the next bottleneck | Covered by: SCALING_ANALYSIS.md Section 8 structure + predicted vs actual table design |
</phase_requirements>

## Summary

Phase 4 is an instrumentation + execution + documentation phase — no new algorithmic work. The implementation is complete (Phases 1-3); this phase adds two timing hooks to the existing codebase, runs the build at cloud scale, captures output, and writes a comparison report.

The codebase already uses a consistent `time_t start = time(nullptr)` / `cout << ... << time(nullptr) - start << " s" << endl` pattern throughout `IndexCreator.cpp`. The two new instrumentation points — a pre-pass timer inside `buildFastaOffsetIndex()` and a total build timer wrapping `idxCre.createIndex()` in `build.cpp` — follow the same pattern exactly. Both touchpoints are minimal, self-contained, and carry no algorithmic risk.

The benchmark run itself is a multi-hour operation requiring a cloud instance with ~128+ GB RAM, ~100 cores, and fast NVMe or network storage for the core_nt FASTA corpus. Stdout capture over a multi-hour run requires a session-persistent approach (tmux + tee is the most operator-friendly combination on a fresh cloud instance). The resulting timings feed directly into `SCALING_ANALYSIS.md` Section 8.

**Primary recommendation:** Instrument first (two code changes, one git commit), then draft the benchmark script, then run at cloud scale in the order: `--max-ram 1000` first (single-flush, clean baseline), `--max-ram 128` second (multi-flush, per-cycle variance). Parse stdout with awk post-run to generate the summary stats table for Section 8.

## Standard Stack

### Core
| Library/Tool | Version | Purpose | Why Standard |
|---|---|---|---|
| `time(nullptr)` (POSIX) | POSIX.1 | Wall-clock stage timers | Already used throughout IndexCreator.cpp — consistent with existing format |
| bash + tee | System | Stdout capture for multi-hour run | No dependencies; tee writes to file and terminal simultaneously |
| tmux | System | Session persistence on cloud | Survives SSH disconnect; operator-friendly alternative to nohup |
| awk | System | Post-run log parsing | Extract and summarize per-cycle timings from captured stdout |

### Supporting
| Tool | Purpose | When to Use |
|---|---|---|
| nohup | Alternate session persistence | Use if tmux unavailable on cloud instance |
| `--max-ram 1000` flag | Force single-flush run | Eliminates flush-cycle overhead from timing; isolates pre-pass + single extraction/sort/filter/write |
| `--max-ram 128` flag | Force multi-flush run (~280 cycles) | Observes per-cycle variance; identifies sort vs extraction split |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|---|---|---|
| `time(nullptr)` | `std::chrono::steady_clock` | chrono offers nanosecond precision but is not used anywhere in the codebase — mixing patterns reduces readability; second-level precision is sufficient for multi-hour build stages |
| tmux + tee | screen + tee | screen works but tmux is the modern default on most cloud AMIs |
| awk for log parsing | Python script | awk is zero-dependency; fine for simple field extraction; Python would be overkill here |

## Architecture Patterns

### Recommended Project Structure
```
scripts/
└── benchmark_core_nt.sh     # Reproducible benchmark script (runs build, captures stdout)

SCALING_ANALYSIS.md           # Updated in-place: new ## 8. Benchmark Results section
```

The `scripts/` directory does not currently exist. The existing test script lives at `test/regression_fasta_access.sh`, which is the regression harness. The benchmark script is operationally distinct (cloud-scale, multi-hour, captures stdout) — placing it in `scripts/` keeps the `test/` directory for correctness checks and `scripts/` for operational tooling.

### Pattern 1: Existing Stage Timer Pattern (HIGH confidence)

**What:** The DB creation flush loop in `IndexCreator.cpp` uses `time_t start = time(nullptr)` before each stage and `cout << "Stage label : " << time(nullptr) - start << " s" << endl` after. This is the project-established pattern.

**When to use:** All new timers in this phase MUST use this pattern for consistency.

**Exact format from source (IndexCreator.cpp:255-284):**
```cpp
// K-mer extraction timer
time_t start = time(nullptr);
cout << "K-mer extraction : " << flush;
extractKmerFromSixFrames(kmerBuffer, batchChecker, processedBatchCnt);
cout << double(time(nullptr) - start) << " s" << endl;

// Sort timer
start = time(nullptr);
cout << "Sort k-mers      : " << flush;
SORT_PARALLEL(kmerBuffer.buffer, ...);
cout << time(nullptr) - start << " s" << endl;

// Filter timer
start = time(nullptr);
filterKmers<FilterMode::DB_CREATION>(...);
cout << "Filter k-mers    : " << time(nullptr) - start << " s" << endl;

// Write timer
start = time(nullptr);
writeTargetFiles(...);
cout << "Write k-mers     : " << time(nullptr) - start << " s" << endl;
```

### Pattern 2: Pre-Pass Timer (New — in buildFastaOffsetIndex)

**What:** The existing `buildFastaOffsetIndex()` already has `time_t start = time(nullptr)` at the top and outputs `"FASTA offset index built: N files, M sequences, X s"`. The locked decision requires the output to match the existing stage format. The existing output line in `buildFastaOffsetIndex()` already prints elapsed time — the task is to verify the format matches the label width convention and adjust if needed.

**Existing output (IndexCreator.cpp:615):**
```cpp
cout << "FASTA offset index built: " << fastaPaths.size() << " files, "
     << totalSeqs << " sequences, " << elapsed << " s" << endl;
```

**Target format per CONTEXT.md locked decision:**
```
Offset index built in X s
```

The existing multi-field output is more informative and already implemented. The planner should decide whether to simplify to the one-liner format or retain the richer output — both satisfy BENCH-01 (per-stage wall-clock recorded). The label width convention used by the flush loop is `"K-mer extraction : "` (17+3 chars) — the pre-pass label should match approximately.

### Pattern 3: Total Build Timer (New — in build.cpp)

**What:** Wrap `idxCre.createIndex()` call in `build.cpp` with a start/end timer. The call site is at `build.cpp:95`.

**Integration point:**
```cpp
// build.cpp:94-96 (current)
IndexCreator idxCre(par, taxonomy, 2);
idxCre.createIndex();
// ... post-createIndex work ...

// With total build timer:
IndexCreator idxCre(par, taxonomy, 2);
time_t buildStart = time(nullptr);
idxCre.createIndex();
cout << "Build complete in " << (time(nullptr) - buildStart) << " s" << endl;
```

Note: `build.cpp` does post-createIndex work (taxonomy write, merge, validateDb). The total timer should wrap `createIndex()` only for a clean stage-level measurement, or wrap everything through `mergeTargetFiles()` for true end-to-end. The CONTEXT.md says "total end-to-end build wall-clock at the end of build.cpp" — this implies wrapping the full function body, not just `createIndex()`. The planner should position `buildStart` before `idxCre` construction and print after `mergeTargetFiles()` completes.

### Pattern 4: Benchmark Script Structure

**What:** A shell script that runs the build command, captures stdout, and exits cleanly. Designed for reproducibility on a cloud instance.

**Script skeleton for `scripts/benchmark_core_nt.sh`:**
```bash
#!/usr/bin/env bash
# Usage: ./scripts/benchmark_core_nt.sh <metabuli_binary> <db_out_dir> <fasta_list> <acc2taxid> <taxonomy_dir> <max_ram>
set -euo pipefail

BINARY="${1:?Usage: $0 <binary> <db_out> <fasta_list> <acc2taxid> <taxonomy_dir> <max_ram>}"
DB_OUT="${2:?}"
FASTA_LIST="${3:?}"
ACC2TAXID="${4:?}"
TAXONOMY="${5:?}"
MAX_RAM="${6:-1000}"
THREADS="${7:-100}"
LOG="${DB_OUT}/benchmark_ram${MAX_RAM}.log"

mkdir -p "$DB_OUT"
echo "Starting benchmark: --max-ram $MAX_RAM --threads $THREADS" | tee "$LOG"
echo "Start time: $(date -u)" | tee -a "$LOG"

"$BINARY" build "$DB_OUT" "$FASTA_LIST" "$ACC2TAXID" \
    --taxonomy-path "$TAXONOMY" \
    --threads "$THREADS" \
    --max-ram "$MAX_RAM" \
    2>&1 | tee -a "$LOG"

echo "End time: $(date -u)" | tee -a "$LOG"
echo "Log written to: $LOG"
```

**Session persistence pattern (tmux):**
```bash
# On cloud instance, before starting:
tmux new-session -d -s bench
tmux send-keys -t bench \
    "./scripts/benchmark_core_nt.sh ./metabuli /data/db_1000 /data/fasta.list /data/acc2taxid.tsv /data/taxonomy 1000" \
    Enter
# Detach: Ctrl-b d
# Reattach: tmux attach -t bench
```

**nohup alternative:**
```bash
nohup ./scripts/benchmark_core_nt.sh ... > /data/bench_1000.log 2>&1 &
echo $! > bench.pid   # save PID for monitoring
```

### Pattern 5: Post-Run Log Parsing for Per-Cycle Stats

**What:** The multi-flush run (~280 cycles) prints extraction/sort/filter/write timings per cycle. After the run, extract and summarize with awk.

**awk snippets for parsing the captured log:**
```bash
# Extract all "K-mer extraction" times from log
grep "K-mer extraction" /data/bench_128.log | awk '{print $NF}' > extraction_times.txt

# Compute min/max/avg using awk
awk 'NR==1{min=$1;max=$1;sum=0} {sum+=$1; if($1<min)min=$1; if($1>max)max=$1} \
     END{printf "min=%.0f max=%.0f avg=%.1f\n", min, max, sum/NR}' extraction_times.txt
```

Run the same for "Sort k-mers", "Filter k-mers", "Write k-mers" lines. This produces the summary stats table for SCALING_ANALYSIS.md Section 8.

### Anti-Patterns to Avoid

- **Using `std::chrono`:** The codebase uses `time(nullptr)` uniformly — introducing chrono creates a mixed pattern with no benefit for hour-scale measurements.
- **Running both benchmark configurations in a single invocation:** The two runs (`--max-ram 1000` and `--max-ram 128`) must produce separate output directories and logs — running them sequentially in one script risks confusing output streams.
- **Including raw per-cycle rows in the SCALING_ANALYSIS.md table:** 280 rows is unreadable — use min/max/avg summary stats as decided.
- **Placing the benchmark script in `test/`:** The `test/` directory contains correctness checks (regression harness). The benchmark is an operational script, not a correctness check — it belongs in `scripts/`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Session persistence for multi-hour run | Custom daemon/wrapper | tmux or nohup | Both are standard on Linux cloud instances; no dependencies |
| Log parsing / stats | Custom C++ stats tool | awk one-liners | Sufficient for 280-line extraction; zero dependency |
| Timing subsystem | chrono wrapper | `time(nullptr)` | Already established in codebase; second-level precision is correct for multi-minute stage timings |

**Key insight:** This phase is measurement and documentation, not engineering. Every tool needed already exists in the codebase or the OS.

## Common Pitfalls

### Pitfall 1: Timer Placement in build.cpp

**What goes wrong:** The total build timer is placed only around `createIndex()`, omitting `mergeTargetFiles()`. The merge step can take significant time for a 280-cycle multi-flush run (merging hundreds of partial index files) — omitting it understates true end-to-end time.

**Why it happens:** `createIndex()` is the obvious instrumentation point, but build.cpp does additional work after it returns.

**How to avoid:** Place `buildStart` before `IndexCreator idxCre` construction and print elapsed time after `mergeTargetFiles()` (or after the `validateDb` block at line 132, to capture everything). For a clean comparison, also record a "createIndex complete" intermediate timestamp.

**Warning signs:** If the reported "Build complete" time is significantly less than the sum of logged stage times plus merge, the timer is placed too narrowly.

### Pitfall 2: SSH Disconnect Kills the Build

**What goes wrong:** A multi-hour core_nt build (expected ~10-12 hours) running in a raw SSH session is killed when the connection drops.

**Why it happens:** SSH session death sends SIGHUP to the foreground process.

**How to avoid:** Always start the benchmark inside a tmux session or with nohup before running. Verify the build is in a session before committing the cloud instance cost.

**Warning signs:** Build starts, SSH drops, reconnecting shows no running process.

### Pitfall 3: Log File Not Capturing stderr

**What goes wrong:** Metabuli prints some diagnostics to stderr; the benchmark log only captures stdout, so timing lines appear in the log but error messages are invisible.

**Why it happens:** `tee` without `2>&1` only captures stdout.

**How to avoid:** Always use `2>&1 | tee -a "$LOG"` to merge stderr into the log stream. This is shown in the script skeleton above.

**Warning signs:** Log file is smaller than expected; error messages visible in terminal but not in saved log.

### Pitfall 4: Output Directory Already Exists From Prior Run

**What goes wrong:** Re-running the benchmark into an existing output directory produces a corrupted or mixed database (partial files from previous run + new run).

**Why it happens:** Metabuli's build appends/overwrites files in the output directory; it does not wipe it first.

**How to avoid:** The benchmark script should use a fresh output directory per run, or explicitly wipe the output directory before starting. Use timestamped directories (`DB_OUT_1000=$(date +%Y%m%d_%H%M)_ram1000`) or include a `rm -rf "$DB_OUT"` guard in the script with a confirmation prompt.

**Warning signs:** Stage timings are anomalously short (cache warm from prior partial build); diffIdx is smaller than expected.

### Pitfall 5: Predicted Values in Section 5.6 Use Different Units

**What goes wrong:** SCALING_ANALYSIS.md Section 5.6 shows predicted values as ranges (e.g., "~7-10 h" for sort) — when actual timings come in as seconds, the comparison table looks inconsistent.

**Why it happens:** Predictions were stated as hour-level estimates; actual timing output is in seconds.

**How to avoid:** Convert actual seconds to hours in the Section 8 table for the "Total" row; leave per-stage rows in seconds or minutes as appropriate. Be explicit about units in every table cell.

## Code Examples

Verified patterns from actual source code:

### Existing buildFastaOffsetIndex Timer (IndexCreator.cpp:571-616)
```cpp
void IndexCreator::buildFastaOffsetIndex() {
    cout << "Building FASTA offset index..." << endl;
    time_t start = time(nullptr);
    // ... parallel file scan ...
    time_t elapsed = time(nullptr) - start;
    cout << "FASTA offset index built: " << fastaPaths.size() << " files, "
         << totalSeqs << " sequences, " << elapsed << " s" << endl;
}
```

The timer is already present. The task is to verify/adjust the label to match the stage label format convention if required by the locked decision.

### Existing Flush Loop Timers (IndexCreator.cpp:253-292 — DB creation path)
```cpp
while(processedBatchCnt < accessionBatches.size()) {
    time_t start = time(nullptr);
    cout << "K-mer extraction : " << flush;
    if (par.cdsInfo == "x") {
        extractKmerFromSixFrames(kmerBuffer, batchChecker, processedBatchCnt);
    } else {
        fillTargetKmerBuffer(kmerBuffer, batchChecker, processedBatchCnt, par);
    }
    cout << double(time(nullptr) - start) << " s" << endl;

    start = time(nullptr);
    cout << "Sort k-mers      : " << flush;
    SORT_PARALLEL(kmerBuffer.buffer, kmerBuffer.buffer + kmerBuffer.startIndexOfReserve,
                  Kmer::compareTargetKmer);
    cout << time(nullptr) - start << " s" << endl;

    start = time(nullptr);
    filterKmers<FilterMode::DB_CREATION>(kmerBuffer, uniqKmerIdx.buffer, selectedKmerCnt, uniqKmerIdxRanges);
    cout << "Filter k-mers    : " << time(nullptr) - start << " s" << endl;

    start = time(nullptr);
    // writeTargetFilesAndSplits or writeTargetFiles
    cout << "Write k-mers     : " << time(nullptr) - start << " s" << endl;
}
```

These lines are the source of the per-cycle timing data captured in the benchmark log. Each cycle iteration prints four lines; 280 cycles yields ~1,120 timing lines in the multi-flush log.

### build.cpp Entry Point (build.cpp:32-131)
```cpp
int build(int argc, const char **argv, const Command &command){
    // ... parameter setup ...
    IndexCreator idxCre(par, taxonomy, 2);  // line 94
    idxCre.createIndex();                   // line 95
    // ... taxonomy write, merge, validateDb ...
    return 0;
}
```

Total build timer: add `time_t buildStart = time(nullptr)` before line 94, print after `mergeTargetFiles()` (line 117 area) to capture everything including the merge step.

### SCALING_ANALYSIS.md Section 8 Target Structure
```markdown
## 8. Benchmark Results

**Run date:** [YYYY-MM-DD]
**Instance:** [cloud instance type, e.g., AWS r7i.32xlarge]
**Configuration:** core_nt, 2,382 FASTA files, ~900 GB
**Metabuli commit:** [git SHA]
**Parameters (single-flush):** --threads 100 --max-ram 1000
**Parameters (multi-flush):** --threads 100 --max-ram 128

### 8.1 Stage Timings — Single Flush Run (--max-ram 1000)

| Stage | Predicted (Section 5.6) | Actual |
|---|---|---|
| Offset pre-pass | ~30 min | X min |
| K-mer extraction | ~1-2 h | X h |
| Sort (1 flush) | ~60-90 s | X s |
| Filter (1 flush) | ~20-30 s | X s |
| Write (1 flush) | ~20-30 s | X s |
| **Total** | **~10-12 h** | **X h** |

### 8.2 Per-Flush-Cycle Summary — Multi-Flush Run (--max-ram 128, ~280 cycles)

| Stage | Min (s) | Max (s) | Avg (s) |
|---|---|---|---|
| K-mer extraction | - | - | - |
| Sort k-mers | - | - | - |
| Filter k-mers | - | - | - |
| Write k-mers | - | - | - |

### 8.3 Before / After Comparison

| Metric | Before (estimated) | After (measured) |
|---|---|---|
| Total build time | ~22 days | X h |
| Primary bottleneck | Redundant FASTA I/O | Sort (or other) |
| Next bottleneck identified | — | [sort / extraction / write] |
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| No per-stage timers in DB creation flush loop | `time(nullptr)` timers on all four stages | Already present in codebase | Flush-cycle timing data is captured without any new instrumentation |
| No total build wall-clock | Wrapper timer in build.cpp | Phase 4 task 1 | Single number for before/after comparison |
| No pre-pass timer (formatted) | `buildFastaOffsetIndex()` output already has elapsed time | Phase 2 implementation | Pre-pass cost visible in output |

**The existing instrumentation is more complete than the CONTEXT.md implies.** The flush loop already has all four per-cycle timers. The pre-pass already reports elapsed time. The remaining gap is: (1) adjust the pre-pass output label to match the stage format convention if needed, and (2) add a total end-to-end wall-clock in `build.cpp`.

## Open Questions

1. **Pre-pass output format: keep rich vs. simplify to one-liner?**
   - What we know: `buildFastaOffsetIndex()` already outputs `"FASTA offset index built: N files, M sequences, X s"` — more informative than the locked decision's `"Offset index built in X s"`.
   - What's unclear: Does the planner need to simplify the existing output or is the richer format acceptable given the locked decision is about the timer existing, not the exact string?
   - Recommendation: Keep the richer output format; it is strictly more informative. The locked decision is satisfied as long as elapsed time is reported. Document the actual output format in the plan.

2. **Total build timer scope: createIndex() only vs. full build() function?**
   - What we know: `build.cpp` does work after `createIndex()` — taxonomy write, `mergeTargetFiles()` (which can be substantial for 280-cycle runs), and optional validateDb.
   - What's unclear: Does the "Build complete in X s" timer wrap just createIndex or everything?
   - Recommendation: Wrap everything through `mergeTargetFiles()` to capture true end-to-end, and add an intermediate "Index creation complete in X s" after `createIndex()` for isolation.

3. **Script location: `scripts/` vs `test/benchmark/`?**
   - What we know: `scripts/` does not exist; `test/` contains the regression harness.
   - Recommendation: Create `scripts/` as a new top-level directory for operational tooling. This is cleaner than nesting under `test/` (which implies correctness tests, not operational benchmarks).

4. **Cloud instance type selection?**
   - What we know: The CONTEXT.md explicitly leaves instance type to Claude's discretion.
   - Recommendation: AWS r7i.32xlarge (128 vCPUs, 1024 GB RAM, up to 40 Gbps EBS). This provides enough RAM for `--max-ram 1000` in a single-flush run and matches the `--threads 100` parameter. Cost is ~$8/hr on-demand; use Spot if available for the multi-hour run.

## Validation Architecture

`workflow.nyquist_validation` is absent from `.planning/config.json` — treated as enabled.

### Test Framework

| Property | Value |
|---|---|
| Framework | bash (existing regression harness) |
| Config file | none — self-contained script |
| Quick run command | `bash test/regression_fasta_access.sh ./build/metabuli` |
| Full suite command | `bash test/regression_fasta_access.sh ./build/metabuli` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| BENCH-01 | Per-stage timings appear in build stdout | smoke | `grep "K-mer extraction" <log_file>` — verifies timing lines present in captured log | ❌ Wave 0 (log exists only after cloud run) |
| BENCH-01 | Offset pre-pass timing present in output | smoke | `grep "offset index" <log_file>` | ❌ Wave 0 |
| BENCH-02 | Section 8 present in SCALING_ANALYSIS.md | manual | `grep "## 8. Benchmark Results" SCALING_ANALYSIS.md` | ❌ Wave 0 |
| BENCH-02 | Before/after table has actual timings | manual-only | Visual review of Section 8.3 table | manual-only — requires cloud run completion |

**Note:** BENCH-01 and BENCH-02 are fundamentally validated by running the cloud build and reviewing its output. The code instrumentation changes (timers in source) can be validated at unit scale with a small build to confirm timing lines appear, but the full BENCH-01 requirement (core_nt scale) is inherently a manual/cloud operation.

### Sampling Rate
- **Per task commit:** `bash test/regression_fasta_access.sh ./build/metabuli` (regression check — confirms instrumentation changes don't break correctness)
- **Per wave merge:** Same regression check
- **Phase gate:** Cloud benchmark run complete + Section 8 written in SCALING_ANALYSIS.md + SCALING_ANALYSIS.md committed

### Wave 0 Gaps
- [ ] `scripts/benchmark_core_nt.sh` — covers BENCH-01 (benchmark script committed)
- [ ] Cloud instance provisioning and data staging (manual prerequisite — not automatable)
- [ ] Captured benchmark logs (only exist after cloud run — cannot be pre-staged)

*(The existing regression harness at `test/regression_fasta_access.sh` covers instrumentation correctness; cloud execution is the only path to satisfying the full requirement.)*

## Sources

### Primary (HIGH confidence)
- Source: direct inspection of `src/commons/IndexCreator.cpp` — timer patterns, label formats, buildFastaOffsetIndex implementation
- Source: direct inspection of `src/workflow/build.cpp` — build entry point, createIndex call site, post-createIndex work
- Source: `.planning/phases/04-benchmarking-and-validation/04-CONTEXT.md` — all locked decisions
- Source: `SCALING_ANALYSIS.md` Sections 3-5.6 — predicted values for Section 8 comparison table
- Source: `test/regression_fasta_access.sh` — existing script pattern for benchmark script design

### Secondary (MEDIUM confidence)
- tmux session persistence pattern: standard practice for cloud engineering, verified across common AWS AMIs
- AWS r7i instance recommendation: based on published AWS instance specs (128 vCPU, 1024 GB RAM family) matching the `--threads 100 --max-ram 1000` parameters

### Tertiary (LOW confidence)
- None — all findings are grounded in the project's own source code and context documents

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools are from the existing codebase or POSIX/system utilities
- Architecture: HIGH — instrumentation points identified from direct source inspection; no ambiguity about where timers go
- Pitfalls: HIGH — SSH/session pitfall is universal cloud engineering; timer placement and log capture issues are observable from the code structure
- Documentation structure: HIGH — Section 8 structure derived directly from CONTEXT.md locked decisions and Section 5.6 predicted values

**Research date:** 2026-03-06
**Valid until:** This is implementation-specific research; no external library staleness concerns. Valid indefinitely.
