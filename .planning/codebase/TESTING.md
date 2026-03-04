# Testing Patterns

**Analysis Date:** 2026-03-04

## Test Framework

**C++ Testing:**
- No C++ unit test framework detected (no GTest, Catch2, or Boost.Test configuration)
- C++ validation is performed via integration testing through main application workflows
- Build system: CMake, with no test target configured in `CMakeLists.txt`

**Python Testing:**
- Framework: pytest
- Used for utility scripts in `util/gtdb_to_taxdump/` module
- Config file: Not present (uses pytest defaults)
- Test runner: Direct pytest execution via pytest conventions

**Run Commands:**
```bash
# Python tests (from util/gtdb_to_taxdump directory)
pytest tests/                          # Run all pytest tests
pytest tests/test_gtdb2td.py          # Run specific test file
pytest tests/ -v                      # Verbose mode (inferred)
```

**Test Discovery:**
- C++: No automated test discovery (no test framework)
- Python: pytest auto-discovers `test_*.py` and `*_test.py` files in `tests/` directory

## Test File Organization

**Location:**
- Python tests: `util/gtdb_to_taxdump/tests/` directory
- Co-located with source: Test files stored separately in dedicated `tests/` subdirectory
- C++ code: No dedicated test directory (integration testing only)

**File Structure:**
```
util/gtdb_to_taxdump/
├── tests/
│   ├── data/              # Test data files
│   ├── test_Dmnd.py       # Diamond tool tests
│   ├── test_Lineage.py    # Lineage conversion tests
│   ├── test_Map.py        # Mapping tests
│   ├── test_acc2tax.py    # Accession to taxonomy tests
│   └── test_gtdb2td.py    # Main GTDB to taxdump tests
├── setup.py
└── bin/
    ├── gtdb_to_taxdump.py
    ├── gtdb_to_diamond.py
    ├── lineage2taxid.py
    └── ...
```

**Naming:**
- Pattern: `test_*.py` for pytest discovery
- Names indicate what is being tested: `test_Dmnd.py`, `test_Lineage.py`, `test_gtdb2td.py`

## Test Structure

**Python Test Pattern:**
```python
#!/usr/bin/env python
from __future__ import print_function
import os
import sys
import pytest

# Test data directory setup
test_dir = os.path.join(os.path.dirname(__file__))
data_dir = os.path.join(test_dir, 'data')

# Tests use script_runner fixture from pytest-console-scripts plugin
def test_help(script_runner):
    ret = script_runner.run('gtdb_to_taxdump.py', '-h')
    assert ret.success, ret.print()

def test_r89(script_runner, tmp_path):
    arc = os.path.join(data_dir, 'gtdb_r89.0', 'ar122_taxonomy_r89.tsv')
    bac = os.path.join(data_dir, 'gtdb_r89.0', 'bac120_taxonomy_r89_n10k.tsv')
    outdir = os.path.join(str(tmp_path), 'gtdb2td')
    ret = script_runner.run('gtdb_to_taxdump.py', '--outdir', outdir,
                            arc, bac, print_result=False)
    assert ret.success, ret.print()
```

**Test Fixtures:**
- `script_runner`: From pytest-console-scripts plugin; runs installed scripts
- `tmp_path`: Built-in pytest fixture providing temporary directory
- Standard pytest test setup with no custom fixtures defined

**Assertion Pattern:**
- Simple `assert` statements with optional failure messages
- `assert ret.success, ret.print()` - asserts return code success and prints output on failure

## Test Types

**Integration Tests:**
- Full application testing through CLI invocation
- Tests validate end-to-end workflows of utility scripts
- Examples:
  - `test_help`: Validates script help output works
  - `test_r89`: Tests GTDB R89 conversion with real data
  - `test_r89_remote`: Tests remote data source handling

**C++ Integration:**
- Main application tested through command-line interface
- No unit test framework for C++ components
- Testing performed via Azure Pipelines with compilation in multiple configurations (AVX2, SSE2)
- Different MPI configurations tested: `MPI: 0` and `MPI: 1`

## Coverage

**Requirements:**
- No coverage reporting configured (no `.coveragerc` or similar)
- No minimum coverage threshold enforced
- Coverage analysis not automated in CI/CD

**Python Testing Scope:**
- Limited test coverage: Only utility scripts in `util/gtdb_to_taxdump/` have tests
- Main C++ application (Metabuli classifier) has no dedicated unit tests
- Testing relies on integration testing and manual validation

## Validation Strategy

**C++ Code Validation:**
- Compilation validation across platforms: Ubuntu 22.04
- SIMD variants tested: AVX2, SSE2
- Static build: `STATIC: 1` in CI configuration
- MPI variants tested: Serial and MPI builds
- Regression testing flag: `regression: 1` variable set in Azure Pipelines

**Python Script Validation:**
- Help/usage validation: `test_help` pattern
- Data format validation: Tests with real GTDB taxonomy data
- Output correctness: Results checked for success flag
- File handling: Temporary path testing ensures proper file I/O

## Test Dependencies

**Python Test Requirements:**
- pytest (test framework)
- pytest-console-scripts (for `script_runner` fixture)
- networkx, tqdm (runtime dependencies listed in `setup.py`)
- numpy (required for compilation)

**C++ Build Requirements:**
- CMake 3.15+
- C++17 compatible compiler (GCC 11+ or equivalent)
- MMSeqs2 library (built from `lib/mmseqs` submodule)
- Prodigal library (built from `lib/prodigal` submodule)
- zlib dependency (for compression)

## CI/CD Testing

**Azure Pipelines Configuration:**
- File: `azure-pipelines.yml`
- Job: `build_ubuntu` with Ubuntu 22.04 VM
- Matrix strategy testing multiple configurations:
  ```
  - SIMD: AVX2, STATIC: 1, MPI: 0, BUILD_TYPE: Release
  - SIMD: SSE2, STATIC: 1, MPI: 0 (inherits Release)
  - Additional configurations in full file (238 lines total)
  ```
- Timeout: 120 minutes
- Regression: Enabled (`regression: 1`)

**Build Process:**
```bash
# Inferred from CMakeLists.txt
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=g++ -DCMAKE_C_COMPILER=gcc .
make
# No explicit test target configured
```

## Testing Gaps

**C++ Application:**
- No unit tests for core classes: `Classifier`, `KmerExtractor`, `KmerMatcher`, `QueryIndexer`
- No tests for:
  - `src/commons/` core functionality
  - `src/uniref/` UniRef classification logic
  - `src/read-group/` group generation features
  - File I/O operations
  - Taxonomy operations
  - Error handling paths

**Python Utilities:**
- Limited test suite (5 test files)
- Some utility scripts lack tests: `ncbi-gtdb_map.py`, `acc2gtdb_tax.py`
- No parametrized tests for multiple input variants
- No error condition testing (invalid inputs, corrupt data)

**Overall Test Landscape:**
- Primarily integration/functional testing
- Minimal unit test coverage for C++ core logic
- No automated performance/regression testing (beyond compilation)
- No fuzzing or robustness testing

## Test Data

**Location:**
- Python tests use `tests/data/` directory
- Contains GTDB taxonomy files: `gtdb_r89.0/`, `ar122_taxonomy_r89.tsv`, `bac120_taxonomy_r89_n10k.tsv`
- Sample data files included with test suite
- Remote data source tested: `https://data.ace.uq.edu.au/public/gtdb/data/releases/`

**Data Management:**
- Local test data in repository
- Remote data tested via network (internet connectivity required)
- Temporary output created in `tmp_path` fixture (auto-cleaned by pytest)

## Error Testing

**Current Approach:**
- No explicit error/exception testing detected
- Success validation: `assert ret.success, ret.print()`
- No tests for invalid input handling
- No tests for edge cases or malformed data

**Recommended Pattern (Not Currently Used):**
```python
def test_invalid_input(script_runner):
    ret = script_runner.run('script.py', '--invalid-arg')
    assert ret.returncode != 0  # Expect failure
    assert 'error' in ret.stderr.lower() or 'error' in ret.stdout.lower()
```

---

*Testing analysis: 2026-03-04*
