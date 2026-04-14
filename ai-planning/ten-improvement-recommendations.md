# Ten Improvement Recommendations for the `range` Library

This document proposes ten concrete improvements across functionality, performance,
testing, documentation, and API design. Each recommendation is self-contained and
can be implemented independently.

---

## 1. ✅ Fix O(n²) `takeEvenly` in `Data/Range/Util.hs` [DONE]

**Category:** Performance

**Current situation:**  
`takeEvenly` (line 130 of `Util.hs`) interleaves multiple lists by repeatedly calling
`map safeHead` and `filter (not . null) . map tail` on the entire input list at every
recursion step. This is O(n·m) where n is the total number of elements and m is the
number of sublists.

```haskell
-- Current O(n²) implementation
takeEvenly xss = (catMaybes . map safeHead $ xss) ++ takeEvenly (filter (not . null) . map tail $ xss)
```

**Recommendation:**  
Rewrite using a single pass with `Data.List.transpose`:

```haskell
takeEvenly :: [[a]] -> [a]
takeEvenly = concat . transpose
```

`Data.List.transpose` already handles lists of different lengths correctly and
runs in O(n) where n is the total number of elements. The semantics are identical
to the current implementation.

---

## 2. Replace linear `inRanges` scan with binary search

**Category:** Performance

**Current situation:**  
`inRanges :: Ord a => a -> [Range a] -> Bool` (exposed via `Data.Range`) folds over
the full list of ranges with an `any`/`elem`-style check. After `mergeRanges` the
ranges are in a canonical sorted, non-overlapping form, but this structure is never
exploited for lookup.

**Recommendation:**  
Add a `canonicalInRanges :: Ord a => a -> [Range a] -> Bool` variant (or replace
the internals of `inRanges` after a `mergeRanges` call) that uses binary search on
the sorted span list. Because the ranges are non-overlapping and sorted after
canonicalisation, a divide-and-conquer search reduces point membership from O(n) to
O(log n). This is especially valuable when checking many points against a fixed range
set (e.g. an IP allowlist or version constraint checker).

---

## 3. Generate exclusive bounds in `Arbitrary (Range a)`

**Category:** Testing

**Current situation:**  
`Test/Generators.hs` defines:

```haskell
generateSpan first second = first +=+ second
```

This always produces `SpanRange (Bound x Inclusive) (Bound y Inclusive)`.
Exclusive bounds (`+=*`, `*=+`, `*=*`) are never generated, so QuickCheck
properties never exercise the exclusive-bound code paths in `Spans.hs`,
`RangeInternal.hs`, or `Util.hs`.

**Recommendation:**  
Replace `generateSpan` with a generator that picks `BoundType` independently for
each end:

```haskell
generateSpan first second = do
  loType <- elements [Inclusive, Exclusive]
  hiType <- elements [Inclusive, Exclusive]
  return $ SpanRange (Bound first loType) (Bound second hiType)
```

Also update `generateLowerBound` and `generateUpperBound` similarly. This doubles
the effective coverage of the property suite with no new test logic required.

---

## 4. Add a `Read` instance consistent with the custom `Show`

**Category:** API / Usability

**Current situation:**  
`Range a` has a hand-written `Show` instance that outputs operator shorthand
(`1 +=+ 5`, `lbi 3`, `inf`, etc.). There is no matching `Read` instance, so
`read . show` does not round-trip. This violates the standard Haskell convention
that `read . show == id` for showable types.

**Recommendation:**  
Add a `Read` instance (or at minimum a `readRange :: Read a => ReadS (Range a)`
function) in a new module `Data.Range.Read` that parses the same surface syntax
emitted by `Show`. Export it from `Data.Range`. This makes the type usable as a
serialisation format in config files, test fixtures, and REPL sessions without
reaching for the Parsec-based `Data.Range.Parser`.

---

## 5. Add `Functor`, `Foldable`, and `Traversable` instances for `Range`

**Category:** Functionality

**Current situation:**  
`Range a` is a plain `data` type with no `Functor`/`Foldable`/`Traversable`
instances. Users who want to transform the values inside a range (e.g. map a
version conversion over a `Range Version`) must pattern-match manually.

**Recommendation:**  
Derive or write `Functor` and `Foldable` instances, and derive `Traversable` via
`DeriveTraversable`. `Functor` would allow:

```haskell
fmap (* 2) (1 +=+ 5 :: Range Int)   -- 2 +=+ 10
fmap negate (lbi 3 :: Range Int)     -- ube (-3)   -- note: callers must re-merge
```

Document that `fmap` on a `SpanRange` does not automatically preserve the
`lo <= hi` invariant if the function is not monotone — callers must apply
`mergeRanges` afterwards when the function may reorder bounds.

`Foldable` lets users use `toList`, `null`, `length`, `minimum`, `maximum` on
singleton and span ranges in a natural way.

---

## 6. Support exclusive bounds and negative literals in the parser

**Category:** Functionality

**Current situation:**  
`Data/Range/Parser.hs` only produces `Inclusive` bounds and cannot parse negative
integer literals (a leading `-` is interpreted as the range separator). Users who
need exclusive bounds or negative values must construct ranges programmatically.

**Recommendation:**  
Extend `RangeParserArgs` with an `exclusiveBoundChar :: Maybe Char` field (default
`Nothing` for backwards compatibility). When set (e.g. `Just ')'` / `Just '('`),
the parser recognises interval notation such as `[1,5)` or `(0,10]`. Additionally,
when `rangeSeparator` is not `"-"` (e.g. `".."`), allow leading `-` in numeric
literals so negative values can be parsed. Both extensions are opt-in, preserving
existing behaviour.

---

## 7. Expose `RangeMerge` validation as a library function

**Category:** Correctness / Testing

**Current situation:**  
The `RangeMerge a` internal representation has several structural invariants
(span ranges are sorted, non-overlapping, and non-adjacent; `IRM` is the only
constructor for an infinite range). These invariants are only checked informally
during development; there is no public `validateRangeMerge` function that callers
or tests can use to assert correctness.

**Recommendation:**  
Add `validateRangeMerge :: Ord a => RangeMerge a -> Either String (RangeMerge a)`
(or expose it in a `Data.Range.Internal` module marked `@since` with a stability
warning). Write a QuickCheck property:

```haskell
prop_mergePreservesInvariants :: [Range Int] -> Bool
prop_mergePreservesInvariants rs =
  isRight . validateRangeMerge . toRangeMerge . mergeRanges $ rs
```

This would have caught at least one class of bugs found during the prior doctest
work where adjoining exclusive/inclusive spans were not correctly merged.

---

## 8. Add `Data.Range.Enum` for contiguous enumeration of bounded ranges

**Category:** Functionality

**Current situation:**  
There is no way to enumerate the elements of a `Range a` when `a` is a bounded
`Enum`. Users wanting `[1..5]` from `1 +=+ 5` must pattern-match themselves and
call `enumFromTo`.

**Recommendation:**  
Add a module `Data.Range.Enum` (or functions in `Data.Range`) exposing:

```haskell
-- | Enumerate all elements in a range. Returns Nothing for infinite ranges.
toEnumRange :: (Enum a, Bounded a) => Range a -> Maybe [a]

-- | Enumerate across a list of merged ranges.
toEnumRanges :: (Enum a, Bounded a) => [Range a] -> Maybe [a]
```

For `LowerBoundRange` / `UpperBoundRange` use `Bounded` sentinels (`minBound`,
`maxBound`). Document that this is only sensible for small domains (e.g. `Char`,
small `Int` subsets); for large domains users should use membership testing
(`inRanges`) instead.

---

## 9. Document the canonical form contract on `mergeRanges`

**Category:** Documentation

**Current situation:**  
`mergeRanges` is documented as "Joins together all ranges that overlap or are
adjacent" but does not state the postcondition: the output list is sorted, fully
merged (no two ranges overlap or adjoin), and each span has `lo ≤ hi`. Callers
who pass the output of `mergeRanges` to other functions (especially the
`Data.Range.Algebra` layer) rely on this invariant, but it is never written down.

**Recommendation:**  
Add an explicit contract section to the `mergeRanges` Haddock:

```
-- | ...
-- __Postconditions (canonical form):__
--
-- * The result contains no overlapping or adjoining ranges.
-- * Span ranges appear in ascending order of their lower bound.
-- * For each @SpanRange lo hi@, @lo <= hi@.
-- * At most one 'InfiniteRange', 'LowerBoundRange', or 'UpperBoundRange'
--   is present (and only if no @InfiniteRange@ is present).
--
-- Many functions in this library assume their inputs are in canonical form.
-- Call 'mergeRanges' before passing user-supplied ranges to set operations.
```

This turns an implicit assumption into a documented contract, reducing confusion
for new contributors and library users.

---

## 10. Provide a `Data.Range.Map` module for interval-keyed maps

**Category:** Functionality

**Current situation:**  
The library provides `KeyRange` and `SortedRange` wrappers so ranges can be used
as `Data.Map` keys, but there is no higher-level structure for the common pattern
of mapping contiguous intervals to values (e.g. IP CIDR → ASN, version range →
release notes, age bracket → discount tier).

**Recommendation:**  
Add a `Data.Range.Map` module providing a `RangeMap k v` type backed by
`Data.Map.Strict (KeyRange k) v` (or a sorted array of `(Range k, v)` pairs for
read-heavy maps). Expose at minimum:

```haskell
fromList     :: Ord k => [(Range k, v)] -> RangeMap k v
lookup       :: Ord k => k -> RangeMap k v -> Maybe v
toAscList    :: RangeMap k v -> [(Range k, v)]
overlapping  :: Ord k => Range k -> RangeMap k v -> [(Range k, v)]
```

`lookup` can use binary search on the sorted structure (benefiting from
recommendation #2). This fills a common use-case gap and complements the existing
`Data.Ranges` `Monoid`-based API without duplicating its semantics.
