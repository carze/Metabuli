# Phase 1: Testing Framework - Research

**Researched:** 2026-03-04
**Domain:** Shell-based regression harness + synthetic FASTA corpus for Metabuli build determinism
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Fully synthetic sequences — no real NCBI data, no external dependencies, fully reproducible
- Static hand-written .fasta files committed directly to the repo (zero build-time generation step)
- 3 FASTA files; at least one species has sequences distributed across two different files
- Sequences are 500–1000 bp each
- ~10 accessions total, ~4 species
- Fully synthetic names.dmp, nodes.dmp, and NCBI-format accession2taxid committed to the repo
- Lives at `test/data/taxonomy/` — co-located with the FASTA corpus
- New `test/` directory at repo root (not util/Metabuli-regression/ — that stays empty)
- FASTA corpus: `test/data/`
- Taxonomy: `test/data/taxonomy/`
- Regression script: `test/regression_fasta_access.sh`
- Binary path is the first positional argument: `./test/regression_fasta_access.sh ./build/metabuli`
- Both builds use the same binary against itself
- Output: minimal — PASS on success; FAIL + first differing byte offset on file mismatch; FAIL + which build on validateDatabase failure
- Cleanup: always remove temp build directories after the run
- Use `--threads 1 --max-ram 1` — the 1 GB RAM limit forces frequent flushing
- No explicit flush count verification; non-empty split files imply flushing occurred
- Compare exactly: `diffIdx`, `info`, `split` (via `cmp -s`) — per REGTEST-02
- Do NOT compare `taxID_list` or `db.parameters`
- Run validateDatabase on both builds before the byte comparison
- Exit non-zero immediately with a clear message if validateDatabase fails
- CI wiring NOT in Phase 1 — standalone script only

### Claude's Discretion
- Exact synthetic nucleotide sequences (any valid ACGT content of the right length)
- Exact taxid values and taxonomy hierarchy shape in synthetic taxonomy
- Shell scripting style (bash, set -e, etc.)
- Exact temp directory naming within the script

### Deferred Ideas (OUT OF SCOPE)
- CI wiring into Azure Pipelines — not Phase 1 scope
- Comparing taxID_list in regression — could add later
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REGTEST-01 | Mini-corpus of ~3 uncompressed FASTA files, ~4 species, ~10 accessions in `test/data/`; at least one species spans two FASTA files; `--max-ram 1` forces 2+ buffer flushes | Corpus design and taxonomy format details documented in §Standard Stack and §Code Examples |
| REGTEST-02 | Shell script `test/regression_fasta_access.sh` builds same database twice with `--threads 1 --max-ram 1`, byte-compares `diffIdx`, `info`, `split` with `cmp -s` | Build invocation, cmp usage, and script structure documented in §Architecture Patterns |
| REGTEST-03 | `metabuli validateDatabase` passes on both builds | validateDatabase invocation and exit code documented in §Standard Stack |
| REGTEST-04 | Script exits non-zero and prints first differing byte offset if any output file differs | `cmp` (non-silent) usage for offset extraction documented in §Common Pitfalls and §Code Examples |
</phase_requirements>

## Summary

Phase 1 creates a self-contained regression harness that proves the Metabuli `build` pipeline is deterministic on a controlled synthetic corpus. The harness is a standalone bash script that runs the same binary twice against the same corpus and byte-compares three output files (`diffIdx`, `info`, `split`). A passing harness in Phase 1 establishes the baseline that Phase 3 will use to verify correctness after the fseeko refactor.

The primary complexity in this phase is getting the input file formats exactly right for the Metabuli build pipeline. The `accession2taxid` file must be 4-column NCBI format (not 2-column), with a mandatory header line. The FASTA list file is a newline-separated list of absolute paths (not direct FASTA arguments on the command line). The taxonomy directory must contain `names.dmp`, `nodes.dmp`, and `merged.dmp` in NCBI dump format — all three are required; a missing `merged.dmp` causes a hard failure.

The script structure is straightforward: build twice into separate temp directories, run validateDatabase on each, byte-compare the three output files, clean up. The main pitfall to avoid is using `cmp -s` (silent mode) for the comparison that must also report the byte offset — `cmp -s` only returns an exit code, it does not print anything. Byte offset reporting requires running `cmp` without `-s`.

**Primary recommendation:** Write the script with `set -euo pipefail`, use `cmp` (not `cmp -s`) to get byte offset output, and validate the accession2taxid format against the 4-column NCBI schema before integration testing.

## Standard Stack

### Core
| Tool/Format | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| bash | ≥4.0 | Script interpreter | Universal on Linux/macOS; Azure Pipelines Ubuntu 22.04 uses bash |
| `cmp` | POSIX | Byte-by-byte file comparison | Built-in to all POSIX systems; reports byte offset on mismatch |
| NCBI names.dmp | NCBI taxdump | Taxonomy node names | Required by Metabuli's TaxonomyWrapper (names, nodes, merged) |
| NCBI nodes.dmp | NCBI taxdump | Taxonomy node hierarchy | Required; defines parent-child taxid relationships |
| NCBI merged.dmp | NCBI taxdump | Merged node records | Required by validateDatabase check; missing = hard failure |
| NCBI accession2taxid | NCBI standard | 4-column mapping: accession, accession.version, taxid, gi | Parsed by `getTaxonomyOfAccessions()` using `%s\t%*s\t%d\t%*d` |

### Build Command Invocation
```bash
# Full signature (verified from README.md and build.cpp)
$BINARY build <DBDIR> <FASTA_LIST> <accession2taxid> --taxonomy-path <TAXDUMP_DIR> \
    --threads 1 --max-ram 1
```

Where:
- `FASTA_LIST` = newline-separated file of **absolute paths** to FASTA files
- `accession2taxid` = 4-column NCBI format file with header (see §Code Examples)
- `--taxonomy-path` = directory containing names.dmp, nodes.dmp, merged.dmp
- Without `--taxonomy-path`, Metabuli looks inside `<DBDIR>/taxonomy/` — both approaches work

### validateDatabase Invocation
```bash
$BINARY validateDatabase <DBDIR>
# Returns 0 on success, non-zero on failure
# Checks: file presence, diffIdx size divisible by 2, k-mer count matches info entry count
```

## Architecture Patterns

### Recommended File Layout
```
test/
├── data/
│   ├── seq1.fasta            # 3-4 accessions, species A and B
│   ├── seq2.fasta            # 3-4 accessions, species B (cross-file) and C
│   ├── seq3.fasta            # 2-3 accessions, species D
│   ├── fasta.list            # newline-separated absolute paths to the 3 fasta files
│   ├── accession2taxid.tsv   # 4-column NCBI format with header
│   └── taxonomy/
│       ├── names.dmp
│       ├── nodes.dmp
│       └── merged.dmp
└── regression_fasta_access.sh
```

### Pattern 1: Script Skeleton
**What:** `set -euo pipefail` harness with positional binary argument, two build runs, validate+compare, cleanup-on-exit trap.
**When to use:** Any shell regression script that must be portable and robust.

```bash
#!/usr/bin/env bash
set -euo pipefail

BINARY="${1:?Usage: $0 <path-to-metabuli-binary>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

BUILD1=$(mktemp -d)
BUILD2=$(mktemp -d)
trap 'rm -rf "$BUILD1" "$BUILD2"' EXIT

# Build step (run twice)
"$BINARY" build "$BUILD1" "$DATA_DIR/fasta.list" \
    "$DATA_DIR/accession2taxid.tsv" \
    --taxonomy-path "$DATA_DIR/taxonomy" \
    --threads 1 --max-ram 1

"$BINARY" build "$BUILD2" "$DATA_DIR/fasta.list" \
    "$DATA_DIR/accession2taxid.tsv" \
    --taxonomy-path "$DATA_DIR/taxonomy" \
    --threads 1 --max-ram 1

# validateDatabase step
if ! "$BINARY" validateDatabase "$BUILD1"; then
    echo "FAIL: validateDatabase failed on build1" >&2
    exit 1
fi
if ! "$BINARY" validateDatabase "$BUILD2"; then
    echo "FAIL: validateDatabase failed on build2" >&2
    exit 1
fi

# Byte-compare step
for FILE in diffIdx info split; do
    if ! cmp -s "$BUILD1/$FILE" "$BUILD2/$FILE"; then
        OFFSET=$(cmp "$BUILD1/$FILE" "$BUILD2/$FILE" 2>&1 | grep -oE 'byte [0-9]+' | grep -oE '[0-9]+' || echo "unknown")
        echo "FAIL: $FILE differs at byte offset $OFFSET" >&2
        exit 1
    fi
done

echo "PASS"
```

### Pattern 2: FASTA list file (absolute paths)
**What:** The `build` command's second argument is a file of newline-separated paths, not direct FASTA paths.
**When to use:** Always — the binary reads paths from this file at runtime.

```
# test/data/fasta.list  (generated or static — static committed to repo is preferred)
/absolute/path/to/test/data/seq1.fasta
/absolute/path/to/test/data/seq2.fasta
/absolute/path/to/test/data/seq3.fasta
```

**Implication:** The script must generate this file at runtime using the script's own absolute path, since the repo may be cloned to different locations.

```bash
# Generate fasta.list at runtime (within regression script)
FASTA_LIST=$(mktemp)
echo "$DATA_DIR/seq1.fasta" > "$FASTA_LIST"
echo "$DATA_DIR/seq2.fasta" >> "$FASTA_LIST"
echo "$DATA_DIR/seq3.fasta" >> "$FASTA_LIST"
# Add $FASTA_LIST to trap cleanup
```

### Anti-Patterns to Avoid
- **Using `cmp -s` for byte-offset reporting:** `cmp -s` is silent — it only sets the exit code. To get the byte offset, run `cmp` without `-s` and parse its output (`"file1 file2 differ: byte N, line M"`).
- **Hardcoding absolute paths in test data files:** The fasta.list must use paths computed at script runtime from the script's own location — hardcoded paths break when the repo is cloned elsewhere.
- **2-column accession2taxid:** The parser reads 4 columns (`%s\t%*s\t%d\t%*d`). A 2-column file will silently produce taxid=0 for all accessions (sequences not found in accession2taxid are silently skipped by Metabuli).
- **Missing merged.dmp:** validateDatabase code checks for `taxonomyDB` file or `taxonomy/merged.dmp`. A missing merged.dmp causes a hard error immediately.
- **Missing header line in accession2taxid:** The parser explicitly skips the first line (`// Skip the header line` in IndexCreator.cpp:605). A file without a header causes the first accession to be skipped.
- **Relative paths in fasta.list:** Metabuli opens files directly from the paths in fasta.list; relative paths will fail unless the script's CWD matches.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File comparison | Custom diff logic | `cmp` (POSIX built-in) | Byte-exact, fast, reports offset, universally available |
| Temp directory management | Manual mkdir + manual rm | `mktemp -d` + `trap ... EXIT` | Cleanup runs even on failure |
| Binary exit code capture | Custom wrappers | `if ! $BINARY ...` | Shell native; handles all exit codes |

**Key insight:** This phase is pure shell scripting and file format correctness. The complexity is entirely in getting the Metabuli input formats right — not in writing clever script logic.

## Common Pitfalls

### Pitfall 1: Wrong accession2taxid format
**What goes wrong:** Build completes with 0 k-mers indexed (empty diffIdx) because all accessions were silently skipped.
**Why it happens:** The parser expects 4-column format; 2-column input fails `sscanf("%s\t%*s\t%d\t%*d", ...)` which returns 0 (not 2), so every line is skipped silently.
**How to avoid:** Use 4-column NCBI format exactly: `accession[tab]accession.version[tab]taxid[tab]0`. Include a header line.
**Warning signs:** validateDatabase passes (files exist) but shows 0 k-mers in diffIdx, or extremely small file sizes.

### Pitfall 2: cmp -s does not print byte offset
**What goes wrong:** REGTEST-04 passes the shell comparison check but never prints the byte offset on mismatch.
**Why it happens:** `cmp -s` ("silent" flag) suppresses all output — it only sets exit code 0 (identical) or 1 (differ).
**How to avoid:** Use a two-step approach: `cmp -s` to check silently, then `cmp` (no -s) to capture the offset message on failure. Or use only `cmp` (no -s) and redirect stdout when identical output is unwanted.
**Warning signs:** Script exits 1 on mismatch with no byte offset printed.

### Pitfall 3: FASTA headers with versions stripped
**What goes wrong:** Accessions in FASTA headers don't match accession2taxid, causing all sequences to be skipped.
**Why it happens:** Metabuli's `getObservedAccessions()` strips the version suffix (truncates at `.`). The accession2taxid parser also strips versions. But if headers are written as `>ACC` (no version) and accession2taxid has `ACC[tab]ACC.1[tab]taxid[tab]0`, everything aligns.
**How to avoid:** Keep FASTA headers simple (no version needed: `>ACC_001`). In accession2taxid, the first column can match exactly, and the second column can be `ACC_001.1` or `ACC_001` — the parser reads column 2 with `%*s` (skip), so it doesn't matter.
**Warning signs:** Build produces empty or very small diffIdx.

### Pitfall 4: Non-empty split files not guaranteed at --max-ram 1
**What goes wrong:** With a tiny corpus, even `--max-ram 1` may not trigger multiple flushes.
**Why it happens:** The buffer size calculation in `common.h:183` applies a multiplier: `if (maxRam < 16) { ... }`. A 1 GB limit with very few sequences may still fit in one flush.
**How to avoid:** The CONTEXT.md decision is to accept this — "non-empty split files imply flushing occurred" but no explicit flush count verification. If split is empty after build, that means no merge step ran (single flush), which is fine for Phase 1. The multi-flush behavior is what Phase 3 correctness depends on, not Phase 1.
**Warning signs:** split file is empty (size 0) — this is acceptable for Phase 1.

### Pitfall 5: Accession ordering non-determinism with --threads > 1
**What goes wrong:** Two builds with `--threads N` (N>1) produce differing output files because OpenMP parallel sections produce different orderings across runs.
**Why it happens:** `getObservedAccessions()` uses `#pragma omp for schedule(static, 1)` with OpenMP critical sections — thread interleaving order is non-deterministic.
**How to avoid:** Always use `--threads 1` as locked in CONTEXT.md. This is the correct choice.
**Warning signs:** N/A — `--threads 1` is already the decided approach.

## Code Examples

Verified patterns from source code inspection:

### Minimal valid accession2taxid format (4-column NCBI)
```
# Source: README.md lines 461-464, IndexCreator.cpp line 629
# sscanf format: "%s\t%*s\t%d\t%*d"
accession	accession.version	taxid	gi
ACC_001	ACC_001.1	1001	0
ACC_002	ACC_002.1	1001	0
ACC_003	ACC_003.1	1002	0
```
Note: header line is mandatory (parser skips first line unconditionally).

### Minimal valid names.dmp
```
# Source: NcbiTaxonomy parsing (NCBI taxdump format)
# Format: taxid [TAB] | [TAB] name_txt [TAB] | [TAB] unique_name [TAB] | [TAB] name_class [TAB] |
1	|	root	|		|	scientific name	|
1001	|	Species A	|		|	scientific name	|
1002	|	Species B	|		|	scientific name	|
```

### Minimal valid nodes.dmp
```
# Source: NcbiTaxonomy parsing
# Format: taxid [TAB] | [TAB] parent_taxid [TAB] | [TAB] rank [TAB] | ...
1	|	1	|	no rank	|	...
1001	|	1	|	species	|	...
1002	|	1	|	species	|	...
```

### Minimal valid merged.dmp
```
# Source: validateDatabase.cpp checks for this file's existence
# Can be empty but file must exist; format: old_taxid [TAB] | [TAB] new_taxid [TAB] |
# Empty file is valid if there are no merged nodes
```

### cmp usage for byte-offset reporting
```bash
# Source: POSIX cmp man page; verified behavior
# Silent check (exit code only):
if cmp -s "$F1" "$F2"; then
    : # files are identical
else
    # Get byte offset from non-silent run:
    # cmp output format: "file1 file2 differ: byte N, line M"
    OFFSET=$(cmp "$F1" "$F2" | awk '{print $5}' | tr -d ',')
    echo "FAIL: differ at byte $OFFSET"
fi
```

### Build invocation with taxonomy path
```bash
# Source: README.md line 439, build.cpp lines 45-50, LocalParameters.cpp line 275
# --taxonomy-path overrides the default <DBDIR>/taxonomy/ lookup
"$BINARY" build "$DBDIR" "$FASTA_LIST" "$ACC2TAXID" \
    --taxonomy-path "$TAXONOMY_DIR" \
    --threads 1 --max-ram 1
```

### fasta.list generation at runtime
```bash
# Must use absolute paths — computed from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
FASTA_LIST=$(mktemp)
trap 'rm -f "$FASTA_LIST"' EXIT  # append to existing trap
printf '%s\n' \
    "$DATA_DIR/seq1.fasta" \
    "$DATA_DIR/seq2.fasta" \
    "$DATA_DIR/seq3.fasta" > "$FASTA_LIST"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| util/Metabuli-regression/ (empty) | test/ directory at repo root | Phase 1 decision | Clean separation from util scripts |
| Manual regression scripts | Bash harness with `set -euo pipefail` + trap cleanup | Phase 1 decision | Reliable cleanup even on failure |

**Existing state:**
- `util/Metabuli-regression/`: empty directory — the Azure Pipelines CI references `run_regression.sh` here but it does not exist; CI regression step always skips (condition is `eq(variables['regression'], 1)` which is set to 1, so the step runs but immediately fails since the script doesn't exist — this means Azure CI currently fails the regression step on every build)
- `azure-pipelines.yml`: already sets `regression: 1` — the new script is independent of CI wiring in Phase 1

## Open Questions

1. **Non-empty split file guarantee with --max-ram 1 on tiny corpus**
   - What we know: Buffer size for `maxRam < 16` applies a fractional multiplier (see `common.h:183-186`); with only ~10 sequences of 500-1000 bp, the total data is ~5-10 KB — almost certainly fits in a single flush even at 1 GB RAM
   - What's unclear: Whether the Phase 1 corpus design actually triggers multiple flushes, or whether split remains empty
   - Recommendation: Accept that split may be empty (single flush is fine for Phase 1 determinism). The CONTEXT.md decision already allows this: "non-empty split files imply flushing occurred" but does NOT require it. The split file comparison still runs — if split is empty in both builds, `cmp -s` exits 0 (identical empties).

2. **Azure CI regression step currently broken**
   - What we know: `azure-pipelines.yml` calls `./util/Metabuli-regression/run_regression.sh` which doesn't exist; `regression: 1` variable is set; CI step will error on every push
   - What's unclear: Whether this actually causes CI failures or the step is currently commented out / unreachable
   - Recommendation: Phase 1 does NOT wire the new script into Azure CI (locked decision). This is noted for Phase planning but no action needed in Phase 1.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash script (no external test framework) |
| Config file | none |
| Quick run command | `./test/regression_fasta_access.sh ./build/src/metabuli` |
| Full suite command | `./test/regression_fasta_access.sh ./build/src/metabuli` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REGTEST-01 | Corpus with 3 FASTA files, 10 accessions, cross-file species, 2+ flushes | smoke | `ls test/data/seq*.fasta test/data/taxonomy/names.dmp` | ❌ Wave 0 |
| REGTEST-02 | Two-build byte comparison of diffIdx, info, split | regression | `./test/regression_fasta_access.sh <BINARY>` | ❌ Wave 0 |
| REGTEST-03 | validateDatabase passes on both builds | smoke (part of regression script) | `./test/regression_fasta_access.sh <BINARY>` | ❌ Wave 0 |
| REGTEST-04 | Non-zero exit + byte offset on mismatch | regression (requires corrupted-file test) | manual verification or inject mismatch | manual-only |

### Sampling Rate
- **Per task commit:** `ls test/data/ test/data/taxonomy/` (verify files exist)
- **Per wave merge:** `./test/regression_fasta_access.sh ./build/src/metabuli` (requires built binary)
- **Phase gate:** Full script exits 0 before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/data/seq1.fasta` — covers REGTEST-01 (corpus file 1)
- [ ] `test/data/seq2.fasta` — covers REGTEST-01 (corpus file 2, cross-file species)
- [ ] `test/data/seq3.fasta` — covers REGTEST-01 (corpus file 3)
- [ ] `test/data/accession2taxid.tsv` — covers REGTEST-01 (4-column NCBI format)
- [ ] `test/data/taxonomy/names.dmp` — covers REGTEST-01
- [ ] `test/data/taxonomy/nodes.dmp` — covers REGTEST-01
- [ ] `test/data/taxonomy/merged.dmp` — covers REGTEST-01 (even if empty, file must exist)
- [ ] `test/regression_fasta_access.sh` — covers REGTEST-02, REGTEST-03, REGTEST-04

## Sources

### Primary (HIGH confidence)
- `src/commons/IndexCreator.cpp` lines 502-566 — `getObservedAccessions()` FASTA list parsing (paths from file, not positional args)
- `src/commons/IndexCreator.cpp` lines 576-654 — `getTaxonomyOfAccessions()` accession2taxid parsing (4-column sscanf format confirmed)
- `src/util/validateDatabase.cpp` — validateDatabase invocation signature and what it validates
- `src/workflow/build.cpp` — full build workflow, parameter names, taxonomy path handling
- `README.md` lines 415-449 — build command documentation with accession2taxid format examples
- `README.md` lines 460-465 — 4-column accession2taxid format example with header

### Secondary (MEDIUM confidence)
- `azure-pipelines.yml` — confirmed existing `regression: 1` variable and the broken `util/Metabuli-regression/run_regression.sh` reference
- `src/commons/common.h` lines 177-190 — buffer size calculation confirming `maxRam < 16` branch applies at `--max-ram 1`

### Tertiary (LOW confidence)
- Inference: tiny corpus (~10 seqs, ~5 KB) will not trigger multiple flushes at 1 GB RAM — unverified by running the binary

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified by reading actual source code and README
- Architecture: HIGH — script pattern is standard bash; file formats verified from source parser
- Pitfalls: HIGH — accession2taxid format verified from sscanf pattern in source; cmp -s behavior is POSIX standard

**Research date:** 2026-03-04
**Valid until:** 2026-06-04 (stable — source code is not changing in Phase 1)
