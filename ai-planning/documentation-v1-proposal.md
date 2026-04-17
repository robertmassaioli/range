# Proposal: Documentation Overhaul for v1.0.0.0

This proposal covers all documentation that needs updating to reflect the v0.3 → v1.0
breaking changes, and identifies gaps that are new to v1.0.

---

## 1. README

### Current state

The README is severely out of date. The code example imports `Data.Range.Range`, a module
that has never existed in this codebase (even v0.3 used `Data.Range`). The example uses
the pre-v0.3 API signatures and contains no mention of:

- `Data.Ranges` (the primary v1.0 module)
- The `Ranges` newtype
- The `Semigroup`/`Monoid` interface
- The `Data.Range.Algebra`, `Data.Range.Ord`, or `Data.Range.Parser` modules
- Performance characteristics of `inRanges`, `aboveRanges`, `belowRanges`
- Any migration guidance

### Required changes

1. **Fix the example import.** Change `Data.Range.Range` → `Data.Ranges`. Rewrite the
   example to use the v1.0 API: `Ranges a`, operators that produce `Ranges`, `<>` for
   combination, `inRanges` on `Ranges`.

2. **Add a features section.** Briefly describe the five exposed modules and their purpose.

3. **Update the installation section.** The Cabal command remains valid but Stack is the
   primary build tool; the section already documents it. Add a pointer to Hackage docs.

4. **Add a migration guide at the tail.** See §6 below for the full text.

---

## 2. `Data.Range` (deprecated shim)

### Current state

```haskell
-- | __Deprecated.__ Import "Data.Ranges" instead.
module Data.Range {-# DEPRECATED "Import Data.Ranges instead of Data.Range." #-}
```

The one-line doc is fine. No further changes needed here.

---

## 3. `Data.Ranges`

### Current state

The module doc and most function Haddocks are thorough — this was substantially improved
in the v1.0 branch. The following gaps remain:

| Item | Gap |
|------|-----|
| `$creation` section note | Says operators "mirror those in `Data.Range.Operators`" — an internal module reference that users cannot import directly. Replace with a brief description of the operators' semantics. |
| `fromRanges` interleaving note | The example shows `[1,10,2,11,3,12]` but does not explain *why* values interleave. A one-sentence note about `takeEvenly` behaviour (breadth-first across ranges) would prevent confusion. |
| `rangesOverlap` / `rangesAdjoin` | No cross-references between the two. A "See also" note would help. |
| `mergeRanges` doc | States it "canonicalises" but doesn't mention the already-merged invariant: once a `Ranges` value exists, passing its `unRanges` to `mergeRanges` is a no-op. |
| Missing `@since` on everything | `Data.Ranges` gained `Eq`, `NFData`, `RangeAlgebra`, `aboveRanges`/`belowRanges` O(1) guarantee, and `mergeRanges`-as-constructor in 1.0. These should carry `@since 1.0.0.0`. |
| `buildAboveQuery` / `buildBelowQuery` | Internal helpers, correctly unexported. Fine. |

### Recommended additions

```haskell
-- $creation
-- Each operator constructs a 'Ranges' covering a single range. Combine with
-- '<>' or 'mconcat'. The full operator set:
--
-- * '+=+' — @[x, y]@ inclusive on both ends
-- * '+=*' — @[x, y)@ inclusive lower, exclusive upper
-- * '*=+' — @(x, y]@ exclusive lower, inclusive upper
-- * '*=*' — @(x, y)@ exclusive on both ends
-- * 'lbi' / 'lbe' — lower-bounded: @[x, ∞)@ and @(x, ∞)@
-- * 'ubi' / 'ube' — upper-bounded: @(−∞, x]@ and @(−∞, x)@
-- * 'inf'         — the entire number line
```

Add to `fromRanges`:
```haskell
-- Note: values from multiple ranges are interleaved (breadth-first), not
-- concatenated. This ensures 'take n' samples from all ranges rather than
-- exhausting the first range before moving on.
```

---

## 4. `Data.Range.Algebra`

### Current state

Substantially improved in v1.0. Remaining gap: the predicate evaluation example uses
`fmap inRanges expr` but `inRanges` now takes `Ranges a`, so the example assumes the
expression tree holds `Ranges a` leaves — this should be made explicit in the comment.

| Item | Gap |
|------|-----|
| Predicate example | `fmap inRanges expr` requires leaves to be `Ranges a`; a reader coming from v0.3 expecting `[Range a]` leaves will be confused. |
| `Algebra` type alias | No haddock comment explaining it is a free-monad catamorphism type alias. Users who need to implement `RangeAlgebra` will want a pointer. |

### Recommended addition

Update the predicate example comment:
```haskell
-- Note: 'fmap inRanges' requires the leaf type to be 'Ranges a'.
-- Build the tree with 'Ranges'-producing operators or use 'A.const' with a
-- 'Ranges' value:
--
--   let expr = A.union (A.const (1 +=+ 10)) (A.const (20 +=+ 30))
--                :: A.RangeExpr (Ranges Integer)
--   A.eval (fmap inRanges expr) 25  -- True
```

---

## 5. `Data.Range.Parser`

### Current state

Well-documented in v1.0 — known limitations are called out, examples are present, the
`ParseError` re-export is explained. One gap:

| Item | Gap |
|------|-----|
| `@since` on the `Ranges`-returning API | `parseRanges` returning `Ranges a` is a v1.0 change; old v0.3 returned `[Range a]`. Should carry `@since 1.0.0.0`. |

---

## 6. `Data.Range.Ord`

### Current state

Well-documented in v1.0 — examples for both newtypes, cross-references, `@since`
annotations. No further changes needed.

---

## 7. Migration guide (new section at end of README)

The following is the complete text to append to `README.markdown`.

---

### Migrating from v0.3 to v1.0

v1.0 unifies the old `Data.Range` and `Data.Ranges` modules into a single
`Data.Ranges` module built around the `Ranges a` newtype. `Data.Range` still
exists as a deprecated re-export shim so that code that only uses the module
import line continues to compile, but all names have moved.

#### Change the import

```haskell
-- v0.3
import Data.Range

-- v1.0
import Data.Ranges
```

If you were importing `Data.Ranges` from v0.3 (the old newtype wrapper module),
your import line is already correct.

#### The core type is now `Ranges a`, not `[Range a]`

In v0.3, most functions worked directly on `[Range a]` lists. In v1.0 the primary
type is `Ranges a` — a canonicalised, indexed collection.

Use `mergeRanges` to promote a raw list, and `unRanges` to extract the list back:

```haskell
-- v0.3
let rs :: [Range Integer]
    rs = mergeRanges [1 +=+ 10, 5 +=+ 20]

-- v1.0
let rs :: Ranges Integer
    rs = mergeRanges [SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)
                     ,SpanRange (Bound 5 Inclusive) (Bound 20 Inclusive)]
-- or, using the operators which now produce Ranges directly:
let rs = 1 +=+ 10 <> 5 +=+ 20 :: Ranges Integer
```

#### Operators now return `Ranges a`, not `Range a`

In v0.3, `1 +=+ 10` had type `Range Integer`. In v1.0 it has type `Ranges Integer`.

If you need a raw `Range a` value (for `inRange`, `rangesOverlap`, `rangesAdjoin`,
`KeyRange`, or `SortedRange`) use the data constructors directly:

```haskell
-- v0.3
inRange (1 +=+ 10) value

-- v1.0
inRange (SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)) value
-- or use inRanges with a Ranges value:
inRanges (1 +=+ 10) value
```

#### `mergeRanges` returns `Ranges a`

```haskell
-- v0.3
mergeRanges :: Ord a => [Range a] -> [Range a]

-- v1.0
mergeRanges :: Ord a => [Range a] -> Ranges a
```

Code that threaded the result directly into another `[Range a]`-expecting
function must be updated. In practice this is usually a no-op because both the
source and destination are now `Ranges a`.

#### All set operations take and return `Ranges a`

`union`, `intersection`, `difference`, `invert`, `fromRanges`, `joinRanges`,
`inRanges`, `aboveRanges`, and `belowRanges` all take/return `Ranges a` in v1.0.
Wrap inputs with `mergeRanges` or build them with the operators.

#### Use `<>` and `mconcat` for building collections

`Ranges a` is a `Semigroup` and `Monoid` where `(<>)` means union-and-merge and
`mempty` is the empty set. This replaces manual `union` calls on lists:

```haskell
-- v0.3
union [1 +=+ 5] [3 +=+ 8]

-- v1.0
(1 +=+ 5 :: Ranges Integer) <> 3 +=+ 8
-- or
mconcat [1 +=+ 5, 3 +=+ 8] :: Ranges Integer
```

#### `parseRanges` returns `Ranges a`

```haskell
-- v0.3
parseRanges :: (Read a, Ord a) => String -> Either ParseError [Range a]

-- v1.0
parseRanges :: (Read a, Ord a) => String -> Either ParseError (Ranges a)
```

The result is now immediately usable for membership testing without a
`mergeRanges` call.

#### `Functor` instance removed

The `fmap` instance on `Ranges` and `Range` has been removed because it was
silently incorrect for half-infinite ranges with non-monotone functions
(e.g. `fmap negate (lbi 5)` produced `lbi (-5)` instead of the correct `ubi (-5)`).

The safe alternative is to **map the query value** through the inverse function
rather than mapping the range boundaries:

```haskell
-- v0.3 (incorrect for half-infinite ranges with negate/subtract/etc.)
inRanges (fmap (+10) myRanges) query

-- v1.0 (always correct)
inRanges myRanges (query - 10)
```

#### New modules in v1.0

| Module | Purpose |
|--------|---------|
| `Data.Range.Ord` | `KeyRange` (for `Map`/`Set`) and `SortedRange` (positional sort) newtypes |
| `Data.Range.Algebra` | F-Algebra expression trees for deferred, efficient multi-step operations |
| `Data.Range.Parser` | Updated to return `Ranges a`; `customParseRanges` and `RangeParserArgs` |

#### Performance improvements in v1.0

- `inRanges`: O(log n) binary search on the canonical span list (was O(n) linear scan)
- `aboveRanges` / `belowRanges`: O(1) cached predicate (was O(n) linear scan)

---

## 8. Priority ordering

| Priority | Item | Effort |
|----------|------|--------|
| 1 | README example — fix broken import and rewrite for v1.0 API | Small |
| 2 | README — add migration guide (text in §7 above) | Small (copy §7) |
| 3 | README — add features/module overview section | Small |
| 4 | `Data.Ranges` — fix `$creation` section note (remove internal module ref) | Tiny |
| 5 | `Data.Ranges` — `fromRanges` interleaving note | Tiny |
| 6 | `Data.Ranges` — `@since 1.0.0.0` on changed/added symbols | Small |
| 7 | `Data.Range.Algebra` — clarify predicate example leaf type | Tiny |
| 8 | `Data.Range.Parser` — `@since 1.0.0.0` on `parseRanges` | Tiny |
