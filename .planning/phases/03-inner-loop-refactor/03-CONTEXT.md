# Phase 3: Inner Loop Refactor - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Refactor `extractKmerFromSixFrames()` and `fillTargetKmerBuffer()` in `IndexCreator.cpp` to use `fseeko` random access (instead of sequential scan from byte 0) when `fastaOffsets[whichFasta]` is non-empty. Add per-thread `seqBuf` vector reuse. Preserve gzip fallback. Add README documentation for the gzip limitation. Regression harness must pass.

</domain>

<decisions>
## Implementation Decisions

### Training sequence scope in fillTargetKmerBuffer
- Training sequence reads (`trainingSeqFasta` / `trainingSeqIdx`) stay on the existing `KSeqWrapper` sequential path — do NOT apply fseeko there
- Training sequence is read once per species (not the hot path); Phase 3 scope is strictly FILLTGT-01 to 04
- Preserve `trained` flag logic exactly as-is — no behavioral changes to the training sequence code path
- When `trainingSeqFasta != whichFasta`: always use `KSeqWrapper` for training reads regardless of offset availability

### seqBuf design after fseeko
- After `fseeko` to `fastaOffsets[fileIdx][ordinal]` (the `>` character), skip header with `fgets`, then bound the read using the next offset: `fastaOffsets[fileIdx][ordinal+1]` gives the byte position of the next sequence header
- Read bytes from current file position up to the next offset (or EOF for last sequence), strip embedded newlines, store in `seqBuf`
- `seqBuf` is a per-thread `vector<char>` declared in the OpenMP parallel block; starts empty, grows via `resize()` as sequences are processed — no pre-allocation
- `maskMode`: masking is done in-place into `seqBuf` (eliminates the separate `maskedSeq = new char[...]` / `delete[]` entirely)
- Gzip fallback path: when `fastaOffsets[whichFasta]` is empty, keep the existing `KSeqWrapper` sequential scan entirely unchanged

### Documentation scope for DOCS-01
- Add a concise limitation note to the main `README.md`, near the database building section
- Tone: limitation + workaround (not a requirements statement)
- Example framing: "gzip FASTA files are not supported for random access. Decompress with gunzip before building large databases. Compressed files fall back to a slower sequential scan."
- No performance numbers — keep it concise
- No code comments needed; README only

### Claude's Discretion
- Exact `fread` vs `fgets`-loop approach for multi-line FASTA sequence accumulation after bounding by next offset (use next-offset bounding as decided, implementation detail of stripping newlines is flexible)
- How to handle the last sequence in a file when there is no `ordinal+1` offset (read until EOF)
- Exact `seqBuf` resize pattern (resize to `nextOffset - currentOffset` as upper bound, then shrink after stripping newlines)
- Whether to extract the fseeko read loop into a helper function or inline it in both function bodies

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `fastaOffsets[fileIdx][ordinal]`: already built by Phase 2 — `fastaOffsets[whichFasta][seqOrdinal]` gives the `>` byte offset; empty vector = gzip file = fallback sentinel
- `accessionBatches[batchIdx].orders[]`: the sequence ordinals needed for a batch (these get sorted by offset before seeking per EXTKMER-02/FILLTGT-02)
- `KSeqFactory` / `KSeqWrapper`: kept for gzip fallback path and training sequence reads — no changes to the KSeq code path

### Established Patterns
- Both functions have identical structure: OpenMP `#pragma omp for schedule(dynamic, 1)`, `hasOverflow` check, `batchChecker.exchange`, buffer reserve, then per-sequence processing loop
- `maskLowComplexityRegions((unsigned char *) src, (unsigned char *) dst, ...)` signature: src and dst CAN be the same pointer (in-place masking) — confirmed safe for the in-place seqBuf design
- `extractKmer_dna2aa(maskedSeq, e.sequence.l, ...)` and `extractTargetKmers(...)` consume a `const char*` pointer and length — seqBuf.data() + seqBuf.size() works as drop-in replacement

### Integration Points
- `extractKmerFromSixFrames()`: simpler function — no Prodigal, no CDS/nonCDS split. The fseeko path replaces the entire `while (kseq->ReadEntry())` scan loop when offsets are available
- `fillTargetKmerBuffer()`: more complex — has Prodigal training, CDS/nonCDS split. Only the main `while (kseq->ReadEntry())` sequence scan loop (the one over `accessionBatches[batchIdx].orders`) gets replaced; Prodigal training sequence block stays as-is
- `fastaPaths[whichFasta]`: the file path string, used to open a fresh `FILE*` per batch for fseeko (per-batch open/close, not cached — PERF-02 is deferred v2)

</code_context>

<specifics>
## Specific Ideas

- The sort-before-seek step (EXTKMER-02, FILLTGT-02): sort `accessionBatches[batchIdx].orders` by their corresponding `fastaOffsets[whichFasta][ordinal]` values before processing the batch — ensures forward-only file access within each batch, enabling OS read-ahead
- For the last sequence in a file (no `ordinal+1` entry in `fastaOffsets[whichFasta]`): read until EOF using `fread` with a reasonable block size, or `fseek(fp, 0, SEEK_END)` + `ftello` to get file size

</specifics>

<deferred>
## Deferred Ideas

- Per-thread cached `FILE*` handles keyed by `fileIdx` (PERF-02) — reduces fopen/fclose overhead when a thread processes multiple batches from the same file. Explicitly v2.
- fseeko for training sequence reads in `fillTargetKmerBuffer` — low impact (once per species), left for later if needed
- `fread` 64 KB block scanner for the offset pre-pass (PERF-01) — deferred to v2

</deferred>

---

*Phase: 03-inner-loop-refactor*
*Context gathered: 2026-03-05*
