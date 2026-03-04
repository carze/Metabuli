# Codebase Structure

**Analysis Date:** 2026-03-04

## Directory Layout

```
metabuli/
├── src/                       # All C++ source code
│   ├── commons/               # Core classification logic
│   ├── workflow/              # Workflow entry points (classify, build, extract, etc.)
│   ├── util/                  # Utility commands and tools
│   ├── benchmark/             # Benchmark dataset generation
│   ├── uniref/                # UniRef k-mer database creation
│   ├── read-group/            # Paired-end read grouping
│   ├── version/               # Version information
│   ├── metabuli.cpp           # Main CLI entry point
│   ├── MetabuliBase.cpp       # Command declarations and registration
│   ├── LocalCommandDeclarations.h  # Command function declarations
│   └── CMakeLists.txt         # Build configuration
├── lib/                       # External dependencies (git submodules)
│   ├── mmseqs/                # MMseqs2 framework
│   ├── prodigal/              # Gene prediction
│   ├── fasta_validator/       # FASTA validation
│   ├── fastq_utils/           # FASTQ validation
│   └── yxml/                  # XML parsing for UniRef
├── data/                      # Data files and shell scripts
├── util/                      # User utilities (Python scripts, regression tests)
│   ├── gtdb_to_taxdump/       # GTDB taxonomy conversion
│   └── Metabuli-regression/   # Test suite
├── .planning/                 # GSD planning documents
│   └── codebase/              # Architecture and structure docs
├── CMakeLists.txt             # Root CMake configuration
├── Dockerfile                 # Container image definition
├── README.md                  # Documentation
└── .gitmodules               # Git submodule configuration
```

## Directory Purposes

**src/commons/:**
- Purpose: Core C++ classes for k-mer matching, taxonomy assignment, database creation
- Contains: Classifier, KmerMatcher, KmerExtractor, Taxonomer, Reporter, Index creation
- Key files:
  - `Classifier.h/cpp`: Orchestrates classification pipeline
  - `KmerMatcher.h/cpp`: Approximate k-mer matching engine (18.7K lines)
  - `IndexCreator.h/cpp`: Database index construction (65.6K lines)
  - `Taxonomer.h/cpp`: Taxonomic rank assignment (29.6K lines)
  - `TaxonomyWrapper.h/cpp`: NCBI taxonomy tree management

**src/workflow/:**
- Purpose: User-facing command implementations
- Contains: Main workflows as callable functions
- Key files:
  - `classify.cpp`: Classification of query sequences
  - `build.cpp`: Database creation from FASTA
  - `updateDB.cpp`: Adding sequences to existing database
  - `extract.cpp`: Extracting reads classified to specific taxon
  - `groupGeneration.cpp`: Organizing paired-end reads

**src/util/:**
- Purpose: Auxiliary utilities and diagnostic tools
- Contains: Database inspection, taxonomy editing, result filtering
- Key files:
  - `classifiedRefiner.cpp`: Post-process classification results (filter by score, rank, taxid)
  - `validateDatabase.cpp`: Check database structural integrity
  - `taxdump.cpp`: Retrieve and display taxonomy information
  - `grade.cpp`: Evaluate classification accuracy (used in testing)
  - `createnewtaxalist.cpp`: Generate new taxonomy entries for database updates

**src/benchmark/:**
- Purpose: Generate test datasets for performance evaluation
- Contains: Synthetic read and genome dataset creation
- Key files:
  - `makeBenchmarkSet.cpp`: Generate benchmark sequences (49.7K)
  - `makeVirusBenchmarkSet.cpp`: Virus-specific benchmark (18.7K)
  - `makeInclusionQuerySet.cpp`: Query sequence generation (11.8K)

**src/uniref/:**
- Purpose: UniRef k-mer database creation and management
- Contains: UniRef clustering and tree construction
- Key files:
  - `UnirefTree.h/cpp`: Hierarchical UniRef cluster storage
  - `UnirefClassifier.cpp`: Classification using UniRef data

**src/read-group/:**
- Purpose: Manage paired-end and multi-strain read organization
- Contains: Read grouping logic for database construction
- Key files:
  - `GroupGenerator.h/cpp`: Group sequences by metadata (48.9K)

**lib/mmseqs/:**
- Purpose: MMseqs2 framework providing base functionality
- Contains: Command system, sequence utilities, parallelization (inherited/extended)
- Integration: Metabuli derives Command classes and parameter parsing from MMseqs2

**data/:**
- Purpose: Static data and build-time resources
- Contains: Shell scripts for database download/management

**util/ (top-level):**
- Purpose: User scripts and testing utilities
- Contains: Python scripts for GTDB conversion, regression test suite

## Key File Locations

**Entry Points:**
- `src/metabuli.cpp`: CLI main entry point and command initialization
- `src/MetabuliBase.cpp`: Command vector registration (metabuliCommands array)
- `src/LocalCommandDeclarations.h`: Forward declarations for all command functions

**Configuration:**
- `CMakeLists.txt`: CMake build orchestration
- `src/CMakeLists.txt`: Source compilation configuration with subdirectories
- `src/commons/CMakeLists.txt`: Build commons library
- `LocalParameters.h/cpp`: Parameter definitions and parsing (51.2K parameters file)

**Core Logic:**
- `src/commons/Classifier.h/cpp`: Main classification orchestration (18.7K, 23K lines)
- `src/commons/KmerMatcher.h/cpp`: K-mer matching implementation (15.7K header, 53.1K implementation)
- `src/commons/Taxonomer.h/cpp`: Taxonomy assignment algorithms (6.2K, 29.6K lines)
- `src/commons/IndexCreator.h/cpp`: Database index building (24.3K, 65.6K lines)

**K-mer Processing:**
- `src/commons/KmerExtractor.h/cpp`: K-mer/metamer extraction (4K, 34.5K lines)
- `src/commons/KmerScanner.h`: Regular k-mer scanning with patterns
- `src/commons/SyncmerScanner.h`: Syncmer (minimizer) extraction (11.1K)
- `src/commons/QueryIndexer.h/cpp`: Query sequence chunking (1.6K, 5.7K lines)

**Data Structures:**
- `src/commons/Kmer.h`: K-mer bit-packing (5.4K)
- `src/commons/Match.h`: K-mer match record (3.9K)
- `src/commons/common.h`: Core structs (MappingRes, Assembly, Query) (12.6K)
- `src/commons/DeltaIdxReader.h`: Differential index decoding (8.0K)

**Taxonomy & Reporting:**
- `src/commons/TaxonomyWrapper.h/cpp`: Taxonomy tree operations (10.6K, 30.5K lines)
- `src/commons/Reporter.h/cpp`: Output formatting (TSV, Krona HTML) (3.8K, 15.9K lines)
- `src/commons/GeneticCode.h`: DNA-to-AA translation tables (11.5K)

**Utilities:**
- `src/commons/SeqIterator.h/cpp`: Sequence file reading with buffering (14.2K, 31.7K lines)
- `src/commons/common.cpp`: Helper functions (10.4K)
- `src/util/accession2taxid.cpp`: Accession-to-taxid mapping (5.1K)

## Naming Conventions

**Files:**
- Headers: `ClassName.h` (e.g., `Classifier.h`, `KmerMatcher.h`)
- Implementation: `ClassName.cpp` (e.g., `Classifier.cpp`)
- Command workflows: `verb.cpp` (e.g., `classify.cpp`, `build.cpp`, `extract.cpp`)
- Utilities: `action-object.cpp` (e.g., `filter_by_genus.cpp`, `expand_diffidx.cpp`)

**Directories:**
- Functional modules: lowercase singular (commons, workflow, util, uniref)
- Multi-word modules: kebab-case (read-group)

**Classes:**
- PascalCase for all classes (Classifier, KmerMatcher, Taxonomer)
- No prefix/suffix conventions

**Functions:**
- camelCase for public methods (startClassify, assignTaxonomy, matchKmers)
- camelCase for private methods (loadTaxonomy, filterCandidates)
- PascalCase for workflow entry functions (classify, build, extract) - static functions in C

**Variables:**
- camelCase for local/member variables (kmerFormat, dbDir, queryList)
- UPPERCASE for macros and constants (DNA_MASK, BufferSize)
- Single letter for loop indices (i, j)

**Types:**
- PascalCase for struct/class names (Match, Query, Kmer)
- PascalCase for typedef'd enums (FilterMode)

## Where to Add New Code

**New Classification Algorithm:**
- Primary code: `src/commons/Taxonomer.cpp` (add methods to Taxonomer class)
- Tests: Create corresponding test in `util/Metabuli-regression/`
- Entry point: Reference via Classifier::assignTaxonomy flow

**New Database Building Feature:**
- Primary code: `src/commons/IndexCreator.cpp` (extend indexing logic)
- Workflow: `src/workflow/build.cpp` or `updateDB.cpp` (add parameter parsing)
- Parameters: Add to `LocalParameters.cpp` with defaults in workflow function

**New Output Format:**
- Primary code: `src/commons/Reporter.cpp` (add format method)
- Entry: `src/workflow/classify.cpp` (call reporter after taxonomy assignment)
- Example: TSV reporter at line 15-40, Krona reporter at lines 50-100

**New Utility Command:**
- Primary code: `src/util/command_name.cpp` (implement command function)
- Declaration: Add to `src/LocalCommandDeclarations.h`
- Registration: Add to metabuliCommands vector in `src/MetabuliBase.cpp`

**New Validation Feature:**
- Primary code: `src/util/validateDatabase.cpp` or new file
- Integration: Call from workflow entry points (see classify.cpp lines 95-100, 133-138)

**Utilities/Helper Functions:**
- Shared helpers: `src/commons/common.cpp` (non-class utilities)
- Local utilities: Create `LocalUtil.cpp` pattern (see `src/commons/LocalUtil.cpp`)
- File operations: Extend `src/commons/LocalUtil.h`

## Special Directories

**lib/mmseqs:**
- Purpose: MMseqs2 framework dependency (git submodule)
- Generated: No - checked in as submodule
- Committed: Yes (submodule reference, not contents)
- Usage: Provides Command base class, parameter parsing, sequence utilities

**lib/ (other subdirs):**
- Purpose: External validation and utility libraries
- Generated: No - all checked in
- Committed: Yes - submodules for prodigal, fasta_validator, fastq_utils, yxml

**.planning/codebase/:**
- Purpose: GSD architecture and structure documentation
- Generated: Yes - created by gsd:map-codebase
- Committed: Yes - to git

**data/:**
- Purpose: Build-time resources and installation data
- Generated: Partially (shell scripts may generate downloads)
- Committed: Yes - source scripts committed

**util/Metabuli-regression/:**
- Purpose: Regression test suite
- Generated: Test outputs during execution
- Committed: Reference/expected outputs, test scripts committed

## Build System Integration

**CMake Flow:**
1. Root `CMakeLists.txt`: Sets C++17 standard, includes subdirectories
2. `src/CMakeLists.txt`: Defines source file variables, builds metabuli executable
3. Per-module `CMakeLists.txt`: Each src subdirectory defines source files (e.g., `commons_source_files`)
4. Final executable: Aggregates all source files from all modules

**Executable Location After Build:**
- `build/src/metabuli`: The compiled binary (installed to `bin/` with `make install`)

**Linking Dependencies:**
- `mmseqs`: Base framework
- `prodigal`: Gene prediction library
- `fasta_validator`: FASTA validation
- `fastq_utils`: FASTQ validation
- `yxml`: XML parsing
- `version`: Version information library

---

*Structure analysis: 2026-03-04*
