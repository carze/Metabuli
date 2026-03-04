# Phase 1: Testing Framework - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a mini FASTA corpus and regression shell script that runs green on the unmodified binary.
Both "builds" in Phase 1 use the same (current, sequential) binary on the same corpus — proving
the harness itself is deterministic. This baseline is what Phase 3's correctness is measured against.
New capabilities (CI wiring, performance improvements) are out of scope for this phase.

</domain>

<decisions>
## Implementation Decisions

### Test corpus design
- Fully synthetic sequences — no real NCBI data, no external dependencies, fully reproducible
- Static hand-written .fasta files committed directly to the repo (zero build-time generation step)
- 3 FASTA files; at least one species has sequences distributed across two different files
  (this is the multi-file lookup path that the offset index must handle correctly)
- Sequences are 500–1000 bp each
- ~10 accessions total, ~4 species

### Taxonomy data
- Fully synthetic names.dmp, nodes.dmp, and NCBI-format accession2taxid committed to the repo
- Accession2taxid format: `accession.version\ttaxid` (tab-separated, NCBI standard)
- Lives at `test/data/taxonomy/` — co-located with the FASTA corpus

### Repo layout
- New `test/` directory at repo root (not util/Metabuli-regression/ — that stays empty)
- FASTA corpus: `test/data/`
- Taxonomy: `test/data/taxonomy/`
- Regression script: `test/regression_fasta_access.sh`

### Script invocation
- Binary path is the first positional argument: `./test/regression_fasta_access.sh ./build/metabuli`
- Both builds use the same binary against itself (proves harness determinism in Phase 1;
  Phase 3 validates by rebuilding after the refactor and re-running)
- Output: minimal — PASS on success; FAIL + first differing byte offset on file mismatch;
  FAIL + which build on validateDatabase failure
- Cleanup: always remove temp build directories after the run

### Buffer flush forcing
- Use `--threads 1 --max-ram 1` — the 1 GB RAM limit forces frequent flushing even with
  the tiny synthetic corpus
- No explicit flush count verification; non-empty split files imply flushing occurred

### Output file comparison
- Compare exactly: `diffIdx`, `info`, `split` (via `cmp -s`) — per REGTEST-02
- Do NOT compare `taxID_list` or `db.parameters` (db.parameters contains a timestamp)

### validateDatabase
- Run on both builds before the byte comparison
- Exit non-zero immediately with a clear message if validateDatabase fails on either build
  (e.g. `FAIL: validateDatabase failed on build1`)

### CI wiring
- Not wired into Azure Pipelines in Phase 1 — standalone script only
- CI integration deferred to a later phase

### Claude's Discretion
- Exact synthetic nucleotide sequences (any valid ACGT content of the right length)
- Exact taxid values and taxonomy hierarchy shape in synthetic taxonomy
- Shell scripting style (bash, set -e, etc.)
- Exact temp directory naming within the script

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `validateDatabase` command: takes a single `dbDir` argument, returns exit code 0 on pass —
  invoke as `$BINARY validateDatabase $DIR`
- `build` command: standard invocation is `$BINARY build $DBDIR --threads 1 --max-ram 1` with
  FASTA files as positional input after taxonomy setup

### Established Patterns
- No existing test/ directory or shell-based regression tests in the repo
- `util/Metabuli-regression/` exists but is empty — the new test/ structure is independent
- Azure Pipelines already sets `regression: 1` variable, but does not invoke any script yet

### Integration Points
- The script tests the `build` and `validateDatabase` subcommands of the metabuli binary
- Output files checked: `diffIdx` (16-bit delta-encoded k-mer index), `info` (k-mer ID metadata),
  `split` (flush boundary markers)
- `db.parameters` also produced but excluded from comparison (contains build timestamp)

</code_context>

<specifics>
## Specific Ideas

- No specific requirements — open to standard approaches for script structure
- The key correctness property: same binary, same corpus, same flags → byte-identical diffIdx/info/split

</specifics>

<deferred>
## Deferred Ideas

- CI wiring into Azure Pipelines — not Phase 1 scope
- Comparing taxID_list in regression — could add later if there's a correctness incident there

</deferred>

---

*Phase: 01-testing-framework*
*Context gathered: 2026-03-04*
