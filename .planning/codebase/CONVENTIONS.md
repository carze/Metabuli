# Coding Conventions

**Analysis Date:** 2026-03-04

## Naming Patterns

**Files:**
- Header files: `.h` extension (e.g., `Classifier.h`, `LocalParameters.h`)
- Implementation files: `.cpp` extension (e.g., `Classifier.cpp`, `common.cpp`)
- Utility files: `.h` extension only when header-only (e.g., `Mmap.h`, `Match.h`)
- Template implementations: Inline in `.h` files or in separate `.h` files
- File names follow PascalCase: `KmerExtractor.h`, `QueryIndexer.h`, `TaxonomyWrapper.h`

**Classes:**
- PascalCase naming convention: `Classifier`, `KmerExtractor`, `QueryIndexer`, `LocalParameters`
- Base classes often use descriptive names indicating purpose: `KmerScanner`, `KmerMatcher`, `Reporter`
- Derived/specialized classes append specialization: `MetamerScanner` (extends `KmerScanner`), `KmerScanner_dna2aa`, `KmerScanner_aa2aa`, `SyncmerScanner` (extends `MetamerScanner`)

**Structs:**
- PascalCase naming: `Match`, `MappingRes`, `Assembly`, `KmerCnt`, `CDSinfo`, `Query`, `Classification`, `SequenceBlock`
- Data-only structs (no methods or minimal methods) are used for data containers and results

**Functions:**
- camelCase for member functions: `startClassify()`, `assignTaxonomy()`, `fillQueryKmerBuffer()`, `loadMappings()`, `getTaxCounts()`
- Function names are descriptive of action or purpose
- Getter/setter conventions: `getTaxCounts()`, `getQuerySplits()`, `getAvailableRam()`, `setKmerLen()`, `setBytesPerKmer()`
- Destructors follow naming pattern: `~ClassName()`

**Variables:**
- camelCase for local and member variables: `dbDir`, `matchPerKmer`, `queryIndexer`, `kmerExtractor`, `taxonomy`
- `_1` and `_2` suffixes indicate paired/related variables: `kseq1`, `kseq2`, `readNum_1`, `readNum_2`, `queryPath_1`, `queryPath_2`
- Private/protected member variables often use descriptive names: `mappingResList`, `emResults`, `topSpeciesSet`, `taxCounts`
- Boolean variables: `isClassified`, `isReverse`, `isFirstTime`, `isNewDB`, `newSpecies`, `complete`

**Constants:**
- UPPERCASE with underscores: `BufferSize`, `DNA_MASK`, `AA_MASK`, `HAMMING_LUT0`
- Macro definitions: `#define` statements use UPPERCASE: `#define BufferSize 16'777'216`, `#define likely(x)`, `#define unlikely(x)`
- Enum values: UPPERCASE (e.g., `EXIT_FAILURE`, `COMMAND_MAIN`, `COMMAND_DATABASE_CREATION`)

**Types:**
- Custom typedef: `TaxID` (used throughout for taxonomy IDs)
- Standard library types used: `std::vector`, `std::unordered_map`, `std::unordered_set`, `std::string`
- Integer types: sized types `uint32_t`, `uint64_t`, `uint8_t`, `size_t` for standard operations

## Code Style

**Formatting:**
- No automated formatter configured (no `.clang-format`, `.prettierrc`, or similar)
- Consistent 4-space indentation observed throughout codebase
- Brace style: Opening braces on same line for functions and control structures
- Line length: Generally under 100 characters, with some exceptions for parameter lists

**Include Organization:**
- Standard library headers first: `#include <cstddef>`, `#include <utility>`, `#include <iostream>`, `#include <fstream>`
- Macro checks: `#define` guards at top of headers with pattern `#ifndef METABULI_CLASSNAME_H`
- Project headers: `#include "LocalHeader.h"` relative to include path
- Grouped by dependency: closely related headers grouped together
- Example from `Classifier.h`:
  ```cpp
  #include "BitManipulateMacros.h"
  #include "Mmap.h"
  #include <fstream>
  #include "Kmer.h"
  #include "SeqIterator.h"
  #include "printBinary.h"
  #include "common.h"
  #include "NcbiTaxonomy.h"
  #include "Debug.h"
  ```

**Linting:**
- No linter configuration files detected
- Code compiles with C++17 standard: `set(CMAKE_CXX_STANDARD 17)` in CMakeLists.txt
- Uses `-Wall` flags for compilation warnings (inferred from Azure pipeline)

## Class Design Patterns

**Access Control:**
- Protected/private member variables for encapsulation
- Public methods for interface
- Protected methods for derived class access: `fillQueryKmerBufferParallel()`, `fillQueryKmerBuffer()` in `KmerExtractor`
- Example from `Classifier.h`:
  ```cpp
  protected:
      string dbDir;
      size_t matchPerKmer;
      unordered_map<TaxID, unsigned int> taxCounts;
  public:
      void startClassify(const LocalParameters &par);
      void assignTaxonomy(const Match *matchList, ...);
      explicit Classifier(LocalParameters & par);
      virtual ~Classifier();
  ```

**Constructors:**
- Explicit constructors preferred: `explicit Classifier(LocalParameters & par)`
- Explicit keyword prevents implicit conversion
- Default constructors: `LocalUtil() = default`
- Parameterized constructors with clear semantics

**Destructors:**
- Virtual destructors in base classes: `virtual ~Classifier()`
- Explicit cleanup in destructors: deleting heap allocations
- RAII pattern partially followed but not strictly enforced

**Method Organization:**
- Declaration in header file, implementation in `.cpp`
- Related methods grouped logically in declarations
- Private helper methods declared in private section
- Static utility methods separated from instance methods

## Error Handling

**Patterns:**
- Direct `exit()` calls for fatal errors: `exit(EXIT_FAILURE)` in `KmerScanner.h`, `QueryIndexer.cpp`
- stderr output for errors: `std::cerr << "Error: ..." << std::endl;`
- Debug logging framework used: `Debug(Debug::ERROR) << "message";` pattern in `common.cpp`
- Boolean returns for validation: `bool isFasta()`, `bool isFastq()`, `bool isValidQueryFile()`
- Return codes from file operations: `if (fstat(fileno(handle), &sb) < 0)` error checking
- Null pointer checks: `if (data == MAP_FAILED)`, `if (t != NULL)`
- File existence checks: `if (fileExist(dbDir + "/db.parameters"))`

**Exception Handling:**
- No C++ exceptions used (no try/catch blocks observed)
- All error handling through return codes and assertions

**Common Error Patterns:**
- File operations: `if (!fp)` checks before using file pointer
- Memory allocation: Direct `new` operator used, checked for null
- Regex/parsing validation: Parameter validation before use in `LocalParameters.cpp`

## Logging

**Framework:**
- Debug class macro system: `Debug(Debug::ERROR)`, `Debug(Debug::WARNING)`
- Pattern: `Debug(Debug::ERROR) << "message" << "\n";`
- Direct `std::cout` and `std::cerr` also used: `cout << "Database name : " << par.dbName << endl;`
- Stdout for informational messages, stderr for errors

**Patterns:**
- Informational output: Database stats, read counts, timing
- Example from `Classifier.cpp`:
  ```cpp
  cout << "--------------------" << endl;
  cout << "Total read count : " << queryIndexer->getReadNum_1() << endl;
  cout << "Total read length: " << queryIndexer->getTotalReadLength() << "nt" << endl;
  cout << "--------------------" << endl;
  ```
- Progress tracking: `tries++` and loop counters indicate processing phases

## Comments

**When to Comment:**
- Complex algorithms with non-obvious intent
- Regex patterns and bit manipulation operations
- Parameter explanations in struct/class definitions
- Magic numbers with clarification (e.g., `16'777'216 // 16 * 1024 * 1024 // 16 M`)

**Comment Style:**
- Single-line: `// comment`
- Multi-line: Not extensively used
- Inline comments for magic numbers: `16'777'216 //16 * 1024 * 1024 // 16 M`
- Commented-out code preserved for reference: Example in `Classifier.cpp` constructor shows commented alternatives

**Documentation Comments:**
- No extensive Doxygen/JSDoc style comments
- Function headers use informal comments describing purpose
- Struct member documentation through inline comments or code clarity

## Template Usage

**Patterns:**
- Template classes used for generic algorithms: `Buffer<T>`, `MmapedData<T>`, `WriteBuffer<T>`
- Template methods in utility classes: `LocalUtil::getQueryKmerNumber()`, `LocalUtil::getMaxCoveredLength()`
- Template implementation inline in headers for header-only utilities
- Example from `LocalUtil.h`:
  ```cpp
  template<typename T>
  static T getQueryKmerNumber(T queryLength, int spaceNum, int kLength = 8);

  template<typename T>
  T LocalUtil::getQueryKmerNumber(T queryLength, int spaceNum, int kLength) {
      return (getMaxCoveredLength(queryLength) / 3 - kLength - spaceNum + 1) * 6;
  }
  ```

## Import Organization

**Typical Header Imports:**
```cpp
#ifndef METABULI_CLASSNAME_H
#define METABULI_CLASSNAME_H

// Standard library (STL)
#include <cstddef>
#include <utility>
#include <iostream>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cmath>

// Project includes
#include "LocalParameters.h"
#include "common.h"
#include "Debug.h"
#include "FileUtil.h"

// Class definition follows
```

**Order:**
1. Include guards with pattern `#ifndef METABULI_FILENAME_H`
2. Standard library includes with angle brackets
3. Project includes with quotes
4. Conditionally compiled sections
5. `using namespace std;` (present in some files, not all)

## Parameter Passing

**Conventions:**
- Const references for read-only parameters: `const LocalParameters &par`, `const std::string & queryPath`
- Non-const references for modification: `std::vector<Query> & queryList`, `Buffer<Kmer> &kmerBuffer`
- Pointers for heap-allocated objects and optional outputs: `FILE* handle`, `MappingRes * mappingResList`
- Value types for primitives when not modified: `int queryId`, `float score`

**Example from `KmerExtractor.h`:**
```cpp
void fillQueryKmerBufferParallel(
    KSeqWrapper* kseq1,
    Buffer<Kmer> &kmerBuffer,
    vector<Query> & queryList,
    const QuerySplit & currentSplit,
    const LocalParameters &par);
```

## Macro Usage

**Bit Manipulation Macros:**
- Located in `src/commons/BitManipulateMacros.h`
- Example: `#define likely(x) __builtin_expect((x),1)` for branch prediction
- Example: `#define unlikely(x) __builtin_expect((x),0)`
- Example: `#define AA(kmer) ((kmer) & ~16777215)`

**Buffer Size Macros:**
- `#define BufferSize 16'777'216` (16MB)
- Used consistently across multiple classes for memory management

---

*Convention analysis: 2026-03-04*
