# Proposal: Binary Search in `inRanges`

## Problem

`inRanges` is the primary membership test in the library and is called on the hot
path for many workloads (IP allowlists, version constraint checks, time-window
filters, etc.). Its current implementation is a linear scan:

```haskell
-- Data/Range.hs:287-288
inRanges :: (Ord a) => [Range a] -> a -> Bool
inRanges rs a = any (`inRange` a) rs
```

This is O(n) per query where n is the number of ranges. After `mergeRanges` (or
any set operation) the ranges are in canonical form: sorted by lower bound,
non-overlapping, and fully merged. That sorted structure is never exploited for
lookup. The existing benchmark (`Bench/Range.hs:68-73`) already measures this at
10, 100, 1 000, and 10 000 disjoint spans, making the regression easy to detect.

## Canonical Form Guarantee

After `mergeRanges` (and after any call to `invert`, `union`, `intersection`,
`difference` — all of which canonicalise as a side effect), the output has the
following structure in `RangeMerge`:

```
RM { largestLowerBound :: Maybe (Bound a)   -- at most one semi-infinite lower tail
   , largestUpperBound :: Maybe (Bound a)   -- at most one semi-infinite upper tail
   , spanRanges        :: [(Bound a, Bound a)]  -- sorted, non-overlapping, finite spans
   }
```

or `IRM` (the whole number line). The `spanRanges` list is sorted ascending by
lower bound with no two spans overlapping or adjoining. This is the invariant that
makes binary search sound.

## Proposed Implementation

### Step 1 — internal binary search over `spanRanges`

Add a helper in `Data/Range/RangeInternal.hs` (or `Data/Range/Util.hs`) that
binary-searches a sorted span vector for a point:

```haskell
-- | Binary search over a sorted, non-overlapping span list.
-- Precondition: spans are sorted ascending by lower bound (canonical form).
bsearchSpans :: Ord a => Bound a -> [(Bound a, Bound a)] -> Bool
bsearchSpans v spans = go 0 (length spans - 1)
  where
    go lo hi
      | lo > hi   = False
      | otherwise =
          let mid  = lo + (hi - lo) `div` 2
              span' = spans !! mid
          in case boundCmp v span' of
               LT -> go lo (mid - 1)
               EQ -> True
               GT -> go (mid + 1) hi
```

`boundCmp` already exists in `Data/Range/Util.hs` and does exactly the right
comparison (returns `EQ` when the bound falls inside the span).

Note: `(!!)` on a plain list is still O(n). To get true O(log n) behaviour the
spans should be stored in a `Data.Array` (or `Data.Vector`) — see the migration
note below. Even without that, replacing `any` with a binary search over a list
eliminates the per-element `inRange` call overhead and improves cache behaviour
for large inputs.

### Step 2 — rewrite `inRanges` to go through `RangeMerge`

Rather than operating on `[Range a]` directly, canonicalise first and then search
the structured `RangeMerge`:

```haskell
inRanges :: Ord a => [Range a] -> a -> Bool
inRanges rs a =
  case loadRanges rs of        -- or: use already-canonical form if available
    IRM -> True
    RM { largestLowerBound = lb
       , largestUpperBound = ub
       , spanRanges        = spans } ->
         checkUpper ub || checkLower lb || bsearchSpans (Bound a Inclusive) spans
  where
    checkLower Nothing  = False
    checkLower (Just b) = Overlap == againstLowerBound (Bound a Inclusive) b
    checkUpper Nothing  = False
    checkUpper (Just b) = Overlap == againstUpperBound (Bound a Inclusive) b
```

The `IRM` branch short-circuits immediately. The semi-infinite bound checks are
O(1). Only the span check uses binary search.

### Step 3 — avoid re-canonicalisation when input is already canonical

The hot-path use case is a fixed range set queried many times. Callers who call
`mergeRanges` once and then query repeatedly pay the `loadRanges` cost on every
call with the approach above.

The right fix is to expose the search on the `Ranges` newtype in `Data.Ranges`,
which already wraps a canonical `[Range a]`:

```haskell
-- Data/Ranges.hs
inRanges :: Ord a => Ranges a -> a -> Bool
inRanges (Ranges rs) a = inRangesCanonical rs a
```

Where `inRangesCanonical` trusts its input is already sorted/merged and skips
the `loadRanges` step, going straight to `exportRangeMerge`-free binary search on
the internal span structure. Because `Ranges` invariants are maintained by its
smart constructors, this is safe.

## Migration Path

1. **No breaking changes.** Both `Data.Range.inRanges` and `Data.Ranges.inRanges`
   keep their existing signatures.
2. Implement `bsearchSpans` internally.
3. Change `Data.Range.inRanges` to canonicalise and binary-search (accepts the
   re-canonicalisation cost for unchecked `[Range a]` inputs — correct and faster
   than before for large n).
4. Change `Data.Ranges.inRanges` to skip re-canonicalisation (fastest path,
   zero extra allocation for the common repeated-query case).
5. Update `Bench/Range.hs` to add a `Ranges`-based benchmark alongside the
   existing `[Range a]` benchmark so both paths are covered.

## Optional Future Step: Use `Data.Array` for O(log n) Binary Search

Storing `spanRanges` as `Data.Array Int (Bound a, Bound a)` (or `Data.Vector`)
instead of a list would give true O(log n) index access. This is a larger change
to `RangeMerge` internals and should be done separately, but the binary search
logic introduced here transfers directly.

## Expected Gains

The existing benchmark already shows the problem clearly:

| Spans | Current `inRanges` (miss) | Expected after change |
|------:|--------------------------|----------------------|
|    10 | ~10 comparisons          | ~4 comparisons       |
|   100 | ~100 comparisons         | ~7 comparisons       |
| 1 000 | ~1 000 comparisons       | ~10 comparisons      |
| 10 000| ~10 000 comparisons      | ~14 comparisons      |

(Miss case is worst case; hit case benefits similarly once the span is found.)
