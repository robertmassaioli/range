# Proposal: Add Benchmark Suite

## Motivation

The README and Haddock documentation prominently advertise performance as the library's primary value proposition, including an inline GHCi timing comparison (`elem` vs `inRange`) that shows orders-of-magnitude improvement. However, there are no automated benchmarks in the repository. This means:

1. **No regression protection.** A refactor that accidentally degrades `mergeRanges` from O(n log n) to O(n²) would pass all existing tests.
2. **No substantiated claims.** The numbers in the documentation are hand-run GHCi snippets, not reproducible measurements. Anyone evaluating the library for production use has to trust informal timings.
3. **No visibility into how operations scale.** The library's internal `RangeMerge` representation relies on sorted span lists. Whether operations degrade gracefully as the number of disjoint spans grows into the thousands or tens of thousands is currently unknown.

A proper benchmark suite addresses all three.

## Tool Choice: `tasty-bench`

**Recommendation: Use `tasty-bench` rather than `criterion`.**

Rationale:
- `tasty-bench` has far fewer transitive dependencies than `criterion` (~5 vs ~40), keeping the dependency footprint small for a library this lean.
- It integrates with the `tasty` test framework, which is the modern successor to `test-framework` (used by this project's test suite). This alignment is useful if we later migrate the tests to `tasty` as well.
- It produces CSV output suitable for CI comparison, and supports `--baseline` for automated regression detection.
- For the kinds of benchmarks this library needs (microsecond-to-millisecond operations on pure data), `tasty-bench` is more than sufficient. We don't need `criterion`'s advanced statistical analysis.

## Benchmark Structure

### File layout

```
Bench/
  Range.hs        -- main benchmark entry point
```

### Cabal stanza

```cabal
benchmark bench-range
  type:             exitcode-stdio-1.0
  main-is:          Bench/Range.hs
  build-depends:    base >= 4.7 && < 5
                  , range
                  , tasty-bench >= 0.3 && < 1
  default-language: Haskell2010
  ghc-options:      -Wall -O2 -rtsopts
```

The `-O2` is critical — benchmarks must be compiled with optimisations to produce meaningful numbers. The existing library stanza doesn't specify an optimisation level (defaults to `-O1` under GHC), so benchmarks with `-O2` will measure the realistic "installed library" performance.

## What to Benchmark

The benchmarks should cover three categories: **point queries** (the primary documented use case), **set operations** (the algebraic core), and **construction/conversion** (loading and merging).

### Category 1: Point Queries

These are the operations the README highlights. Benchmark them across input sizes to show the scaling advantage over naive list traversal.

| Benchmark | Description | Input sizes |
|-----------|-------------|-------------|
| `inRange/SpanRange` | Single span containment check | N/A (constant time) |
| `inRange/LowerBoundRange` | Half-bounded containment | N/A (constant time) |
| `inRanges/disjoint-spans` | Check membership across N disjoint spans | 10, 100, 1000, 10000 |
| `inRanges/vs-elem` | Compare `inRanges` against `Data.List.elem` on equivalent enumerated list | 1000, 10000, 100000 |
| `aboveRanges/disjoint-spans` | Check if value is above all ranges | 10, 100, 1000 |
| `belowRanges/disjoint-spans` | Check if value is below all ranges | 10, 100, 1000 |

The `inRanges/vs-elem` benchmark is specifically to reproduce and substantiate the claim in the `Data.Range` Haddock documentation. The others reveal how `inRanges` (which is `any . inRange`) scales linearly with the number of ranges — important for users who accumulate many disjoint ranges.

### Category 2: Set Operations

These exercise the `RangeMerge` internals — `unionRangeMerges`, `intersectionRangeMerges`, `invertRM` — through the public API. The interesting dimension is how many disjoint spans the internal representation is carrying.

| Benchmark | Description | Input sizes |
|-----------|-------------|-------------|
| `mergeRanges/already-merged` | Merge ranges that are already non-overlapping | 10, 100, 1000 |
| `mergeRanges/fully-overlapping` | Merge N ranges that all overlap (worst case for union) | 10, 100, 1000 |
| `mergeRanges/random` | Merge N randomly generated ranges (realistic case) | 10, 100, 1000 |
| `union/disjoint` | Union of two disjoint range sets of size N | 10, 100, 1000 |
| `union/overlapping` | Union of two overlapping range sets | 10, 100, 1000 |
| `intersection/disjoint` | Intersection of two disjoint sets (should be fast — empty result) | 10, 100, 1000 |
| `intersection/dense` | Intersection of two heavily overlapping sets | 10, 100, 1000 |
| `difference/N` | Difference of two range sets | 10, 100, 1000 |
| `invert/N-spans` | Invert a range with N disjoint spans | 10, 100, 1000 |

The `mergeRanges/fully-overlapping` benchmark is particularly important because it exercises the `insertionSortSpans` + `unionSpans` pipeline in `Data.Range.Spans`, which uses an insertion-sort merge. If that becomes quadratic at scale, this benchmark will show it.

### Category 3: Construction and Conversion

| Benchmark | Description | Input sizes |
|-----------|-------------|-------------|
| `loadRanges/N` | Convert `[Range a]` → `RangeMerge a` | 10, 100, 1000 |
| `exportRangeMerge/N` | Convert `RangeMerge a` → `[Range a]` | 10, 100, 1000 |
| `fromRanges/take-N` | `take N . fromRanges` on a set of 10 ranges | 100, 1000, 10000 |
| `joinRanges/N-adjacent` | Join N adjacent integer ranges | 10, 100, 1000 |

The `fromRanges/take-N` benchmark is relevant to improvement suggestion #7 (`takeEvenly` is O(n²)). It establishes a measurable baseline before any optimisation.

### Category 4: Algebra Expressions

| Benchmark | Description | Input sizes |
|-----------|-------------|-------------|
| `Alg.eval/deep-union-tree` | Evaluate a left-skewed tree of N unions | 5, 10, 20 |
| `Alg.eval/deep-intersection-tree` | Evaluate a left-skewed tree of N intersections | 5, 10, 20 |
| `Alg.eval/mixed-tree` | Evaluate a balanced tree mixing union, intersection, invert | 5, 10, 20 |

These directly test whether the algebra's deferred-evaluation design (avoiding repeated `loadRanges`/`exportRangeMerge` round-trips) actually delivers measurable savings. They would also catch a regression if the `rangeAlgebra` function (see improvement suggestion #6) were changed.

## Input Generation Strategy

Benchmarks need deterministic, reproducible inputs — not QuickCheck-generated ones.

```haskell
-- N disjoint spans covering [0,2), [3,5), [6,8), ...
disjointSpans :: Int -> [Range Integer]
disjointSpans n = [fromIntegral (i * 3) +=+ fromIntegral (i * 3 + 1) | i <- [0..n-1]]

-- N fully overlapping spans all within [0, 1000]
overlappingSpans :: Int -> [Range Integer]
overlappingSpans n = [fromIntegral i +=+ (fromIntegral i + 1000) | i <- [0..n-1]]

-- A pre-merged baseline for operations that take already-merged input
mergedInput :: Int -> [Range Integer]
mergedInput = mergeRanges . disjointSpans
```

All inputs should be evaluated to NF before benchmarking using `env` (in `tasty-bench`) or `deepseq`. This requires an `NFData` instance for `Range a` — either derived via `Generic` or hand-written. This is a small addition to `Data.Range.Data` (also mentioned in improvement suggestion #9).

## CI Integration

### Stack command

```bash
stack bench --benchmark-arguments '--csv bench-results.csv +RTS -T'
```

The `+RTS -T` flag enables GC statistics, allowing `tasty-bench` to report allocation numbers alongside wall-clock time.

### GitHub Actions step

Add to `.github/workflows/ci.yml`:

```yaml
      - name: Benchmark
        run: stack bench --benchmark-arguments '--csv bench-results.csv +RTS -T'

      - name: Upload benchmark results
        uses: actions/upload-artifact@v4
        with:
          name: benchmarks
          path: bench-results.csv
```

### Regression detection (optional future step)

`tasty-bench` supports `--baseline bench-results.csv` which compares current results against a saved baseline and fails if any benchmark regresses by more than a configurable threshold (default 20%). This could be integrated by:

1. Committing a `bench-baseline.csv` to the repository.
2. Running `--baseline bench-baseline.csv --fail-if-slower 15` in CI.
3. Updating the baseline file when intentional performance changes are made.

This is a nice-to-have for later — the first version should just generate and archive numbers.

## Dependencies Added

| Package | Version | Transitive deps added |
|---------|---------|----------------------|
| `tasty-bench` | `>= 0.3 && < 1` | ~5 (tasty, tagged, optparse-applicative, ansi-terminal, a few more) |
| `deepseq` | Already a transitive dep of `base` | 0 |

This is significantly lighter than `criterion`, which would pull in ~40 additional packages including `aeson`, `vector`, `statistics`, `microstache`, etc.

## Implementation Order

1. Add `NFData` instance for `Range a` and `Bound a` in `Data.Range.Data`.
2. Create `Bench/Range.hs` with the input generators and benchmark groups.
3. Add the `benchmark` stanza to `range.cabal`.
4. Add the GitHub Actions step.
5. Run the suite, inspect results, and adjust input sizes if any benchmarks take too long or too short to measure reliably.
6. Commit initial `bench-baseline.csv` once numbers are stable.
