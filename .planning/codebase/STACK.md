# Technology Stack

**Analysis Date:** 2026-03-04

## Languages

**Primary:**
- C++ 17 - Core metagenomic classifier implementation
- C - Prodigal gene prediction engine and utility functions

**Build/Scripting:**
- Bash - Database download and deployment scripts

## Runtime

**Environment:**
- Unix/Linux/MacOS (cross-platform support)
- Windows (via precompiled binaries)
- ARM64 and AVX2/SSE2 CPU variants supported

**Build System:**
- CMake 3.15+ (minimum requirement)
- Default build type: Release

## Frameworks & Libraries

**Core Libraries:**
- MMseqs2 - Sequence database framework (with custom derived target setup)
- Prodigal - Gene prediction for DNA-to-protein conversion (`lib/prodigal/`)
- FASTA Validator - Input FASTA file validation (`lib/fasta_validator/`)
- FASTQ Utils - FASTQ file parsing and validation (`lib/fastq_utils/`)
- yxml - XML processing for UniRef data (`lib/yxml/`)

**System Libraries:**
- zlib - GZIP compression (for .gz file support)
- OpenMP - Multi-threaded parallelization
- Standard C++ libraries (STL)

## Key Dependencies

**Critical:**
- zlib - Required for compressed FASTA/FASTQ input handling
- Prodigal - Gene prediction step in database build process
- MMseqs2 - Underlying sequence search and indexing framework

**Build Integration:**
- MMseqs2 uses custom CMake module (`lib/mmseqs/cmake/MMseqsSetupDerivedTarget.cmake`)
- Framework-only build mode with custom parameter extensions

## Configuration

**Build Configuration:**
- `CMAKE_BUILD_TYPE=Release` (default, optimized)
- `CMAKE_CXX_STANDARD=17` (required C++ standard)
- `FRAMEWORK_ONLY=1` (forces MMseqs2 framework-only mode)

**Runtime Configuration:**
- Parameters managed via `LocalParameters` class in `src/commons/LocalParameters.h`
- Taxonomy path (customizable, defaults to `DBDIR/taxonomy/`)
- Thread count controlled via `--threads` parameter (OpenMP)
- RAM usage limits configurable via `--max-ram` parameter

**Input Formats Supported:**
- FASTA variants: `.fna`, `.fasta`, `.fa` (with optional `.gz` compression)
- FASTQ variants: `.fq`, `.fastq` (with optional `.gz` compression)
- Taxonomy files: NCBI-format (nodes.dmp, names.dmp, merged.dmp)
- Accession mapping: NCBI accession2taxid format

## Platform Requirements

**Development:**
- CMake 3.15 or later
- C++17 compatible compiler (GCC, Clang, MSVC)
- OpenMP support

**Compilation:**
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j 16
```

**Production:**
- Minimum: 8 GiB RAM for most analyses
- Supports custom RAM limits for constrained environments
- Database files stored on disk (can exceed available RAM)
- Tested with MacBook Air M1 (8 GiB) classifying 15M paired-end reads against 69 GiB database

**Distribution:**
- Static binaries provided for:
  - Linux (AVX2, SSE2 variants)
  - MacOS (Universal: ARM64/Intel)
  - Windows
  - Linux ARM64
- Conda package available via bioconda

---

*Stack analysis: 2026-03-04*
