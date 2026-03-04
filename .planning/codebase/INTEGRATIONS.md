# External Integrations

**Analysis Date:** 2026-03-04

## APIs & External Services

**Database Downloads:**
- mmseqs.com - Host for pre-built Metabuli databases
  - URL: `https://mmseqs.com/metabuli`
  - Accessed via: `metabuli databases` command
- hulk.mmseqs.com - GTDB database distribution
  - GTDB R226 databases hosted here

**Reference Data:**
- GTDB (Genome Taxonomy Database) - Prokaryote genome taxonomy
  - Integration: Custom database build support via `--gtdb 1` flag
  - Requires: GTDB taxdump files + taxonkit format compatibility
- NCBI RefSeq - Prokaryote and viral genomes
  - Integration: Accession-based mapping via NCBI-style files
- NCBI Taxonomy - Taxonomy structure (nodes.dmp, names.dmp, merged.dmp)
  - Source: `ftp.ncbi.nlm.nih.gov/pub/taxonomy/`
- NCBI Accession2Taxid - Sequence-to-taxon mapping
  - Source: `ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/`

## Data Storage

**Databases:**
- File-based (local filesystem only)
- Custom directory structure:
  - `DBDIR/taxonomy/` - Taxonomy dump files
  - `DBDIR/*_diffIdx` - Differential index files (can be deleted post-build)
  - `DBDIR/*_info` - Index metadata (can be deleted post-build)
  - Split indices for k-mer database partitioning

**Input/Output:**
- Input: FASTA/FASTQ files (sequence reads, optionally gzip compressed)
- Output: TSV format
  - `{JOBID}_classifications.tsv` - Per-read classification results
  - `{JOBID}_report.tsv` - Kraken2-compatible summary report
  - `{JOBID}_krona.html` - Interactive Krona visualization

**File Storage:**
- Local filesystem only (no cloud storage integration)
- Database files can be stored independently of RAM capacity
- Supports memory-mapped file access for large databases

## Caching

**Database Indexing:**
- K-mer index files cached on disk
- Syncmer index format (v1.0.8+) reduces database size 50%
- Index can be rebuilt if space is critical

## Authentication & Identity

**Authentication:**
- None - Metabuli is a standalone tool
- Database downloads are unauthenticated

**Taxonomy Ownership:**
- Databases reference external taxonomy sources (GTDB, NCBI)
- Taxonomy ownership managed by source institutions
- Custom taxonomy support for user-defined sequences

## Monitoring & Observability

**Logging:**
- Console output via `--print-log` parameter (default 0)
- Verbosity controlled via `--verbosity` parameter (default 3)
- Validation output for FASTA/FASTQ integrity checks

**Error Tracking:**
- Built-in validation options:
  - `--validate-input` (0/1) - Validate input FASTA/Q format
  - `--validate-db` (0/1) - Validate database files post-build
- No external error tracking service

## CI/CD & Deployment

**Hosting:**
- GitHub repository: `github.com/steineggerlab/Metabuli`
- Precompiled binaries: mmseqs.com
- Conda package: bioconda channel

**CI Pipeline:**
- Docker image available (`.github/workflows/docker.yml`)
- Dockerfile present for containerization

**Distribution Channels:**
- Conda: `conda install -c conda-forge -c bioconda metabuli`
- Static binaries: Platform-specific downloads from mmseqs.com
- Source compilation: Git repository with submodules

## Taxonomy Data Integration

**Taxonomy Formats:**
- NCBI-style DUMP files:
  - `nodes.dmp` - Taxonomy structure
  - `names.dmp` - Taxon names
  - `merged.dmp` - Obsolete taxon mappings
- GTDB taxdump format (via taxonkit compatibility)
- Taxonkit-generated GTDB dumps: `github.com/shenwei356/gtdb-taxdump`

**Taxonomy File Workflow:**
- Taxonomy path configurable: `--taxonomy-path` (defaults to `DBDIR/taxonomy/`)
- Manual download from NCBI or taxonkit sources
- Optional CDS (Coding Sequence) information to skip Prodigal prediction: `--cds-info` parameter
- Support for custom taxa extension via `--new-taxa` option

## Database Building

**Input Requirements:**
1. FASTA files with accession headers (matching `GC[AF]_[0-9]+\.[0-9]+` for GTDB)
2. Accession2taxid mapping file (tab-separated, 4 columns)
3. Taxonomy dump directory (nodes.dmp, names.dmp, merged.dmp)

**Build Commands:**
- `metabuli build` - Create new database from FASTA list
- `metabuli updateDB` - Add sequences to existing database
- `metabuli createnewtaxalist` - Generate new taxa entries

**Output Database Contents:**
- K-mer/syncmer index files
- Differential index files (`*_diffIdx`)
- Index metadata (`*_info`)
- Split partition files (configurable via `--split-num`, default 4096)

## Classification Workflow

**Input Processing:**
- Paired-end reads (default `--seq-mode 2`)
- Single-end reads (`--seq-mode 1`)
- Long reads (`--seq-mode 3`)
- Validation optional for quality assurance

**Output Generation:**
- Per-read classification in TSV format
- Kraken2-compatible aggregate report
- Interactive Krona HTML visualization
- Optional lineage information with `--lineage 1`

## Webhooks & Callbacks

**Incoming:**
- None - Metabuli is command-line only

**Outgoing:**
- None - Results written to local files only

---

*Integration audit: 2026-03-04*
