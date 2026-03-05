---
phase: 03-inner-loop-refactor
verified: 2026-03-05T19:30:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 3: Inner Loop Refactor Verification Report

**Phase Goal:** Refactor both inner-loop hot paths (extractKmerFromSixFrames and fillTargetKmerBuffer) to use fseeko random access when FASTA offsets are available, eliminating sequential re-scan overhead for large uncompressed FASTA databases. Add a readFastaSequence() helper. Document gzip limitation in README.
**Verified:** 2026-03-05T19:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | extractKmerFromSixFrames seeks directly to each required sequence via fseeko when fastaOffsets[whichFasta] is non-empty | VERIFIED | Lines 1091-1143: `if (!offsets.empty())` branch calls `readFastaSequence(fp, curOff, nextOff, seqBuf)` with fopen/fclose per batch |
| 2 | Batch orders are processed in ascending byte-offset order within each batch (forward-only file access) | VERIFIED | Lines 1104-1108: `std::iota` + `std::sort` on `sortedIdx` sorting by `offsets[orders[a]]` — present in both functions |
| 3 | When fastaOffsets[whichFasta] is empty, extractKmerFromSixFrames falls back to the existing KSeqWrapper scan path | VERIFIED | Lines 1145-1197: `else` branch preserves original KSeqWrapper loop verbatim |
| 4 | A per-thread seqBuf vector<char> replaces all per-sequence new/delete allocations in the fseeko path | VERIFIED | Line 1058: `std::vector<char> seqBuf;` declared inside `#pragma omp parallel` block; no `new char[` in fseeko branch (only at lines 1164, 1482, 1596 — all in gzip fallback) |
| 5 | fillTargetKmerBuffer seeks directly to each required sequence via fseeko when fastaOffsets[whichFasta] is non-empty | VERIFIED | Lines 1269-1462: `if (!offsets.empty())` branch with readFastaSequence, header re-seek for cdsInfoMap, Prodigal forward/RC sub-branches, all using seqBuf/rcBuf |
| 6 | Training sequence block stays on KSeqWrapper path, unchanged | VERIFIED | Line 1364: `KSeqWrapper* training_seq = KSeqFactory(fastaPaths[accessionBatches[batchIdx].trainingSeqFasta].c_str())` inside the fseeko branch Prodigal sub-block; also at line 1529 in gzip fallback |
| 7 | Per-thread seqBuf and rcBuf vectors replace all per-sequence new/delete in fillTargetKmerBuffer fseeko path | VERIFIED | Lines 1230-1231: `std::vector<char> seqBuf; std::vector<char> rcBuf;` inside parallel block; `delete[] maskedSeq` only at lines 1595, 1620 (gzip fallback) |
| 8 | readFastaSequence() static helper exists with fseeko + header-skip + bounded fread + newline-strip logic | VERIFIED | Lines 1007-1046: complete implementation with `fseeko`, `fgets` loop for long headers, `ftello`, `fread`, in-place newline strip; placed before `extractKmerFromSixFrames` definition at line 1048 |
| 9 | README.md contains a gzip FASTA limitation note near the database building section | VERIFIED | Line 421: `[!NOTE]` callout immediately after `[!IMPORTANT]` block at line 414 in "Creat a new database" section; states limitation, sequential fallback, gunzip workaround; no performance numbers |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/commons/IndexCreator.cpp` | readFastaSequence static helper + refactored extractKmerFromSixFrames body | VERIFIED | Helper at lines 1007-1046; extractKmerFromSixFrames fseeko branch lines 1091-1143; gzip fallback lines 1145-1197 |
| `src/commons/IndexCreator.cpp` | refactored fillTargetKmerBuffer body using readFastaSequence helper | VERIFIED | fseeko branch lines 1269-1462; calls readFastaSequence at line 1303; gzip fallback lines 1464-1640+ |
| `README.md` | gzip FASTA limitation note for database builders | VERIFIED | Line 420-421: [!NOTE] callout with gzip limitation + gunzip workaround |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| extractKmerFromSixFrames (fseeko branch) | readFastaSequence helper | direct call with fp, curOff, nextOff, seqBuf | WIRED | Line 1126: `readFastaSequence(fp, curOff, nextOff, seqBuf)` |
| extractKmerFromSixFrames | fastaOffsets[whichFasta] | offsets.empty() sentinel check | WIRED | Line 1091: `if (!offsets.empty())` — aliases to `fastaOffsets[whichFasta]` via `const auto& offsets = fastaOffsets[whichFasta]` at line 1089 |
| fillTargetKmerBuffer (fseeko branch) | readFastaSequence helper | direct call with fp, curOff, nextOff, seqBuf | WIRED | Line 1303: `readFastaSequence(fp, curOff, nextOff, seqBuf)` |
| fillTargetKmerBuffer | fastaOffsets[whichFasta] | offsets.empty() sentinel check | WIRED | Line 1269: `if (!offsets.empty())` — aliases to `fastaOffsets[whichFasta]` via line 1267 |
| fillTargetKmerBuffer Prodigal forward path | seqBuf.data() | getPredictedGenes + maskLowComplexityRegions in-place + extractTargetKmers | WIRED | Lines 1405-1424: Prodigal on seqBuf.data(), masking in-place after getExtendedORFs, extractTargetKmers on seqBuf.data() |
| fillTargetKmerBuffer Prodigal reverse-complement path | rcBuf.data() | maskLowComplexityRegions with rc as src and rcBuf as dst | WIRED | Lines 1435-1445: rcBuf.resize(seqBytes+1), maskLowComplexityRegions src=rc dst=rcBuf.data(), maskedRC = rcBuf.data() |
| README.md gzip note | NCBI or custom taxonomy database section | positioned near Create a new database section | WIRED | Lines 420-421 immediately follow the [!IMPORTANT] block at lines 414-418 in the "Creat a new database" section |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EXTKMER-01 | 03-01 | fseeko() to seek directly to each sequence when fastaOffsets non-empty | SATISFIED | Lines 1091-1143: fseeko branch in extractKmerFromSixFrames |
| EXTKMER-02 | 03-01 | Batch orders sorted by byte offset before seeking | SATISFIED | Lines 1104-1108: sortedIdx iota+sort pattern |
| EXTKMER-03 | 03-01 | Gzip fallback to KSeqWrapper when offsets empty | SATISFIED | Lines 1145-1197: original KSeq scan preserved in else branch |
| EXTKMER-04 | 03-01 | Per-thread seqBuf vector replacing per-sequence new/delete | SATISFIED | Line 1058: seqBuf declared in parallel block; no new char[] in fseeko branch |
| FILLTGT-01 | 03-02 | fseeko() in fillTargetKmerBuffer when fastaOffsets non-empty | SATISFIED | Lines 1269-1462: fseeko branch with readFastaSequence |
| FILLTGT-02 | 03-02 | Batch orders sorted by byte offset | SATISFIED | Lines 1281-1284: sortedIdx iota+sort pattern |
| FILLTGT-03 | 03-02 | Gzip fallback to KSeqWrapper in fillTargetKmerBuffer | SATISFIED | Lines 1464-1640+: original KSeq scan in else branch |
| FILLTGT-04 | 03-02 | Per-thread seqBuf vector in fillTargetKmerBuffer | SATISFIED | Lines 1230-1231: seqBuf and rcBuf declared in parallel block |
| DOCS-01 | 03-03 | Note in build documentation about gzip FASTA limitation | SATISFIED | README.md line 421: [!NOTE] callout with limitation + workaround |

No orphaned requirements. All 9 Phase 3 requirements are claimed by plans and verified as implemented.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/commons/IndexCreator.cpp` | 1482 | `// TODO: reuse the buffer` comment | Info | Inside gzip KSeq fallback branch of fillTargetKmerBuffer — this is legacy code that was preserved verbatim as required by plan. The TODO is a future optimization note on the unchanged fallback path, not the refactored fseeko path. Does not affect goal achievement. |

### Human Verification Required

#### 1. Regression Test Confirmation

**Test:** Run `./test/regression_fasta_access.sh ./build/src/metabuli` against a current build
**Expected:** Script exits 0 with byte-identical k-mer output between sequential and fseeko builds; summary reports state 166,551 k-mers (extractKmerFromSixFrames) and 99,924 k-mers (fillTargetKmerBuffer)
**Why human:** Requires building the project and executing the regression script. Summaries claim passes but cannot verify programmatically from a static code review.

#### 2. Forward Prodigal Masking Order (Behavioral Correctness)

**Test:** Build a database with a genome that has known CDS annotations and maskMode enabled. Compare k-mer set between fseeko and KSeq builds.
**Expected:** extractTargetKmers receives the masked sequence while Prodigal received the raw (unmasked) sequence for gene prediction — matching original behavior.
**Why human:** The ordering of Prodigal calls vs. maskLowComplexityRegions matters for correctness. Code at lines 1405-1414 shows Prodigal before masking (correct), but confirming behavioral equivalence requires a test run.

### Gaps Summary

No gaps. All automated checks passed across all three verification levels (exists, substantive, wired) for all artifacts and key links. All 9 requirement IDs are satisfied. The single TODO comment is in preserved legacy code (gzip fallback) and does not block goal achievement.

---

_Verified: 2026-03-05T19:30:00Z_
_Verifier: Claude (gsd-verifier)_
