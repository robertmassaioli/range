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

Implementation plan: see `ai-planning/arbitrary-exclusive-bounds-proposal.md`.

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

## 9. No `Ord` instance for `Range` **[DONE]**

`Range a` has `Eq` and `Show` but no `Ord`, `NFData`, or `Hashable` instances. `Ord` is the most consequential missing one — users who want to store ranges in `Set` or as `Map` keys, or sort a list of ranges for display, currently can't without defining orphan instances themselves. A derived or manual `Ord` would be a non-breaking addition.

`NFData` was added as part of item 3 (benchmark suite). `Hashable` remains unimplemented.

Implemented in `Data/Range/Ord.hs` as two newtypes exported from `Data.Range.Ord`: `KeyRange` (structural ordering for `Map`/`Set` keys) and `SortedRange` (positional ordering by number line location). `Range` itself has no `Ord` instance. 22 tests added in `Test/RangeOrd.hs`. Bumped to v0.3.2.0.

### Implementation

Both orderings are exposed as newtypes so every use site is explicit about which ordering it intends. `Range` itself **never gets an `Ord` instance** — not even internally.

#### Structural ordering via `ByConstructor`

`BoundType` and `Bound a` gain `Ord` (they are small supporting types where a structural order is unambiguous). `Range a` does not. `ByConstructor` is given a manual `Ord` instance:

```haskell
-- BoundType: Inclusive < Exclusive
data BoundType = Inclusive | Exclusive
   deriving (Eq, Ord, Show, Generic)

-- Bound a: compare by value first, then by boundType
data Bound a = Bound { boundValue :: a, boundType :: BoundType }
   deriving (Eq, Ord, Show, Generic)

-- Range a: no Ord instance
data Range a = SingletonRange a | SpanRange (Bound a) (Bound a) | ...
   deriving (Eq, Generic)
```

```haskell
-- In Data.Range.Ord (new module)
newtype KeyRange a = KeyRange { unKeyRange :: Range a }
   deriving Eq

-- Constructor rank: SingletonRange=0, SpanRange=1, LowerBoundRange=2,
--                   UpperBoundRange=3, InfiniteRange=4
constructorRank :: Range a -> Int
constructorRank (SingletonRange _)  = 0
constructorRank (SpanRange _ _)     = 1
constructorRank (LowerBoundRange _) = 2
constructorRank (UpperBoundRange _) = 3
constructorRank InfiniteRange       = 4

instance Ord a => Ord (KeyRange a) where
  compare (KeyRange x) (KeyRange y) =
    case compare (constructorRank x) (constructorRank y) of
      EQ -> compareFields x y
      r  -> r

compareFields :: Ord a => Range a -> Range a -> Ordering
compareFields (SingletonRange a)  (SingletonRange b)  = compare a b
compareFields (SpanRange lo1 hi1) (SpanRange lo2 hi2) = compare lo1 lo2 <> compare hi1 hi2
compareFields (LowerBoundRange a) (LowerBoundRange b) = compare a b
compareFields (UpperBoundRange a) (UpperBoundRange b) = compare a b
compareFields InfiniteRange       InfiniteRange       = EQ
compareFields _                   _                   = EQ  -- rank mismatch handled above
```

**This ordering is not semantically meaningful** — `SingletonRange 5` and `SpanRange (Bound 5 Inclusive) (Bound 5 Inclusive)` are not equal under it, just as they are not equal under the existing derived `Eq`. It is only appropriate where any consistent total order will do (deduplication, `Map` keys).

#### Positional ordering via `SortedRange`

For sorting ranges by where they sit on the number line, a `newtype` wrapper signals intent explicitly. The design uses an extended bound type to represent -∞ and +∞:

```haskell
-- In Data.Range.Ord
data ExtBound a = NegInfinity | FiniteBound (Bound a) | PosInfinity
   deriving (Eq)

-- NegInfinity < FiniteBound _ < PosInfinity
-- Within FiniteBound, use compareLower/compareHigher from Util as appropriate

newtype SortedRange a = SortedRange { unSortedRange :: Range a }

lowerExtBound :: Range a -> ExtBound a
lowerExtBound (UpperBoundRange _) = NegInfinity
lowerExtBound InfiniteRange       = NegInfinity
lowerExtBound (LowerBoundRange b) = FiniteBound b
lowerExtBound (SpanRange lo _)    = FiniteBound lo
lowerExtBound (SingletonRange x)  = FiniteBound (Bound x Inclusive)

upperExtBound :: Range a -> ExtBound a
upperExtBound (LowerBoundRange _) = PosInfinity
upperExtBound InfiniteRange       = PosInfinity
upperExtBound (UpperBoundRange b) = FiniteBound b
upperExtBound (SpanRange _ hi)    = FiniteBound hi
upperExtBound (SingletonRange x)  = FiniteBound (Bound x Inclusive)

instance Ord a => Ord (SortedRange a) where
  compare (SortedRange a) (SortedRange b) =
    case compareExtBound compareLower (lowerExtBound a) (lowerExtBound b) of
      EQ -> compareExtBound compareHigher (upperExtBound a) (upperExtBound b)
      x  -> x
```

The asymmetry in `Bound` comparison is already handled by `compareLower` and `compareHigher` in `Data.Range.Util`: for lower bounds `Inclusive 5` comes before `Exclusive 5` (i.e. `[5,` starts earlier than `(5,`), and for upper bounds `Exclusive 5` comes before `Inclusive 5` (i.e. `,5)` ends earlier than `,5]`).

Having both orderings as newtypes makes the intent explicit at every use site — neither is a "default" that could be misapplied accidentally. Both are exported from a new `Data.Range.Ord` module.

### Example use cases

**Deduplicating a collection of ranges.** Uses `KeyRange`. A user collecting ranges from multiple sources who wants to remove exact duplicates before merging:

```haskell
import Data.Range.Ord (KeyRange(..))
import Data.Set (Set)
import qualified Data.Set as Set

uniqueRanges :: Ord a => [Range a] -> [Range a]
uniqueRanges = map unKeyRange . Set.toList . Set.fromList . map KeyRange
```

Note: this deduplicates structurally identical ranges (`SingletonRange 5` and `SpanRange (Bound 5 Inclusive) (Bound 5 Inclusive)` would both survive as they are not structurally equal). For semantic deduplication, use `mergeRanges` instead.

**Using a range as a Map key.** Uses `KeyRange`. A user building a rule engine who wants to associate metadata with each distinct range:

```haskell
import Data.Range.Ord (KeyRange(..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

type RuleMap = Map (KeyRange Integer) String

rules :: RuleMap
rules = Map.fromList
  [ (KeyRange (1 +=+ 10),  "low")
  , (KeyRange (11 +=+ 50), "medium")
  , (KeyRange (lbi 51),    "high")
  ]

lookupRule :: Range Integer -> RuleMap -> Maybe String
lookupRule r m = Map.lookup (KeyRange r) m
```

**Sorting ranges by position for display.** Uses `SortedRange`. After `mergeRanges` the output is in canonical internal order, but a user wanting to display ranges sorted by their position on the number line (e.g. upper-bounded ranges first, then spans, then lower-bounded):

```haskell
import Data.Range.Ord (SortedRange(..))
import Data.List (sortOn)

displayRanges :: Ord a => [Range a] -> [Range a]
displayRanges = sortOn SortedRange
```

This produces an intuitively ordered result like `[ube 0, 1 +=+ 5, lbi 10]` rather than the structural order which would place `UpperBoundRange` after `SpanRange` by constructor position.

## 10. `Data.Range.Parser` has no tests **[DONE]**

The parser module has zero test coverage. It's a real user-facing input surface (explicitly intended for CLI programs) with at least one known edge case (negative numbers, see #4). A small HUnit or QuickCheck test group covering: round-trip `show`/`parse` for valid inputs, `parseRanges` on the examples from the module Haddock, and a few known-invalid inputs, would meaningfully improve confidence.

Implemented in `Test/RangeParser.hs` with 13 tests covering: the Haddock example, singletons, spans, lower/upper bounds, wildcards, unions, custom parser args, and edge cases. Also documented that the parser accepts non-range input as an empty list (a known limitation of the `sepBy` design).
