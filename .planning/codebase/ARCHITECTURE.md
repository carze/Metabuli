# Architecture

**Analysis Date:** 2026-03-04

## Pattern Overview

**Overall:** Metabuli uses a command-driven pipeline architecture built on the MMseqs2 framework, with specialized modules for metagenomic sequence classification. The system follows a layered design with clear separation between database creation, k-mer matching, and taxonomic assignment.

**Key Characteristics:**
- Multi-phase workflow: database building → k-mer extraction → reference matching → taxonomy assignment → reporting
- Hybrid DNA/amino acid (AA) k-mer analysis using "metamers" (joint DNA-AA k-mers)
- Memory-efficient design with streaming-based k-mer processing and configurable RAM usage
- Command-based dispatch system inherited from MMseqs2 for modular functionality

## Layers

**Command/Workflow Layer:**
- Purpose: Entry points for user workflows (classify, build, updateDB, extract, etc.)
- Location: `src/workflow/` and `src/metabuli.cpp`
- Contains: Workflow functions (classify.cpp, build.cpp, updateDB.cpp, extract.cpp)
- Depends on: LocalParameters, Classifier, IndexCreator, Reporter
- Used by: Main CLI entry point (metabuli.cpp)

**Core Classification Layer:**
- Purpose: Orchestrates the classification pipeline for query sequences
- Location: `src/commons/Classifier.h` and `src/commons/Classifier.cpp`
- Contains: Classifier class that manages k-mer extraction, matching, and taxonomy assignment
- Depends on: QueryIndexer, KmerExtractor, KmerMatcher, Taxonomer, Reporter
- Used by: classify workflow

**K-mer Processing Layer:**
- Purpose: Extracts, indexes, and matches k-mers from sequences
- Location: `src/commons/` (KmerExtractor, KmerMatcher, QueryIndexer, SyncmerScanner, KmerScanner)
- Contains:
  - KmerExtractor: Converts DNA/AA sequences to k-mers/metamers
  - QueryIndexer: Indexes query sequences for memory-bounded processing
  - KmerMatcher: Performs approximate matching against reference k-mers
  - SyncmerScanner/KmerScanner: Extracts syncmers or regular k-mers with configurable spaced patterns
- Depends on: GeneticCode, Kmer data structures, differential index readers
- Used by: Classifier, IndexCreator

**Taxonomy/Ranking Layer:**
- Purpose: Assigns taxonomic classification based on matched k-mers
- Location: `src/commons/Taxonomer.h`, `src/commons/Reporter.h`, `src/commons/TaxonomyWrapper.h`
- Contains:
  - Taxonomer: Implements LCA, EM-based, and species-level classification logic
  - Reporter: Formats and writes classification results (TSV, Krona HTML)
  - TaxonomyWrapper: NCBI taxonomy dump management and rank traversal
- Depends on: Match structures, TaxID mappings, NCBI taxonomy files
- Used by: Classifier

**Database Creation Layer:**
- Purpose: Builds indexed k-mer databases from reference sequences
- Location: `src/commons/IndexCreator.h` and `src/commons/IndexCreator.cpp`
- Contains: IndexCreator class orchestrating k-mer extraction, filtering, and differential index creation
- Depends on: KmerExtractor, SeqIterator, taxonomic mapping, accession2taxid files
- Used by: build and updateDB workflows

**Index Management Layer:**
- Purpose: Efficient storage and retrieval of reference k-mers using differential encoding
- Location: `src/commons/` (DeltaIdxReader.h, Mmap.h)
- Contains:
  - DeltaIdxReader: Decodes differential indices for space efficiency
  - Mmap utilities: Memory-mapped file access for large indices
- Depends on: File I/O utilities
- Used by: KmerMatcher, IndexCreator

**Utility/Helper Layer:**
- Purpose: Supporting functionality for validation, filtering, and data transformation
- Location: `src/util/` and auxiliary commands
- Contains: Database validation, taxonomy creation, read extraction, result filtering (classifiedRefiner)
- Depends on: Core taxonomy and file utilities
- Used by: Various workflows and manual utilities

**Read-Group/Accession Layer:**
- Purpose: Manages grouping of sequences by read pairs or accession numbers
- Location: `src/read-group/`
- Contains: GroupGenerator for organizing paired-end or multi-strain reads
- Depends on: Sequence information structures
- Used by: Database creation and classification workflows

## Data Flow

**Classification Pipeline:**

1. **Input**: User provides query FASTA/Q file(s) and reference database directory
2. **Query Indexing** (`QueryIndexer::indexQueryFile`):
   - Reads sequences in memory-bounded chunks
   - Creates query splits managing RAM constraints
3. **K-mer Extraction** (`KmerExtractor`):
   - Converts DNA to AA via genetic code translation
   - Extracts k-mers/metamers (24bp DNA or 8 AA + DNA combination)
   - Generates spaced k-mers or syncmers based on mode
4. **K-mer Matching** (`KmerMatcher::matchKmers`):
   - Loads differential index from database
   - Performs approximate matching using Hamming distance thresholds
   - Returns Match objects with reference taxID, position, hamming distance
5. **Taxonomy Assignment** (`Taxonomer::assignTaxonomy`):
   - Builds match paths (chains of overlapping matches)
   - Selects best species using LCA or EM algorithm
   - Assigns ranks (species, genus, family, etc.) based on taxonomy
6. **Reporting** (`Reporter::reportResult`):
   - Writes classifications (read ID, taxID, score, rank)
   - Generates taxonomy report (Krona HTML)
   - Outputs TSV-formatted results
7. **Output**: JobID_classifications.tsv, JobID_report.tsv, JobID_krona.html

**Database Building Pipeline:**

1. **Input**: FASTA list, accession2taxid mapping, taxonomy directory
2. **Sequence Reading** (`SeqIterator`):
   - Loads sequences grouped by accession/species
   - Associates taxonomy IDs from accession2taxid
3. **Training Sequence Selection** (`IndexCreator`):
   - Identifies representative sequences per species
   - Uses statistical analysis to select training sequences
4. **K-mer Extraction & Filtering**:
   - Extracts all k-mers from training sequences
   - Filters common k-mers (appear in multiple species)
   - Identifies unique/discriminative k-mers
5. **Differential Index Creation**:
   - Sorts k-mers lexicographically
   - Encodes k-mer positions as 16-bit differential values
   - Stores in compact delta index format
6. **Index Splitting & Serialization**:
   - Creates diffIdx, info, split files
   - Encodes species/taxID information
7. **Output**: Database directory with diffIdx, split, info, taxonomy files

**State Management:**

- **Match Buffer**: Stores Match objects (queryID, refTaxID, hamming, score) during k-mer matching
- **Query Buffer**: Holds Kmer objects (24bp uint64_t or Metamer) extracted from query
- **Taxonomy Tree**: In-memory hierarchy of taxIDs with parent/child relationships
- **Tax Counts**: Cumulative counts of matches per taxID for LCA/EM algorithms

## Key Abstractions

**Kmer (24bp DNA):**
- Purpose: Represents a 24-base DNA k-mer as uint64_t
- Examples: `src/commons/Kmer.h`
- Pattern: Bit-packing with 2 bits per base (A=0, C=1, G=2, T=3)

**Metamer (DNA + AA hybrid):**
- Purpose: Joint DNA-AA representation for sensitive homology detection
- Examples: `src/commons/Kmer.h` (Metamer class)
- Pattern: Bitset<96> combining 24bp DNA + 8 AA codons in single structure

**Match:**
- Purpose: Encodes a k-mer match between query and reference
- Examples: `src/commons/Match.h`
- Pattern: Contains queryID, refTaxID, position, hamming distance, score calculation

**Query:**
- Purpose: Metadata for a single query sequence
- Examples: `src/commons/common.h`
- Pattern: Tracks classification state (isClassified, bestTaxID, score, rank)

**Accession:**
- Purpose: Database sequence metadata (name, species, taxID)
- Examples: `src/commons/IndexCreator.h`
- Pattern: Sorted by speciesID for efficient grouping during DB creation

**Assembly:**
- Purpose: Represents a reference genome with taxonomic hierarchy
- Examples: `src/commons/common.h`
- Pattern: Stores taxIDs at multiple ranks (species, genus, family, order)

**DiffIdxReader:**
- Purpose: Decodes variable-length differential indices
- Examples: `src/commons/DeltaIdxReader.h`
- Pattern: Reads 16-bit chunks, reconstructs full k-mers using cumulative delta encoding

## Entry Points

**Main CLI (metabuli):**
- Location: `src/metabuli.cpp`
- Triggers: `metabuli <command> [options]`
- Responsibilities: Command registration, parameter initialization, command dispatch

**classify Workflow:**
- Location: `src/workflow/classify.cpp`
- Triggers: `metabuli classify <query1> [query2] <dbdir> <outdir> <jobid>`
- Responsibilities: Parameter parsing, input validation, Classifier instantiation, output routing

**build Workflow:**
- Location: `src/workflow/build.cpp`
- Triggers: `metabuli build <dbdir> <fasta_list> <accession2taxid> --taxonomy-path <taxdir>`
- Responsibilities: FASTA parsing, taxonomy mapping, IndexCreator delegation, output serialization

**extract Workflow:**
- Location: `src/workflow/extract.cpp`
- Triggers: `metabuli extract <query> <classifications.tsv> <dbdir> --tax-id <taxid>`
- Responsibilities: Read filtering based on taxonomy, output formatting

## Error Handling

**Strategy:** Parameter validation at entry, exception-free design with exit codes

**Patterns:**
- Input validation (classify.cpp lines 45-189): Checks file existence, directory structure, format compatibility
- Database validation (validateDatabase.cpp): Confirms required index files present
- Parameter sanity checks (LocalParameters.cpp): Validates ranges (e.g., RAM usage, score thresholds)
- Error reporting: Writes to stdout, exits with code 1 on failure

## Cross-Cutting Concerns

**Logging:** Console output via `std::cout` with verbosity control via `par.verbosity`

**Validation:**
- FASTA validation via `fasta_validate.h` (external library integration)
- FASTQ validation via `fastq_utils` (external library integration)
- Database structural validation checks diffIdx/info/split file presence

**Authentication:** Not applicable (offline tool, no external services)

**Memory Management:**
- Manual allocation/deallocation with Buffer<> template for dynamic arrays
- Memory-bounded processing via QueryIndexer splits (respects `--max-ram` parameter)
- Memory-mapped file access for large indices via Mmap utilities

---

*Architecture analysis: 2026-03-04*
