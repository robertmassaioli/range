# Warning Cleanup Proposal

`stack clean && stack build` produces **8 warnings** across two files:
`Data/Range/RangeInternal.hs` and `Data/Ranges.hs`.

They fall into three categories.

---

## Category 1: `-Wincomplete-record-updates` (5 warnings, RangeInternal.hs)

**GHC diagnostic code: GHC-62161**

### Cause

`RangeMerge a` has two constructors — `IRM` and `RM { ... }`. Record update
syntax (`someValue { field = x }`) is partial: it would throw a runtime error
if `someValue` were `IRM`. GHC warns because it cannot statically rule that
out.

### Instances

**Lines 37–42 — `storeRange`**

```haskell
storeRange (LowerBoundRange lower) = emptyRangeMerge { largestLowerBound = Just lower }
storeRange (UpperBoundRange upper) = emptyRangeMerge { largestUpperBound = Just upper }
storeRange (SpanRange ...) | otherwise = emptyRangeMerge { spanRanges = [...] }
storeRange (SingletonRange x)          = emptyRangeMerge { spanRanges = [...] }
```

`emptyRangeMerge = RM Nothing Nothing []`, so the updates are always safe. But
the record-update notation obscures this: the reader and GHC both have to trace
through the definition to see it.

**Fix:** Use record *construction* syntax (not record *update* syntax). The
warning is specific to `existingValue { field = x }` — constructing a fresh
`RM` with named fields (`RM { f1 = x, f2 = y, f3 = z }`) requires all fields
to be listed and never triggers the warning:

```haskell
storeRange (LowerBoundRange lower) =
  RM { largestLowerBound = Just lower, largestUpperBound = Nothing, spanRanges = [] }
storeRange (UpperBoundRange upper) =
  RM { largestLowerBound = Nothing, largestUpperBound = Just upper, spanRanges = [] }
storeRange (SpanRange x@(Bound xv xt) y@(Bound yv yt))
  | xv == yv && pointJoinType xt yt == Separate = emptyRangeMerge
  | otherwise =
      RM { largestLowerBound = Nothing, largestUpperBound = Nothing
         , spanRanges = [(minBounds x y, maxBounds x y)] }
storeRange (SingletonRange x) =
  RM { largestLowerBound = Nothing, largestUpperBound = Nothing
     , spanRanges = [(Bound x Inclusive, Bound x Inclusive)] }
```

Note: `emptyRangeMerge` can be kept as-is since it is a construction
expression itself (`RM Nothing Nothing []`), not a record update.

A builder-helper approach (e.g. `rmLower`, `rmUpper`, `rmSpans`) does not
help here: any helper that uses record update syntax internally just moves
the warning to the helper's definition site. The only warning-free path with
named fields is the full `RM { ... }` construction form shown above.

---

**Line 144 — `unionRangeMerges`, `filterTwo`**

```haskell
filterTwo = foldr filterUpperBound (filterOne { spanRanges = [] }) (spanRanges filterOne)
```

`filterOne` is `foldr filterLowerBound boundedRM (unionSpans sortedSpans)`.
`boundedRM` is always `RM { ... }` and the non-IRM branches of `filterLowerBound`
return `RM` values, so `filterOne` is always `RM` at runtime. GHC still warns
because the type is `RangeMerge a`.

**Fix:** Replace the record update with an explicit reset helper:

```haskell
-- Add this helper at the top of the where block:
withNoSpans :: RangeMerge a -> RangeMerge a
withNoSpans IRM      = IRM   -- impossible path, but exhaustive
withNoSpans rm       = rm { spanRanges = [] }

filterTwo = foldr filterUpperBound (withNoSpans filterOne) (spanRanges filterOne)
```

Or, more directly, avoid mutating `filterOne` by destructuring it:

```haskell
filterTwo = case filterOne of
  IRM              -> IRM   -- unreachable but exhaustive
  rm               -> foldr filterUpperBound (rm { spanRanges = [] }) (spanRanges rm)
```

The `case` form is preferred because it keeps the logic local without adding
a new name.

---

## Category 2: `-Wx-partial` (3 warnings)

**GHC diagnostic code: GHC-63394**

These warn on `head` and `tail`, which throw on empty lists.

### Instance A — `head` in `invertRM` (RangeInternal.hs:205)

```haskell
invertRM rm = RM { ... }
  where
    newLowerValue = invertBound . snd . last . spanRanges $ rm
    newUpperValue = invertBound . fst . head . spanRanges $ rm
```

The catch-all `invertRM rm` branch is only reached when all the explicit
patterns (which handle all forms with an empty `spanRanges`) have already
failed. By exhaustion, `spanRanges rm` is non-empty here. GHC cannot infer
this.

**Fix:** Destructure `spanRanges rm` explicitly in the pattern:

```haskell
invertRM (RM lb ub spans@((firstLo, _) : _)) = RM
  { largestUpperBound = newUpperBound
  , largestLowerBound = newLowerBound
  , spanRanges        = upperSpan ++ betweenSpans ++ lowerSpan
  }
  where
    newUpperValue = invertBound firstLo
    newLowerValue = invertBound . snd . last $ spans
    ...
```

The non-empty guard is now enforced by the pattern itself, making both `head`
and `last` replaceable with direct destructuring / `last` on `spans`.
`last spans` still fires a `-Wx-partial` warning on `last` though — use
`Data.List.NonEmpty` or `foldr const (head spans) (tail spans)` style patterns
if you want it fully clean. The simplest clean form given the current structure
is:

```haskell
invertRM (RM lb ub spans) = RM
  { ... }
  where
    (firstLo, _) = head spans   -- now justified by the pattern excluding []
    ...
```

But GHC still warns on `head`. The cleanest path is to extract `firstLo` and
`lastHi` via explicit pattern and `last`:

```haskell
invertRM (RM lb ub spans@(firstSpan : _)) = RM { ... }
  where
    newUpperValue = invertBound (fst firstSpan)
    newLowerValue = invertBound (snd (last spans))
```

This removes the `head` warning entirely by naming `firstSpan` in the pattern.
`last spans` is still technically partial, but it is safe because `spans` is
non-empty (it matched `firstSpan : _`). Suppressing the `last` warning can be
done with the same pattern trick by `Data.List.NonEmpty` or with a local
`lastSpan` extracted via `foldl1 (const id) spans` if you want zero partials.

The pragmatic recommendation: use the `firstSpan :_` pattern for `head` and
accept the `last` warning, or suppress it file-locally with
`{-# OPTIONS_GHC -Wno-x-partial #-}` for this module only after reviewing
both call sites carefully.

---

### Instance B — `tail` in `fromRanges` (Data/Ranges.hs:469)

```haskell
fromRange InfiniteRange =
  zero : takeEvenly [tail (iterate succ zero), tail (iterate pred zero)]
  where zero = toEnum 0
```

`iterate` always returns an infinite list, so `tail` is safe. GHC doesn't know
this.

**Fix:** Replace `tail (iterate f x)` with `iterate f (f x)`, which is
semantically identical and avoids `tail` entirely:

```haskell
fromRange InfiniteRange =
  zero : takeEvenly [iterate succ (succ zero), iterate pred (pred zero)]
  where zero = toEnum 0
```

This is the cleanest fix: no partial functions, no suppressions, same result.

---

## Category 3: Safe Haskell rule ignored (1 warning, RangeInternal.hs:65)

**GHC diagnostic code: GHC-56147**

```haskell
{-# RULES "load/export" [1] forall x. loadRanges (exportRangeMerge x) = x #-}
```

`Data/Range/RangeInternal.hs` is compiled with `{-# LANGUAGE Safe #-}`. Safe
Haskell disables user-defined `RULES` pragmas entirely (they could be used to
circumvent safety invariants). The rule has never fired since the module was
marked `Safe`.

**Fix:** Delete the `RULES` pragma. It is dead code. If the optimisation is
ever needed, the correct path is to mark the module `{-# LANGUAGE Trustworthy #-}`
(after auditing it for actual safety) rather than re-adding a rule that Safe
Haskell will always suppress.

---

## Summary table

| # | File | Lines | Category | Diagnostic | Fix |
|---|------|-------|----------|------------|-----|
| 4 | `Data/Range/RangeInternal.hs` | 37, 38, 41, 42 | Incomplete record update | GHC-62161 | Use `RM` constructor directly in `storeRange` |
| 1 | `Data/Range/RangeInternal.hs` | 144 | Incomplete record update | GHC-62161 | Use `case filterOne of` in `unionRangeMerges` |
| 1 | `Data/Range/RangeInternal.hs` | 205 | Partial `head` | GHC-63394 | Pattern-match on `spans@(firstSpan:_)` in `invertRM` |
| 1 | `Data/Range/RangeInternal.hs` | 65 | RULES ignored (Safe HS) | GHC-56147 | Delete the `RULES` pragma |
| 2 | `Data/Ranges.hs` | 469 | Partial `tail` | GHC-63394 | Replace `tail (iterate f x)` with `iterate f (f x)` |

All 8 warnings can be eliminated with local, mechanical changes. No semantic
behaviour changes.

---

## Recommended order of changes

1. **`Data/Ranges.hs:469`** — replace `tail (iterate ...)`. Trivial, zero risk.
2. **`Data/Range/RangeInternal.hs:65`** — delete dead `RULES` pragma. Trivial.
3. **`Data/Range/RangeInternal.hs:37–42`** — rewrite `storeRange` to use `RM`
   directly. Small, mechanical; makes `storeRange` slightly more readable.
4. **`Data/Range/RangeInternal.hs:144`** — add `case filterOne of` in
   `unionRangeMerges`. Small; makes the exhaustiveness obvious.
5. **`Data/Range/RangeInternal.hs:205`** — pattern-match `spans@(firstSpan:_)`
   in `invertRM`. One line change; removes the `head` warning.
