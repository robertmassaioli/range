# Proposal: Fix the `Functor Ranges` Problem

## Problem

`Ranges` implements `Functor`, but the instance is subtly wrong in three
independent ways.

### 1. It violates the `Functor` identity law

The identity law requires `fmap id = id`. But the current implementation:

```haskell
instance Functor Ranges where
   fmap f r = Ranges (fmap (fmap f) (unRanges r)) Nothing
```

always stores `Nothing` in `_rangesQuery`, regardless of what `f` is. That
means:

```haskell
fmap id r /= r   -- _rangesQuery goes from (Just pred) to Nothing
```

The two values are extensionally equivalent for `inRanges`, but they are not
the same value, and the discarded cache has real performance consequences.
This is a law violation — not just a quality-of-implementation issue.

### 2. It allows semantically invalid transformations without warning

The type `fmap :: (a -> b) -> Ranges a -> Ranges b` accepts any function,
including non-monotonic ones. Applying, say, `fmap negate` to `[1 +=+ 5]`
produces a span whose lower bound (`-1`) is greater than its upper bound
(`-5`). The library's internal invariants (spans sorted, lower ≤ upper) are
silently broken. The existing Haddock already warns about this, but having to
warn about a typeclass method is a sign the typeclass is the wrong fit.

### 3. The cache cannot be rebuilt after `fmap`

`Functor` carries no constraints on `b`. Rebuilding the lookup structure
requires `Ord b`, so it is impossible to call `mkRanges` (or even
`mergeRanges`) inside `fmap`. The result is a `Ranges` that has lost its O(log
n) membership guarantee for every query until the caller explicitly routes it
back through a set-operation function. This is a non-obvious footgun, as shown
by the documentation we had to add to `inRanges` to explain the workaround.

---

## Root cause

`Ranges a` is not a plain container — it is an ordered, canonical,
indexed structure. Its type parameter appears in an `Ord` constraint
everywhere: construction, merging, and querying all require `Ord a`. That is
fundamentally incompatible with `Functor`, which requires the mapping to be
constraint-free. Attempting to bridge that gap produces a leaky abstraction.

---

## Option A: Drop `Functor`, add `mapRanges` (keep the cache field)

Keep `Ranges` as a `data` type with the `_rangesQuery` cache field. Delete the
`Functor` instance and replace it with a single explicit function:

```haskell
-- | Map a function over every boundary value in every range, producing a
-- new canonical 'Ranges' with a freshly pre-built lookup structure.
--
-- The function should be monotonically non-decreasing; applying a
-- non-monotonic function (e.g. @negate@) will silently produce ranges
-- where the lower bound exceeds the upper bound.
--
-- >>> mapRanges (*2) (1 +=+ 5 :: Ranges Integer)
-- Ranges [2 +=+ 10]
mapRanges :: (Ord a, Ord b) => (a -> b) -> Ranges a -> Ranges b
mapRanges f = mkRanges . fmap (fmap f) . unRanges
```

`mkRanges` calls `mergeRanges` and pre-builds the lookup structure, so the
returned `Ranges b` is immediately O(log n) for `inRanges`. The `Ord b`
constraint makes the semantics explicit at the call site.

**Tradeoffs:**

- `mapRanges` always returns a fully-cached `Ranges` — no silent O(n) penalty
- `mapRanges` re-sorts and merges after mapping, so a non-monotonic mapping
  produces a canonical (if semantically surprising) result rather than a broken one
- The `Functor` identity law is satisfied vacuously
- `inRanges` documentation no longer needs a workaround section
- The `_rangesQuery` cache field still pays a constant per-value memory cost,
  but it is always `Just` for every value the library produces
- Breaking change — `0.5.0.0`

---

## Option B: Revert to `newtype`, rely on partial application

Revert `Ranges` to a simple `newtype` over `[Range a]`, eliminating the cache
field entirely:

```haskell
newtype Ranges a = Ranges { unRanges :: [R.Range a] }
```

`Functor` works correctly again with no law violations because there is no
hidden field to drop:

```haskell
instance Functor Ranges where
   fmap f (Ranges rs) = Ranges (fmap (fmap f) rs)
```

Performance is preserved by relying on the partial-application behaviour of
`Data.Range.inRanges`, which already pre-builds the lookup map at the point of
partial application (introduced in the `0.4.0.0` cleanup):

```haskell
inRanges :: Ord a => Ranges a -> a -> Bool
inRanges r = R.inRanges (unRanges r)
-- R.inRanges builds the Map when partially applied:
--   R.inRanges rs = case loadRanges rs of { IRM -> const True; RM lb ub spans -> buildSpanQuery lb ub spans }
```

The contract placed on the caller: **always partially apply `inRanges` when
querying the same `Ranges` more than once.** This is already idiomatic Haskell
and should be documented clearly:

```haskell
-- Good — map is built once, shared across all queries
let memberOf = inRanges myRanges
filter memberOf largeList

-- Avoid — map is rebuilt for every element
filter (inRanges myRanges) largeList  -- GHC may or may not share without -O2
```

**Tradeoffs:**

- `Functor` laws hold without qualification
- No per-value memory overhead for the cache field
- The O(log n) guarantee depends on caller discipline; it is easy to accidentally
  call `inRanges r val` in a loop without partial application and pay O(n log n)
  instead of O(n + log n), with no type-level warning
- Without `-O2`, GHC does not reliably common-subexpression-eliminate
  `inRanges myRanges` across a `filter` call, so the discipline requirement
  is load-bearing in unoptimised builds
- Non-monotonic `fmap` still silently produces ill-formed spans — this problem
  is unresolved
- Breaking change (field removed from `data` type, `_rangesQuery` gone) — `0.5.0.0`

---

## Option C: Two-type split — `Ranges` (cached) and `RangeList` (plain)

Introduce a second type that is a plain `newtype` over `[Range a]`, keeping the
existing `data Ranges a` unchanged except for removing `Functor`:

```haskell
-- Existing type: cached, indexed, no Functor
data Ranges a = Ranges { unRanges :: [R.Range a], _rangesQuery :: Maybe (a -> Bool) }

-- New type: plain list wrapper, has Functor, no cache
newtype RangeList a = RangeList { unRangeList :: [Range a] }
  deriving (Functor)

-- Convert a RangeList back into a cached Ranges
toRanges :: Ord a => RangeList a -> Ranges a
toRanges = mkRanges . unRangeList

-- Downgrade a Ranges to a RangeList for transformation pipelines
fromRanges :: Ranges a -> RangeList a
fromRanges = RangeList . unRanges
```

The mapping workflow becomes explicit about when the cache is paid for:

```haskell
-- fmap over boundaries, then re-index once
let shifted = toRanges . fmap (+1) . fromRanges $ myRanges
filter (inRanges shifted) largeList
```

`RangeList` can also implement `Semigroup`/`Monoid` via list concatenation
(without merging), giving callers a lazily-accumulated list they convert to
`Ranges` in one pass when ready.

**Tradeoffs:**

- `Functor` laws hold on `RangeList` without qualification
- `Ranges` retains its O(log n) membership guarantee unconditionally
- The type system makes the cache boundary visible — `toRanges` is the explicit
  "pay for indexing here" call
- Adds a second public type, which increases API surface and may confuse new users
  about which type to reach for
- Non-monotonic `fmap` on `RangeList` still produces an ill-formed list, but
  `toRanges` will re-sort and merge on conversion, silently correcting order
- Additive change for the new type; removing `Functor Ranges` is still a
  breaking change — `0.5.0.0`

---

## Recommendation

**Option A** is the most honest and simplest fix: the `Functor` instance was
always wrong for this type, and `mapRanges` makes the `Ord` requirement
explicit at the one place it belongs. The `_rangesQuery` cache continues to
earn its keep because `Ranges` values are typically constructed once and queried
many times.

**Option B** is a reasonable alternative if the goal is to minimise complexity.
It removes the cache field entirely and pushes the performance contract onto
callers, which is acceptable for a library whose primary audience writes
idiomatic Haskell. The unresolved non-monotonic `fmap` hazard is its main
weakness.

**Option C** is worth considering if the library wants to support
transformation pipelines (e.g. `fmap`, `traverse`, functor composition) as a
first-class use case. The cost is a larger API surface.

---

## Shared migration note

All three options are breaking changes that warrant a `0.5.0.0` version bump.
The `fmap` doctest in `Data/Ranges.hs` must be updated in all cases.

---

## Relation to other proposals

The `Functor` instance was introduced alongside the `Ranges` newtype. This
proposal supersedes the workaround documented in `inRanges` added during the
`0.4.0.0` cleanup cycle.
