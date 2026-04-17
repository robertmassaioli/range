# range - by Robert Massaioli

The `range` library makes it easy to work with ranges over any `Ord` type —
integers, version numbers, custom ordered types, or anything else. Given a set
of ranges and a value, you can test membership, compute unions and intersections,
invert a range set, enumerate the covered values, and more.

This library is significantly more efficient than using `elem x [lo..hi]` or
filtering large lists. `inRanges` runs in O(log n), and `aboveRanges` /
`belowRanges` are O(1).

## Modules

| Module | Purpose |
|--------|---------|
| `Data.Ranges` | **Start here.** `Ranges` type, all construction operators, set operations, and membership predicates. |
| `Data.Range` | Deprecated re-export shim pointing at `Data.Ranges`. |
| `Data.Range.Ord` | `KeyRange` and `SortedRange` newtypes for use as `Map` keys or for positional sorting. |
| `Data.Range.Parser` | Parsec-based parser for human-readable range strings (e.g. CLI input). |
| `Data.Range.Algebra` | F-Algebra expression trees for chaining multiple set operations efficiently. |

## Example

The library works on any `Ord` type. Here it checks software version compatibility
using `Data.Version` from `base`:

```haskell
module Main where

import Data.Ranges
import Data.Version (Version, makeVersion, showVersion)

-- Versions compatible with our library: [1.0, 2.0) and [2.1, 2.4].
-- The exclusive upper bound on the first range neatly captures all 1.x
-- versions. The gap at 2.0 reflects a known-bad release.
compatible :: Ranges Version
compatible = makeVersion [1,0] +=* makeVersion [2,0]
          <> makeVersion [2,1] +=+ makeVersion [2,4]

check :: Version -> String -> IO ()
check v label = putStrLn $ "[" ++ show (inRanges compatible v) ++ "] " ++ label

main :: IO ()
main = do
    check (makeVersion [1,5])    "v1.5   — in the 1.x compatible band"
    check (makeVersion [2,0])    "v2.0   — in the gap, NOT compatible"
    check (makeVersion [2,0,5])  "v2.0.5 — still in the gap, NOT compatible"
    check (makeVersion [2,1])    "v2.1   — inclusive lower bound, compatible"
    check (makeVersion [2,3])    "v2.3   — in the 2.1–2.4 compatible band"
    check (makeVersion [3,0])    "v3.0   — above all compatible ranges"
    putStrLn $ "anything below "
            ++ showVersion (makeVersion [1,0])
            ++ " is below all ranges: "
            ++ show (belowRanges compatible (makeVersion [0,9]))
    putStrLn $ "anything above "
            ++ showVersion (makeVersion [2,4])
            ++ " is above all ranges: "
            ++ show (aboveRanges compatible (makeVersion [3,0]))
```

Expected output:

```
[True]  v1.5   — in the 1.x compatible band
[False] v2.0   — in the gap, NOT compatible
[False] v2.0.5 — still in the gap, NOT compatible
[True]  v2.1   — inclusive lower bound, compatible
[True]  v2.3   — in the 2.1–2.4 compatible band
[False] v3.0   — above all compatible ranges
anything below 1.0 is below all ranges: True
anything above 2.4 is above all ranges: True
```

For a more complete example in a real program, see [splitter][1].

## Installation

From Hackage using Cabal:

```shell
cabal install range
```

From source using [Haskell Stack][2]:

```shell
stack build
```

## Building and testing

```shell
# Run the test suite
stack test

# Run the benchmark suite
stack bench

# Benchmark results in CSV format (useful for comparing runs)
stack bench --benchmark-arguments '--csv bench-results.csv'
```

---

## Migrating from v0.3 to v1.0

v1.0 consolidates the old `Data.Range` and `Data.Ranges` modules into a single
`Data.Ranges` module built around the `Ranges a` newtype. `Data.Range` still
exists as a deprecated re-export shim so imports continue to compile, but all
names are now in `Data.Ranges`.

### Change the import

```haskell
-- v0.3
import Data.Range

-- v1.0
import Data.Ranges
```

### The core type is now `Ranges a`, not `[Range a]`

In v0.3, most functions worked directly on `[Range a]` lists. In v1.0 the primary
type is `Ranges a` — a canonicalised, indexed collection. Use `mergeRanges` to
promote a raw list, and `unRanges` to extract the list back:

```haskell
-- v0.3
let rs :: [Range Integer]
    rs = [1 +=+ 10, 5 +=+ 20]

-- v1.0
let rs :: Ranges Integer
    rs = 1 +=+ 10 <> 5 +=+ 20
-- or from a raw list:
let rs = mergeRanges [SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)
                     ,SpanRange (Bound 5 Inclusive) (Bound 20 Inclusive)]
```

### Operators now return `Ranges a`, not `Range a`

In v0.3, `1 +=+ 10` had type `Range Integer`. In v1.0 it has type `Ranges Integer`.

If you need a raw `Range a` value (for `inRange`, `rangesOverlap`, `rangesAdjoin`,
`KeyRange`, or `SortedRange`) use the data constructors directly:

```haskell
-- v0.3
inRange (1 +=+ 10) value

-- v1.0 — use the data constructor for a single-range test
inRange (SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)) value
-- or use inRanges with a Ranges value
inRanges (1 +=+ 10) value
```

### `mergeRanges` returns `Ranges a`

```haskell
-- v0.3
mergeRanges :: Ord a => [Range a] -> [Range a]

-- v1.0
mergeRanges :: Ord a => [Range a] -> Ranges a
```

### All set operations take and return `Ranges a`

`union`, `intersection`, `difference`, `invert`, `fromRanges`, `joinRanges`,
`inRanges`, `aboveRanges`, and `belowRanges` all take or return `Ranges a` in
v1.0. Wrap inputs with `mergeRanges` or build them with the operators.

### Use `<>` and `mconcat` for building collections

`Ranges a` is a `Semigroup` and `Monoid` where `(<>)` means union-and-merge and
`mempty` is the empty set:

```haskell
-- v0.3
union [1 +=+ 5] [3 +=+ 8]

-- v1.0
(1 +=+ 5 :: Ranges Integer) <> 3 +=+ 8
-- or
mconcat [1 +=+ 5, 3 +=+ 8] :: Ranges Integer
```

### `parseRanges` returns `Ranges a`

```haskell
-- v0.3
parseRanges :: (Read a, Ord a) => String -> Either ParseError [Range a]

-- v1.0
parseRanges :: (Read a, Ord a) => String -> Either ParseError (Ranges a)
```

The result is immediately usable for membership testing — no `mergeRanges` call needed.

### `Functor` instance removed

The `fmap` instance on `Ranges` and `Range` has been removed. It was silently incorrect
for half-infinite ranges with non-monotone functions: `fmap negate (lbi 5)` produced
`lbi (-5)` (i.e. `[−5, ∞)`) instead of the correct `ubi (-5)` (i.e. `(−∞, −5]`).

The safe replacement is to **map the query value** through the inverse function instead
of mapping range boundaries:

```haskell
-- v0.3 (incorrect for half-infinite ranges with negate, subtract, etc.)
inRanges (fmap (+10) myRanges) query

-- v1.0 (always correct)
inRanges myRanges (query - 10)
```

### New in v1.0

| Addition | Notes |
|----------|-------|
| `Semigroup` / `Monoid` on `Ranges a` | `(<>)` = union; `mempty` = empty set |
| `Eq (Ranges a)` | Compare two `Ranges` values for equality |
| `Data.Range.Ord` | `KeyRange` for `Map`/`Set` keys; `SortedRange` for positional sorting |
| `Data.Range.Algebra` | F-Algebra expression trees for multi-step operations |
| `inRanges` is O(log n) | Binary search on the canonical span list |
| `aboveRanges` / `belowRanges` are O(1) | Cached at construction time |

---

 [1]: http://hackage.haskell.org/package/splitter
 [2]: https://docs.haskellstack.org/
