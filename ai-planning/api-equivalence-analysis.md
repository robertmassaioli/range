# API Equivalence Analysis: Data.Range + Data.Ranges → Data.Ranges (1.0.0.0)

This document compares every function exported by the old `Data.Range` and `Data.Ranges` modules
(0.4.x, the last version before this branch) against the new unified `Data.Ranges` module
(1.0.0.0) to confirm that no valid use case is silently lost.

---

## Old export inventory

### Old `Data.Range` exports

| Symbol | Type |
|--------|------|
| `(+=+)`, `(+=*)`, `(*=+)`, `(*=*)` | `Ord a => a -> a -> Range a` |
| `lbi`, `lbe`, `ubi`, `ube` | `a -> Range a` |
| `inf` | `Range a` |
| `inRange` | `Ord a => Range a -> a -> Bool` |
| `inRanges` | `Ord a => [Range a] -> a -> Bool` |
| `aboveRange` | `Ord a => Range a -> a -> Bool` |
| `aboveRanges` | `Ord a => [Range a] -> a -> Bool` |
| `belowRange` | `Ord a => Range a -> a -> Bool` |
| `belowRanges` | `Ord a => [Range a] -> a -> Bool` |
| `rangesOverlap` | `Ord a => Range a -> Range a -> Bool` |
| `rangesAdjoin` | `Ord a => Range a -> Range a -> Bool` |
| `mergeRanges` | `Ord a => [Range a] -> [Range a]` |
| `union` | `Ord a => [Range a] -> [Range a] -> [Range a]` |
| `intersection` | `Ord a => [Range a] -> [Range a] -> [Range a]` |
| `difference` | `Ord a => [Range a] -> [Range a] -> [Range a]` |
| `invert` | `Ord a => [Range a] -> [Range a]` |
| `fromRanges` | `(Ord a, Enum a) => [Range a] -> [a]` |
| `joinRanges` | `(Ord a, Enum a) => [Range a] -> [Range a]` |
| `Bound(..)`, `BoundType(..)`, `Range(..)` | data types |

### Old `Data.Ranges` exports (additional / different)

| Symbol | Type | Note |
|--------|------|------|
| `Ranges(unRanges)` | newtype | wraps `[Range a]` + optional cached predicate |
| All operators | `Ord a => a -> a -> Ranges a` | return `Ranges a` not `Range a` |
| `inRanges` | `Ord a => Ranges a -> a -> Bool` | cached; cache dropped on `fmap` |
| `aboveRanges`, `belowRanges` | `Ord a => Ranges a -> a -> Bool` | |
| `union`, `intersection`, `difference`, `invert` | `Ord a => Ranges a -> … -> Ranges a` | |
| `fromRanges` | `(Ord a, Enum a) => Ranges a -> [a]` | |
| `joinRanges` | `(Ord a, Enum a) => Ranges a -> Ranges a` | |
| `Functor Ranges` | `fmap :: (a -> b) -> Ranges a -> Ranges b` | **removed in 1.0** |
| `Semigroup`, `Monoid` | `(<>) = union` | |

Note: old `Data.Ranges` did **not** export `inRange`, `aboveRange`, `belowRange`,
`rangesOverlap`, `rangesAdjoin`, or `mergeRanges`. Those were only in `Data.Range`.

---

## Function-by-function comparison

### Construction operators: `+=+`, `+=*`, `*=+`, `*=*`, `lbi`, `lbe`, `ubi`, `ube`, `inf`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Return type | `Range a` | `Ranges a` | `Ranges a` |

**Breaking change for `Data.Range` users.** Code that used operators where a `Range a` was
expected (e.g. as elements of a `[Range a]` list, or as an argument to `inRange`/`rangesOverlap`)
now fails to typecheck.

**Migration:** use `Range` constructors directly where a `Range a` is needed:
```haskell
-- Old
[1 +=+ 10 :: Range Integer]
inRange (1 +=+ 10) value

-- New
[SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)]
inRange (SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)) value
-- or just use inRanges:
inRanges (1 +=+ 10) value
```

No use case is lost — every `Range a` value the operators could build is still expressible via
constructors. The change makes the operators always return the primary type.

---

### `inRange :: Ord a => Range a -> a -> Bool`

**Identical.** Present in new `Data.Ranges` with the same signature. No change.

---

### `inRanges`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Signature | `[Range a] -> a -> Bool` | `Ranges a -> a -> Bool` | `Ranges a -> a -> Bool` |
| Cache | Built on first partial application | Built at construction; dropped on `fmap` | Built at construction; never dropped |

**Breaking change for `Data.Range` users.** Raw `[Range a]` lists must be wrapped with
`mergeRanges` first.

```haskell
-- Old (Data.Range)
inRanges [1 +=+ 10, 20 +=+ 30] value

-- New
inRanges (mergeRanges [SpanRange ..., SpanRange ...]) value
-- or, using the operators:
inRanges (1 +=+ 10 <> 20 +=+ 30) value
```

**Strictly better:** the new version guarantees the cache is always live; the old `Data.Range`
version built it on each new partial application, and the old `Data.Ranges` version silently
dropped it after `fmap`.

---

### `aboveRange :: Ord a => Range a -> a -> Bool`
### `belowRange :: Ord a => Range a -> a -> Bool`

**Identical.** Present in new `Data.Ranges` with the same signatures. No change.

---

### `aboveRanges`, `belowRanges`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Argument | `[Range a]` | `Ranges a` | `Ranges a` |

Same migration as `inRanges`: wrap a raw list with `mergeRanges` or build with operators.
Semantics unchanged.

---

### `rangesOverlap :: Ord a => Range a -> Range a -> Bool`
### `rangesAdjoin :: Ord a => Range a -> Range a -> Bool`

**Identical.** Present in new `Data.Ranges` with the same signatures. No change.
(Previously only in `Data.Range`; new `Data.Ranges` now exports them too — an improvement.)

---

### `mergeRanges`

| | Old `Data.Range` | New `Data.Ranges` |
|--|--|--|
| Type | `Ord a => [Range a] -> [Range a]` | `Ord a => [Range a] -> Ranges a` |

**Breaking change.** The return type is now `Ranges a` rather than `[Range a]`. Code that fed
the result directly into another `[Range a]`-expecting function breaks.

```haskell
-- Old
let rs = mergeRanges input :: [Range Integer]
inRanges rs value

-- New — flows naturally since everything now takes Ranges a
let rs = mergeRanges input :: Ranges Integer
inRanges rs value
```

No semantics are lost: `unRanges (mergeRanges xs) == old mergeRanges xs` always holds.

---

### `union`, `intersection`, `difference`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Arguments | `[Range a] -> [Range a]` | `Ranges a -> Ranges a` | `Ranges a -> Ranges a` |
| Return | `[Range a]` | `Ranges a` | `Ranges a` |

**Breaking change for `Data.Range` users.** Wrap inputs with `mergeRanges` or use the new
`Ranges`-based construction.

Semantically: `unRanges (union a b) == old union (unRanges a) (unRanges b)`. Identical results.

Note: `union a b == a <> b` (the `Semigroup` instance). No expressiveness lost.

---

### `invert`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Type | `Ord a => [Range a] -> [Range a]` | `Ord a => Ranges a -> Ranges a` | `Ord a => Ranges a -> Ranges a` |

Same migration pattern. `unRanges (invert r) == old invert (unRanges r)`. Identical results.

---

### `fromRanges`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Argument | `[Range a]` | `Ranges a` | `Ranges a` |
| Return | `[a]` | `[a]` | `[a]` |

Same migration. Results identical since the canonical list is the same.

---

### `joinRanges`

| | Old `Data.Range` | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|--|
| Type | `(Ord a, Enum a) => [Range a] -> [Range a]` | `(Ord a, Enum a) => Ranges a -> Ranges a` | `(Ord a, Enum a) => Ranges a -> Ranges a` |

Same migration. `unRanges (joinRanges r) == old joinRanges (unRanges r)`. Identical.

---

### `Bound(..)`, `BoundType(..)`, `Range(..)`

**Identical.** All constructors still exported from new `Data.Ranges`. No change.

---

### `Functor Ranges` (removed)

| | Old `Data.Ranges` | New `Data.Ranges` |
|--|--|--|
| `fmap :: (a -> b) -> Ranges a -> Ranges b` | Present | **Removed** |
| `fmap :: (a -> b) -> Range a -> Range b` | Present (via `Data.Range.Data`) | **Removed** |

This is the only removal that cannot be mechanically migrated to the new API.

#### What `fmap` was used for

The only use cases documented or found in the codebase:

1. **Shifting boundaries by a constant** (`fmap (+10)`, `fmap negate`) — changing units,
   offsetting a set of ranges.

2. **Type conversion** — mapping a parse result from one numeric type to another.

#### Why these use cases are unsafe for half-infinite ranges

`fmap negate (lbi 5)` produces `lbi (-5)` — `[−5, ∞)` — because the `LowerBoundRange`
constructor is preserved. The mathematically correct result is `ubi (-5)` — `(−∞, −5]`.
`fmap` cannot flip constructors, so any order-reversing function silently produces wrong results
for `LowerBoundRange` and `UpperBoundRange`. Finite `SpanRange` values are rescued by
`minBounds`/`maxBounds` in `storeRange`, but half-infinite ranges are not.

#### The safe replacement

Map the **query value** through the inverse function instead of mapping boundaries:

```haskell
-- Old (broken for non-monotonic f, e.g. negate on lbi):
inRanges (fmap f myRanges) query

-- New (always correct):
inRanges myRanges (inverseF query)

-- Concrete example — test a Fahrenheit value against Celsius ranges:
let safeTemp = 20 +=+ 37 :: Ranges Double   -- defined in °C
let inSafeTemp f = inRanges safeTemp ((f - 32) * 5 / 9)
```

For type conversion between two `Ord` types where the mapping is order-preserving and you only
need `SpanRange` / `SingletonRange` (no half-infinite), the constructor-level approach works:

```haskell
mapRangeOrd :: (a -> b) -> Range a -> Range b
mapRangeOrd f (SingletonRange x)  = SingletonRange (f x)
mapRangeOrd f (SpanRange lo hi)   = SpanRange (fmap f lo) (fmap f hi)
-- LowerBoundRange and UpperBoundRange omitted intentionally —
-- callers must handle them explicitly if their mapping can reverse order.
```

#### Verdict

The `fmap` use case for monotone functions on finite spans is expressible via constructors or
the query-mapping pattern. The `fmap` use case for half-infinite ranges with non-monotone
functions was **always silently wrong** in the old API. Removing `Functor` eliminates a class
of correctness bugs. No valid, correct use case is lost.

---

## New capabilities in `Data.Ranges` 1.0.0.0 not present in 0.4.x

| Addition | Notes |
|----------|-------|
| `Eq (Ranges a)` | Compare two `Ranges` values for set equality |
| `NFData (Ranges a)` | `force` / `deepseq` support for benchmarking and strict evaluation |
| `RangeAlgebra (Ranges a)` | Use `Ranges a` as the algebra leaf and output type |
| `parseRanges` returns `Ranges a` | Parser result is immediately ready for membership testing |
| `inRange`, `aboveRange`, `belowRange`, `rangesOverlap`, `rangesAdjoin` in `Data.Ranges` | Previously required importing `Data.Range` separately |

---

## Summary verdict

Every function from the old combined `Data.Range` + `Data.Ranges` API has a direct equivalent
in the new `Data.Ranges` with identical semantics. The changes are:

1. **Type changes** (all arguments/return values from `[Range a]` to `Ranges a`): purely
   mechanical migration; `unRanges`/`mergeRanges` bridge the gap where needed.

2. **Operator return type** (`Range a` → `Ranges a`): use constructors directly where a raw
   `Range a` is needed (e.g. `KeyRange`, `inRange`, `rangesOverlap`).

3. **`Functor` removed**: the only breaking removal. The use case (mapping boundaries) was
   silently incorrect for half-infinite ranges with non-monotone functions. The correct pattern
   (map the query value) is strictly safer and no less expressive.

Deprecating `Data.Range` and directing all users to `Data.Ranges` loses no valid, correct use
case.
