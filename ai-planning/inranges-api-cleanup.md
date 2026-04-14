# Proposal: `inRanges` API Cleanup and `Ranges` Map Caching

## Problems

Two related issues introduced by the binary-search implementation:

1. **`inRangesPrebuilt` is unnecessary API surface.** It exists solely to allow
   callers to pre-build the `Map` once and reuse it. But Haskell's evaluation
   model already provides this via partial application — `inRangesPrebuilt` is
   a redundant function that adds to the public API for no reason.

2. **`Data.Ranges.inRanges` rebuilds the `RangeMerge` on every call.** The
   `Ranges` newtype wraps a canonical `[Range a]`, but `inRanges (Ranges xs) =
   R.inRanges xs` calls through to `Data.Range.inRanges`, which calls
   `loadRanges` on every invocation. The canonical form is already established
   at construction time (every `Semigroup`/`Monoid` operation calls
   `mergeRanges`), so re-canonicalising on lookup is pure waste.

---

## Fix 1 — Remove `inRangesPrebuilt`, use partial application

### Why `inRangesPrebuilt` is redundant

Haskell is a lazy language with sharing. The current `inRanges` implementation
is:

```haskell
inRanges :: Ord a => [Range a] -> a -> Bool
inRanges rs val =
  let v = Bound val Inclusive
  in case loadRanges rs of
       IRM -> True
       RM lb ub spans ->
         maybe False (\b -> Overlap == againstUpperBound v b) ub ||
         maybe False (\b -> Overlap == againstLowerBound v b) lb ||
         any (\s -> boundCmp v s == EQ) spans
```

Because `rs` and `val` are both parameters, GHC treats the whole body as a
two-argument function. Every call to `inRanges rs val` re-executes
`loadRanges rs`.

If the implementation is refactored to consume `rs` in the outer lambda and
return a closure:

```haskell
inRanges :: Ord a => [Range a] -> a -> Bool
inRanges rs =
  case loadRanges rs of
    IRM -> const True
    RM lb ub spans ->
      \val ->
        let v = Bound val Inclusive
        in maybe False (\b -> Overlap == againstUpperBound v b) ub ||
           maybe False (\b -> Overlap == againstLowerBound v b) lb ||
           buildSpanQuery lb ub spans val
```

Now `loadRanges rs` and `buildSpanQuery lb ub spans` (which builds the `Map`)
are evaluated exactly once when the partial application `inRanges rs` is forced.
Every subsequent call with a different `val` hits only the O(log n) `Map`
lookup.

This means:

```haskell
-- Without fix: loadRanges + Map.fromList on EVERY call
filter (inRanges myRanges) largeList

-- After fix: loadRanges + Map.fromList ONCE; each filter step is O(log n)
filter (inRanges myRanges) largeList
```

The type signature `[Range a] -> a -> Bool` is identical before and after —
this is a **non-breaking change**. Callers who already write `inRanges rs val`
continue to work; the only difference is performance for callers who partially
apply `inRanges rs`.

### `inRangesPrebuilt` removal

Once `inRanges` is one-argument, `inRangesPrebuilt` is strictly identical to
`inRanges` in behaviour:

```haskell
inRangesPrebuilt rs == inRanges rs   -- for all rs
```

Remove `inRangesPrebuilt` from `Data/Range.hs` and from the export list. Any
user currently writing `let f = inRangesPrebuilt rs` migrates trivially to
`let f = inRanges rs`.

**Note:** This is a breaking change to the public API (removing an exported
name), so it should be accompanied by a version bump per PVP. However, since
`inRangesPrebuilt` was only introduced in the same development cycle and has
not been released in a stable version, the breakage surface is zero in practice.

### Updated `inRanges` documentation

The Haddock block for `inRanges` should explain the partial-application
performance contract:

```haskell
-- | Returns 'True' if the value falls within any of the given ranges.
--
-- The range list is canonicalised and a 'Data.Map'-backed lookup structure is
-- built when this function is partially applied to its range argument. This
-- means that when testing multiple values against the same set of ranges,
-- partial application amortises the setup cost:
--
-- @
-- -- Efficient: map is built once
-- let memberOf = inRanges myRanges
-- filter memberOf largeList
--
-- -- Also fine for one-off checks
-- inRanges myRanges someValue
-- @
--
-- The first argument does not need to be in merged/canonical form; the
-- function canonicalises it internally. If the input is already canonical
-- (e.g. the result of 'mergeRanges'), canonicalisation is a no-op.
--
-- >>> inRanges [1 +=+ 10, 20 +=+ 30] (5 :: Integer)
-- True
-- >>> inRanges [1 +=+ 10, 20 +=+ 30] (15 :: Integer)
-- False
-- >>> inRanges [] (0 :: Integer)
-- False
--
-- See also 'inRange' for testing against a single range.
```

---

## Fix 2 — Cache the `Map` inside `Ranges`

### Current situation

`Ranges` is a newtype over `[R.Range a]`. Its `inRanges` delegates to
`R.inRanges`, which calls `loadRanges` on the underlying list. After Fix 1,
`R.inRanges` will build the `Map` on partial application — but since
`Data.Ranges.inRanges` is:

```haskell
inRanges (Ranges xs) = R.inRanges xs
```

…each call to `inRanges someRanges` pattern-matches on the `Ranges` constructor,
extracts `xs`, and partially-applies `R.inRanges` to `xs`. That creates a fresh
closure each time, re-running `loadRanges xs` and `Map.fromList` for every call.
The sharing that Fix 1 provides for `[Range a]` callers does not carry over to
`Ranges` callers.

### Proposed `Ranges` change

Store the pre-built query function alongside the canonical list:

```haskell
data Ranges a = Ranges
  { unRanges :: [R.Range a]
  , _rangesQuery :: a -> Bool   -- cached O(log n) predicate; not exported
  }
```

**Alternatively**, since `Ranges` already guarantees canonical form at
construction, store the `RangeMerge` directly:

```haskell
import Data.Range.RangeInternal (RangeMerge, loadRanges, buildSpanQuery, IRM, RM(..))

data Ranges a = Ranges
  { unRanges  :: [R.Range a]
  , _rangesRM :: RangeMerge a   -- ^ internal; not exported
  }
```

And derive the predicate lazily from `_rangesRM` on demand.

The simplest correct approach is to store the predicate function directly,
built once at construction time:

```haskell
mkRanges :: Ord a => [R.Range a] -> Ranges a
mkRanges xs = Ranges xs (R.inRanges xs)

inRanges :: Ranges a -> a -> Bool
inRanges = _rangesQuery
```

Every smart constructor (`(+=+)`, `lbi`, `mconcat`, `<>`, etc.) goes through
`mkRanges`, so `_rangesQuery` is always fresh.

### Constructor discipline

The key requirement is that every path that produces a `Ranges` value calls
`mkRanges`. The current constructors that need updating:

| Constructor | Change |
|-------------|--------|
| `(+=+) a b` | `mkRanges [R.+=+ a b]` |
| `lbi`, `lbe`, `ubi`, `ube`, `inf` | `mkRanges [R.lbi x]`, etc. |
| `Semigroup (<>)` | `mkRanges (R.mergeRanges (a ++ b))` |
| `Monoid mconcat` | `mkRanges (R.mergeRanges (concatMap unRanges xs))` |
| `Functor fmap` | `mkRanges (fmap (fmap f) xs)` |
| `union`, `intersection`, `difference`, `invert`, `joinRanges` | `mkRanges result` |

**Breaking change note:** The `Ranges(..)` export currently exposes the record
field `unRanges`, which is fine and should stay. But the constructor `Ranges`
itself is exported via `Ranges(..)`. Once `Ranges` becomes a `data` type with
two fields, any code constructing `Ranges xs` directly (without `mkRanges`)
would break. This can be avoided by:

- Keeping `Ranges` as a `newtype` and instead using the cached-predicate trick
  via a top-level `IORef` / `unsafePerformIO` (inadvisable — impure)
- Exporting only `Ranges` (the type) and `unRanges` (the accessor), not the
  constructor — callers who construct `Ranges xs` directly should use
  `mkRanges xs` or `R.mergeRanges` + `Ranges`
- Accepting the minor breakage as a performance improvement and noting it in
  the changelog

The cleanest choice is to **not export the `Ranges` constructor** (change the
export from `Ranges(..)` to just `Ranges` for the type plus explicit `unRanges`
accessor). This is a minor PVP breaking change but makes the API safer — direct
construction bypasses `mergeRanges` and produces inconsistent internal state.

### After the change

```haskell
-- O(log n), map built once when 'Ranges' was constructed
inRanges :: Ranges a -> a -> Bool
inRanges r = _rangesQuery r

-- Same pattern as Fix 1 — partial application is natural
let p = inRanges myRanges    -- O(1): just reads the cached predicate
filter p largeList            -- each element O(log n)
```

---

## Summary of changes

| Change | Breaking? | Files |
|--------|-----------|-------|
| Refactor `inRanges` to one-arg form | No | `Data/Range.hs` |
| Remove `inRangesPrebuilt` | Yes (minor — new in this cycle) | `Data/Range.hs` |
| Update `inRanges` Haddock | No | `Data/Range.hs` |
| `Ranges` caches predicate via `mkRanges` | Minor (constructor export) | `Data/Ranges.hs` |
| Remove `Ranges` constructor from exports | Minor | `Data/Ranges.hs` |
| Remove `inRangesPrebuilt` benchmark | No | `Bench/Range.hs` |

PVP version bump required (removing exported names): increment the second
component (`0.3.2.1` → `0.3.3.0`).
