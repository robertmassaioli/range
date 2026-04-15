# Proposal: Drop `Functor Ranges`, Add `mapRanges`

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

## Proposed fix

### Remove the `Functor` instance

Delete the `instance Functor Ranges` declaration entirely.

### Add `mapRanges`

Export a single replacement function:

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

`mkRanges` calls `mergeRanges` (re-sorts and de-duplicates) and pre-builds
the lookup structure, so the returned `Ranges b` is immediately O(log n) for
`inRanges`.  The `Ord b` constraint makes the semantics explicit at the call
site.

### Migration

Any code using `fmap f someRanges` becomes `mapRanges f someRanges`. Because
`Functor` is a widely assumed typeclass, removing it is a **breaking change**
and requires a major/minor PVP bump (i.e. `0.5.0.0`).

The `fmap` use in the existing doctest:

```haskell
-- >>> fmap (*2) (1 +=+ 5 :: Ranges Integer)
-- Ranges [2 +=+ 10]
```

becomes:

```haskell
-- >>> mapRanges (*2) (1 +=+ 5 :: Ranges Integer)
-- Ranges [2 +=+ 10]
```

---

## What users lose

Code that passes `Ranges` to a function expecting `Functor f => f a` (e.g.
`Data.Functor.void`, or some generic utility) will break. In practice this is
unlikely because `Ranges` carries `Ord` constraints on every meaningful
operation, so it rarely fits into generic functor pipelines. Any code doing so
was already living dangerously with the non-monotonic mapping hazard.

## What users gain

- `mapRanges` always returns a fully-cached `Ranges` — no silent O(n) penalty.
- `mapRanges` re-sorts and merges, so non-monotonic mappings produce a
  canonical (if semantically surprising) result rather than a broken one.
- The `Functor` identity law is restored (vacuously, by not having the
  instance at all).
- The `inRanges` documentation no longer needs to explain a workaround.

---

## Relation to other proposals

The `Functor` instance was introduced alongside the `Ranges` newtype. This
proposal supersedes the workaround documented in `inRanges` added during the
`0.4.0.0` cleanup cycle.
