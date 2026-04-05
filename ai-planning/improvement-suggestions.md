# Codebase Improvement Suggestions

Items marked **[DONE]** have been implemented.

## 1. Missing set-theoretic property tests **[DONE]**

The `Test/Range.hs` tests cover almost no algebraic laws at the `[Range a]` level — they only test `invert` and a few membership checks. The internal `RangeMerge` layer has good De Morgan / identity coverage, but the public API surface lacks properties like:
- Idempotency: `mergeRanges (mergeRanges xs) == mergeRanges xs`
- Commutativity: `union a b == union b a`
- Associativity of union/intersection
- Distributivity: `intersection a (union b c) == union (intersection a b) (intersection a c)`
- `difference a b == intersection a (invert b)` at the list level

These are the contracts users rely on and they're currently untested at the public API layer.

Implemented in `Test/RangeLaws.hs` with 15 QuickCheck properties covering idempotency, commutativity, associativity, distributivity, identity/absorption laws, difference, and double-invert. Shared `Arbitrary` instances extracted to `Test/Generators.hs`.

## 2. The `Arbitrary (Range a)` generator only produces `Inclusive` span bounds

In `Test/Range.hs:70-71`, the span generator always uses `+=+` (inclusive/inclusive). `Exclusive` bounds are never exercised in any generated `SpanRange`. This means properties involving exclusive bounds are only tested at the `RangeMerge` level (via `maybeBound` in `RangeMerge.hs`), not through the public API.

## 3. No benchmark suite **[DONE]**

The README prominently advertises performance as the primary value proposition (with a GHCi timing comparison in the docs), but there's no `criterion` or `tasty-bench` benchmark suite in the cabal file. Given that performance is a selling point, a suite testing `inRanges` on large lists of ranges, `mergeRanges` on pathological inputs, and `intersection` on dense overlapping ranges would both protect against regressions and substantiate the performance claims.

Implemented in `Bench/Range.hs` using `tasty-bench`: 55 benchmarks across point queries, set operations, construction/conversion, and algebra expression trees. `NFData` instances added to `Range`, `Bound`, `BoundType`, and `OverlapType`. CI uploads `bench-results.csv` as an artifact. Run with `stack bench`.

## 4. Parser only supports non-negative integers with `Read`

`Data.Range.Parser` uses `many1 digit` (`readSection`, line 95) which only handles non-negative integers in the input string, despite the type being `(Read a) => ... [Range a]`. Negative numbers are silently parsed as a range (e.g. `"-5"` becomes `UpperBoundRange 5`, not `SingletonRange (-5)`). This is documented implicitly by the example but is a real usability footgun — worth either documenting the constraint explicitly in the type or extending the parser to support negative literals.

## 5. `Data.Ranges` module has an incomplete module doc comment

`Data/Ranges.hs:8-10` has a dangling haddock comment: `-- | This module provides a simpler interface...` followed by `-- ` and then nothing before `module Data.Ranges`. The comment was started but never finished. This will render as an incomplete paragraph in generated Haddock docs.

## 6. `rangeAlgebra` converts through `RangeMerge` on every node

`Data/Range/Algebra/Range.hs:10` — `rangeAlgebra` calls `loadRanges` on each leaf and `exportRangeMerge` on each result, meaning an expression tree of depth N does N round-trips through export. The `rangeMergeAlgebra` in `Algebra.Internal` is already correct and works directly on `RangeMerge a`. `rangeAlgebra` should evaluate to `RangeMerge a` first (using `iter rangeMergeAlgebra`) and only call `exportRangeMerge` once at the top — which is exactly what the `RangeAlgebra [Range a]` instance in `Algebra.hs:78` already does correctly. The `rangeAlgebra` helper function appears to be doing redundant conversions per node.

## 7. `takeEvenly` in `Util.hs` is O(n²)

`takeEvenly` (line 131) calls `map safeHead`, `map tail`, and `filter (not . null)` on the entire list of sublists on every element emitted. For `fromRanges` over many ranges this becomes quadratic. A more efficient approach would zip with indices or use a queue/cycle. Given `fromRanges` is already documented as a convenience/non-performance function this is low priority, but worth noting — especially since it affects users who call `take n . fromRanges` with large `n`.

## 8. `RangeMerge` invariants are undocumented and unenforced

`RangeInternal.hs:13-21` documents three invariants as a comment block but there's no `newtype` wrapper, smart constructor, or `assert`-guarded constructor to enforce them. A single malformed `RangeMerge` (e.g. unsorted spans, overlapping spans) passed to `unionRangeMerges` or `intersectionRangeMerges` will produce silently wrong results. At minimum, a `validateRangeMerge :: RangeMerge a -> Bool` function usable in tests would be valuable.

## 9. No `Ord` instance for `Range`

`Range a` has `Eq` and `Show` but no `Ord`, `NFData`, or `Hashable` instances. `Ord` is the most consequential missing one — users who want to store ranges in `Set` or as `Map` keys, or sort a list of ranges for display, currently can't without defining orphan instances themselves. A derived or manual `Ord` would be a non-breaking addition.

`NFData` was added as part of item 3 (benchmark suite). `Ord` and `Hashable` remain unimplemented.

## 10. `Data.Range.Parser` has no tests

The parser module has zero test coverage. It's a real user-facing input surface (explicitly intended for CLI programs) with at least one known edge case (negative numbers, see #4). A small HUnit or QuickCheck test group covering: round-trip `show`/`parse` for valid inputs, `parseRanges` on the examples from the module Haddock, and a few known-invalid inputs, would meaningfully improve confidence.
