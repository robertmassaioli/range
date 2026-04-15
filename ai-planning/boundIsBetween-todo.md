# Analysis: "TODO replace everywhere with boundsOverlapType"

A stale comment in `Data/Range/Util.hs` (line 106, now removed) read:

```haskell
-- TODO replace everywhere with boundsOverlapType
boundIsBetween :: (Ord a) => Bound a -> (Bound a, Bound a) -> OverlapType
```

This document analyses whether the replacement is correct, partially correct, or wrong.

## The two functions

```haskell
-- Point-in-span: is this single Bound within the span (lower, upper)?
boundIsBetween :: Ord a => Bound a -> (Bound a, Bound a) -> OverlapType

-- Span-vs-span: do these two spans share any values?
boundsOverlapType :: Ord a => (Bound a, Bound a) -> (Bound a, Bound a) -> OverlapType
```

`boundsOverlapType` is *built on top of* `boundIsBetween`:

```haskell
boundsOverlapType l@(ab, bb) r@(xb, yb)
   | isEmptySpan l || isEmptySpan r = Separate
   | a == x                         = Overlap
   | b == y                         = Overlap
   | otherwise = (ab `boundIsBetween` (xb, yb)) `orOverlapType` (xb `boundIsBetween` (ab, bb))
```

The dependency runs **`boundsOverlapType` → `boundIsBetween`**, not the other way around. Replacing
`boundIsBetween` with `boundsOverlapType` in its own definition would be circular.

## Where `boundIsBetween` is called outside Util

| Call site | Argument form | Note |
|---|---|---|
| `inRange (SpanRange x y) value` | `boundIsBetween (Bound value Inclusive) (x, y)` | value is always inclusive |
| `buildSpanQuery` (RangeInternal) | `boundIsBetween v (lo, hi)` where `v = Bound val Inclusive` | value is always inclusive |
| `boundCmp` (Util) | `boundIsBetween ab (xb, yb)` | `ab` may be exclusive |

## Can the inclusive-only sites be replaced?

At `inRange` and `buildSpanQuery`, the tested value is always `Bound val Inclusive`. The
degenerate-span substitution `boundsOverlapType (Bound val Inclusive, Bound val Inclusive) (x, y)`
is semantically equivalent because:

- The degenerate span `(Bound val Inclusive, Bound val Inclusive)` is never empty
  (`isEmptySpan` returns `False` for inclusive bounds with equal endpoints)
- `boundsOverlapType` then checks whether `Bound val Inclusive` is between `(x, y)`, which
  reduces to exactly what `boundIsBetween` computes

So *technically* the substitution is correct at those two sites.

## Why the replacement is still the wrong call

**1. It increases verbosity for no gain.**

```haskell
-- Current — clear intent, minimal noise
Overlap == boundIsBetween (Bound value Inclusive) (x, y)

-- After replacement — wraps a point in a redundant pair
Overlap == boundsOverlapType (Bound value Inclusive, Bound value Inclusive) (x, y)
```

The degenerate span `(v, v)` is a distraction; the reader has to reason about why two identical
bounds appear before understanding the check.

**2. It cannot replace all call sites.**

`boundCmp` calls `boundIsBetween ab (xb, yb)` where `ab` is the lower bound of a span and may be
`Exclusive`. A degenerate exclusive span `(Bound a Exclusive, Bound a Exclusive)` is empty, so
`boundsOverlapType` would immediately return `Separate` — the wrong answer.

**3. The dependency direction is already correct.**

`boundIsBetween` is the lower-level primitive. `boundsOverlapType` is the higher-level combinator
that uses it. Eliminating the lower-level primitive to force every site to use the combinator
inverts the natural abstraction hierarchy.

## Recommendation

**Close the TODO: reject the replacement.**

- Keep `boundIsBetween` as an exported function in `Data.Range.Util`.
- Remove the stale TODO comment (done in the same commit that produced this document).
- Document `boundIsBetween` as the point-in-span primitive that `boundsOverlapType` is built upon.

No code change is needed beyond removing the comment. The existing structure is correct.
