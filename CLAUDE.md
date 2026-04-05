# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the library
stack build

# Run all tests
stack test

# Build without running tests (faster iteration)
stack build --test --no-run-tests

# Load the test suite in a REPL for interactive testing
stack ghci range:test-range

# Run the benchmark suite
stack bench

# Run benchmarks and save results to CSV
stack bench --benchmark-arguments '--csv bench-results.csv'
```

## Architecture

This is a Haskell library (`range`) for efficient range operations. It works on any `Ord` type — integers, versions, custom ordered types.

### Public API (exposed modules)

- **`Data.Range`** — Primary module. Use this for most purposes. Provides `Range a` data type, construction operators, and all set operations as functions on `[Range a]`.
- **`Data.Ranges`** — Alternative interface wrapping `[Range a]` in a `newtype Ranges a` that implements `Semigroup`/`Monoid` (union semantics). More composable in Haskell idioms.
- **`Data.Range.Algebra`** — F-Algebra based API using `RangeExpr` for building deferred expression trees of set operations. Evaluates via `eval :: RangeAlgebra a => RangeExpr [Range a] -> a`, avoiding repeated conversion to/from internal representation. Supports two evaluation targets: `[Range a]` (concrete ranges) and `a -> Bool` (predicate).
- **`Data.Range.Parser`** — Parsec-based parser for range expressions from strings.

### Key Data Types (`Data.Range.Data`)

- `Range a` — Sum type: `SingletonRange a | SpanRange (Bound a) (Bound a) | LowerBoundRange (Bound a) | UpperBoundRange (Bound a) | InfiniteRange`
- `Bound a` — A value with `BoundType` (`Inclusive | Exclusive`)
- `OverlapType` — `Separate | Overlap | Adjoin` (internal)

### Internal representation (`Data.Range.RangeInternal`)

All set operations convert to `RangeMerge a` internally — an efficient structure separating the span ranges (sorted, non-overlapping list of `(Bound, Bound)` pairs) from optional lower/upper infinite bounds. `IRM` represents the infinite range. The algebra layer (`Algebra.Internal`) operates directly on `RangeMerge a` to avoid redundant conversions.

### Range operators

The library uses symbolic operators for concise range construction:
- `+=+` inclusive-inclusive span
- `+=*` inclusive-exclusive span  
- `*=+` exclusive-inclusive span
- `*=*` exclusive-exclusive span
- `lbi`/`lbe` — lower bound inclusive/exclusive
- `ubi`/`ube` — upper bound inclusive/exclusive
- `inf` — infinite range

### Tests

Tests use `test-framework` + `QuickCheck` (property-based). Main test entry: `Test/Range.hs`, with helpers in `Test/RangeMerge.hs`.

### GHC compatibility

The library targets GHC 8.0+ (v7 support was removed). CPP guards in `Data/Ranges.hs` and `Data/Range/Algebra/Internal.hs` handle `base` version differences (`MIN_VERSION_base` checks). The library is marked `{-# LANGUAGE Safe #-}` throughout.
