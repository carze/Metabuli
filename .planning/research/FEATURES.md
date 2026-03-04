# Feature Research: Regression Testing for FASTA Random-Access Refactor

**Domain:** Bioinformatics pipeline correctness verification / regression testing
**Researched:** 2026-03-04
**Confidence:** HIGH

## Context

This document prescribes the regression testing strategy for refactoring Metabuli's FASTA reading
from sequential scan to `fseek`-based random access. The database build pipeline extracts 8-mer
metamers (64-bit AA+DNA hybrid values stored in `Kmer.value`) from reference FASTA files, sorts
them, computes LCA, and writes a differential index (`diffIdx` + `info` + `split`). The refactor
changes only the I/O access pattern inside `extractKmerFromSixFrames` and `fillTargetKmerBuffer`
in `IndexCreator.cpp` — not the k-mer computation, filtering, or write logic. The goal is to
prove that the refactored reader delivers identical byte content to the k-mer extraction layer.

---

## Feature Landscape

### Table Stakes (Required for Refactor Correctness)

| Feature | Why Required | Complexity | Notes |
|---------|--------------|------------|-------|
| Byte-identical `diffIdx` comparison | Any difference in delivered sequence bytes → different k-mers → different DB | LOW | `cmp` or `sha256sum` suffices |
| Byte-identical `info` comparison | TaxID assignments derive from sequence content order | LOW | Same tool as diffIdx |
| Byte-identical `split` comparison | Split offsets encode exact k-mer count positions | LOW | 4096 × 24-byte records; trivially diffable |
| Deterministic single-thread build | Multi-thread OMP scheduling is non-deterministic across buffer sizes; single-thread run eliminates this variable | MEDIUM | Use `--threads 1` for test builds |
| Small FASTA test corpus | Running on core_nt (900 GB) is not CI-feasible; a curated mini-corpus must reproduce all code paths | MEDIUM | See dataset design section below |
| `validateDatabase` pass | Existing tool checks that k-mer count in `diffIdx` matches entry count in `info` | LOW | Already ships in Metabuli |

### Differentiators (Strengthen Confidence Beyond Byte-Identity)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Classification equivalence test | Byte-identical DB → identical classification is guaranteed; but running classify on a small query set gives an independent sanity check | LOW | Use same reads that built the mini-DB |
| K-mer count per species comparison | Intermediate invariant: even if DB encoding differs, the count of k-mers assigned to each taxID must match | MEDIUM | Parse `info` file (array of uint32 TaxIDs) with a script |
| Prodigal CDS path coverage | If `par.cdsInfo != "x"`, a different branch of `fillTargetKmerBuffer` executes; the mini-corpus must exercise both the six-frame and CDS-annotated paths | MEDIUM | Include one species with CDS annotation |
| Syncmer vs. regular metamer path | `extractKmerFromSixFrames` vs. `fillTargetKmerBuffer` dispatch depends on `par.cdsInfo == "x"`; test both | MEDIUM | Two separate test invocations |

### Anti-Features (Avoid These)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Functional equivalence only (no binary diff) | "If classification results match, DB is correct" | Classification is lossy — two different DBs can produce identical TSV output for a given query set while containing different k-mers for untested organisms | Require byte-identical binary files as primary gate; use classification as secondary sanity check |
| Full core_nt regression in CI | Most thorough | 900 GB input, hours to run, impossible in CI; flaky due to download failures | Curated mini-corpus in repo or object storage |
| Comparing text export of `diffIdx` | Human-readable | Slow, text comparison is fragile; not needed when `cmp` works | Direct binary `cmp` |

---

## Equivalence Level Recommendation: BYTE-IDENTICAL BINARY FILES

**Recommendation: Byte-identical `diffIdx`, `info`, and `split` files are the required correctness
criterion. Functional (classification-level) equivalence alone is insufficient.**

**Rationale:**

1. The refactor touches only sequence delivery to `kmerExtractor->extractKmer_dna2aa()` and
   `kmerExtractor->extractTargetKmers()`. These functions are stateless given the same byte input.
   Therefore if the refactored reader delivers the same bytes in the same order, downstream output
   is deterministically identical.

2. The `diffIdx` file is a stream of variable-width 16-bit differential integers. It is byte-order
   sensitive and position-sensitive: a single out-of-order sequence in the batch changes both the
   sort order of k-mers and the LCA assignment in `filterKmers<FilterMode::DB_CREATION>`. These
   changes produce different `diffIdx` and `info` content that would still "work" for classification
   on the training set but would classify novel organisms differently.

3. The `split` file (4096 × `DiffIdxSplit` structs) is entirely derived from the contents of
   `diffIdx` and `info`. If both are byte-identical, `split` will be byte-identical automatically.

4. Bioinformatics tools that have done similar refactors (htslib's BGZ reader overhaul, DIAMOND's
   chunked FASTA reader) use byte-level checksums of output indexes, not functional tests, as the
   primary regression gate.

---

## Test Dataset Design

### Minimal Corpus Requirements

The mini-corpus must exercise the following code paths:

1. **Multi-sequence FASTA per species** — to trigger the `orders` vector loop in
   `extractKmerFromSixFrames` (scanning past earlier sequences to reach the target by `order` index).
2. **Multiple FASTA files** — `fastaPaths` must have at least 2 entries so `whichFasta` varies
   across `AccessionBatch` entries. This is the primary code path the random-access refactor targets.
3. **A species with sequences spanning file boundary** — one species with genomes in two
   separate FASTA files exercises the batch-grouping logic in `getAccessionBatches`.
4. **At least one sequence near buffer boundary** — size corpus so `--max-ram 1` forces at least 2
   flushes, exercising `writeTargetFiles` + `mergeTargetFiles`.
5. **Sequences with low-complexity regions** — to exercise the `maskLowComplexityRegions` branch.

### Concrete Construction Method

```bash
# 1. Pull 3-5 small complete bacterial genomes from NCBI (Mycoplasma, Buchnera)
#    Target: ~20 MB across 3 FASTA files, ~10 accessions total

# 2. Distribute sequences:
#    fasta_1.fna: 3 accessions from species A, 2 from species B
#    fasta_2.fna: 2 accessions from species B (same species, different file), 3 from species C
#    fasta_3.fna: 2 accessions from species D

# 3. Build with old (sequential) implementation, single thread:
metabuli build dbdir_old test.list acc2taxid.tsv \
    --taxonomy-path taxdir --threads 1 --max-ram 1

# 4. Build with new (fseek) implementation, same parameters:
metabuli_new build dbdir_new test.list acc2taxid.tsv \
    --taxonomy-path taxdir --threads 1 --max-ram 1

# 5. Compare outputs:
cmp dbdir_old/diffIdx dbdir_new/diffIdx && echo "PASS: diffIdx identical"
cmp dbdir_old/info    dbdir_new/info    && echo "PASS: info identical"
cmp dbdir_old/split   dbdir_new/split   && echo "PASS: split identical"
```

### Why `--threads 1` and `--max-ram 1`

`--threads 1` eliminates OpenMP non-determinism in batch processing order.
`--max-ram 1` forces multiple buffer flushes with the 20 MB corpus, exercising the
`writeTargetFiles` + `mergeTargetFiles` path. Without this, a small corpus fits in a single
buffer flush and never exercises the merge path.

---

## MVP Definition

### Launch With (v1 — before merging the refactor)

- [ ] Mini-corpus FASTA fixtures checked into repo under `test/data/` — enables offline CI
- [ ] Shell script `test/regression_fasta_access.sh` that builds both old and new DB and diffs them
- [ ] `validateDatabase` call on both DBs to confirm internal consistency
- [ ] CI job that runs the regression script on every PR to the refactor branch

### Add After Validation (v1.x)

- [ ] Classification equivalence check — run `metabuli classify` on a small synthetic FASTA against
  both DBs; compare TSV output as human-readable confirmation for reviewers
- [ ] K-mer count per species comparison — parse `info` file (raw `uint32_t` array) and compare
  per-taxID counts across old and new builds
- [ ] CDS-annotated path test — build with `--cds-info` pointing to a Prodigal output fixture to
  cover `fillTargetKmerBuffer` code path

---

## Binary Output Diffing

### Primary: `cmp`

```bash
cmp -l old/diffIdx new/diffIdx
# Prints: byte offset, old value, new value (octal) — useful for debugging divergence location
# Use cmp -s in CI (silent, check exit code only)
```

### Secondary: `sha256sum`

```bash
sha256sum old/diffIdx new/diffIdx old/info new/info old/split new/split
```

Store expected hashes as `.expected_sha256` files alongside test fixtures.

### Parsing `info` for K-mer Counts Per Species (Python)

The `info` file is a raw array of `uint32_t` TaxIDs, one per k-mer:

```python
import struct, collections, sys
with open(sys.argv[1], 'rb') as f:
    data = f.read()
taxids = struct.unpack(f'{len(data)//4}I', data)
counts = collections.Counter(taxids)
for taxid, count in sorted(counts.items()):
    print(f"{taxid}\t{count}")
```

### Using `validateDatabase`

```bash
metabuli validateDatabase dbdir_new
# Prints k-mer count from diffIdx and entry count from info — must match
```

---

*Feature research for: Metabuli FASTA random-access refactor regression testing*
*Researched: 2026-03-04*
