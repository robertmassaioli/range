# Performance Analysis: aboveRanges and belowRanges

## Current implementation

```haskell
aboveRanges :: Ord a => Ranges a -> a -> Bool
aboveRanges r a = all (`aboveRange` a) (unRanges r)

belowRanges :: Ord a => Ranges a -> a -> Bool
belowRanges r a = all (`belowRange` a) (unRanges r)
```

Both iterate the entire `unRanges` list and apply a per-`Range` check to every element.

---

## Why this is suboptimal

### The canonical list layout

`exportRangeMerge` always produces the list in this order:

```
[ UpperBoundRange? , SpanRange₁ , SpanRange₂ , … , SpanRangeₙ , LowerBoundRange? ]
```

- `UpperBoundRange` (extends to −∞) is always **first** if present.
- `LowerBoundRange` (extends to +∞) is always **last** if present.
- Span ranges are sorted in ascending order and are non-overlapping.
- `IRM` (infinite) produces `[InfiniteRange]`.

Because the list is sorted, the **first element has the smallest lower bound** and the
**last element has the largest upper bound**.

### `belowRanges`: answer is determined by the first element alone

`belowRanges r a = True` means `a` is strictly less than the lower bound of every range.

The first element of the canonical list has the smallest lower bound. By the sorted,
non-overlapping invariant, if `a` is below the first element it is automatically below
all subsequent elements. Conversely:

- `UpperBoundRange` first → `belowRange (UpperBoundRange _) _ = False` always (extends to
  −∞; nothing can be below it).
- `InfiniteRange` → False.
- Empty list → True (vacuously).

**Current behaviour:**
- False case: O(1) — `all` short-circuits immediately on `UpperBoundRange` or on the first
  span that `a` is not below. ✓
- True case: O(n) comparisons — checks every single span even though only the first matters. ✗

### `aboveRanges`: answer is determined by the last element alone

`aboveRanges r a = True` means `a` is strictly greater than the upper bound of every range.

The last element of the canonical list has the largest upper bound. If `a` is above it,
`a` is above everything. Conversely:

- `LowerBoundRange` last → `aboveRange (LowerBoundRange _) _ = False` always (extends to
  +∞; nothing can be above it).
- `InfiniteRange` → False.
- Empty list → True (vacuously).

**Current behaviour:**
- False case (LowerBoundRange present): O(n) comparisons — `all` must walk to the last
  element before short-circuiting. ✗
- True case: O(n) comparisons — checks every span. ✗

Both cases are worse than necessary. The entire list is traversed with a comparison at
each step even though only one comparison is needed.

---

## Options

### Option A: Keep as-is

Leave both implementations unchanged.

**Pros:** Simple, correct, no risk.

**Cons:** O(n) comparisons in the True case for both functions, and O(n) comparisons
before reaching the decisive last element for `aboveRanges`'s False case. For large
range sets and/or expensive comparison types, these are unnecessary.

---

### Option B: Structural optimization — single element check

Use the canonical list structure directly. Both functions reduce to a single element
access plus one comparison.

```haskell
aboveRanges :: Ord a => Ranges a -> a -> Bool
aboveRanges r a = case unRanges r of
  [] -> True
  rs -> aboveRange (last rs) a

belowRanges :: Ord a => Ranges a -> a -> Bool
belowRanges r a = case unRanges r of
  [] -> True
  (x:_) -> belowRange x a
```

**`belowRanges` complexity:** O(1) — `head` is O(1) for a list; one comparison.

**`aboveRanges` complexity:** O(n) list traversal (for `last`) + O(1) comparisons.
List traversal is the same cost as the current `all`, but the n−1 redundant comparisons
are eliminated. For types where `Ord` comparison is expensive (e.g. multi-field version
structs, long strings), this is a meaningful saving.

**Pros:** No change to the `Ranges` data structure; correct by the canonical-order
invariant documented above; `belowRanges` improves from O(n) → O(1).

**Cons:** `aboveRanges` still pays O(n) for list traversal; the `last` call is a code
smell since `last` on a list is partial and O(n).

---

### Option C: Cache the decisive bounds in `Ranges` (recommended)

Store the two bounds that `aboveRanges` and `belowRanges` need directly in the `Ranges`
struct, built once at construction time from the `RangeMerge`.

```haskell
data Ranges a = Ranges
  { unRanges      :: [Range a]
  , _rangesQuery  :: a -> Bool      -- O(log n) membership predicate
  , _aboveBound   :: Maybe (Bound a) -- highest upper bound; Nothing if LowerBoundRange/IRM present
  , _belowBound   :: Maybe (Bound a) -- lowest lower bound; Nothing if UpperBoundRange/IRM present
  }
```

Built in `mkRanges` from the `RangeMerge`:

```haskell
-- From RangeMerge:
--   aboveBound = Nothing               if IRM or largestLowerBound present
--              = Nothing               if spans empty and no upper bound
--              = Just (snd (last spans)) if spans non-empty
--              = Just largestUpperBound  if only UpperBoundRange present

-- belowBound = Nothing               if IRM or largestUpperBound present
--            = Nothing               if spans empty and no lower bound
--            = Just (fst (head spans)) if spans non-empty
--            = Just largestLowerBound  if only LowerBoundRange present
```

Then:

```haskell
aboveRanges :: Ord a => Ranges a -> a -> Bool
aboveRanges r a = case _aboveBound r of
  Nothing -> False   -- IRM, or a LowerBoundRange is present
  Just b  -> Separate == againstUpperBound (Bound a Inclusive) b

belowRanges :: Ord a => Ranges a -> a -> Bool
belowRanges r a = case _belowBound r of
  Nothing -> False   -- IRM, or an UpperBoundRange is present
  Just b  -> Separate == againstLowerBound (Bound a Inclusive) b
```

**Complexity:** O(1) — single field access, one comparison.

**Pros:** Maximally efficient; consistent with how `inRanges` works (build once, query
many times); no list traversal at query time; correct for the empty-set case.

**Cons:** Two extra fields in `Ranges`; `mkRanges` does a small amount of extra work;
`Eq`, `NFData`, and `Show` instances are unaffected (they already ignore function fields);
the fields need to be kept in sync if `Ranges` is ever constructed outside `mkRanges`
(which it isn't — `mkRanges` is the only constructor path).

---

## Benchmark evidence

The existing benchmarks test the True case (value outside all ranges):

```
aboveRanges/disjoint-spans
  10:   whnf (aboveRanges ms10)   10000   -- ms10 covers [0,1],[3,4],...
  100:  whnf (aboveRanges ms100)  10000
  1000: whnf (aboveRanges ms1000) 10000   -- ms1000 upper bound is 2998; 10000 > 2998
belowRanges/disjoint-spans
  10:   whnf (belowRanges ms10)   (-1)
  100:  whnf (belowRanges ms100)  (-1)
  1000: whnf (belowRanges ms1000) (-1)    -- ms1000 lower bound is 0; -1 < 0
```

These hit the O(n) path in the current implementation. Option C would make all six
benchmarks O(1).

---

## Recommendation

**Implement Option C.**

The pattern is identical to how `inRanges` achieves O(log n) via `_rangesQuery`: pay a
small construction cost once, eliminate all per-query traversal. `aboveRanges` and
`belowRanges` are less frequently called than `inRanges`, but the fix is small, clean,
and consistent with the library's existing design philosophy.

Option B is acceptable if adding fields to `Ranges` is undesirable, but it leaves
`aboveRanges` doing unnecessary list traversal and uses `last`, which is partial and
visually confusing.
