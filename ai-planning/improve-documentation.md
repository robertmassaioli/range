# Proposal: Improve Documentation of Exposed Modules

## Overview

This proposal audits every Haddock comment across the five exposed modules
(`Data.Range`, `Data.Ranges`, `Data.Range.Ord`, `Data.Range.Parser`,
`Data.Range.Algebra`) and specifies concrete improvements. The goal is that a
first-time user can learn the library entirely from `stack haddock --open`, and
that existing users can discover cross-cutting relationships between modules.

---

## 1. Module-by-module audit

### 1.1 `Data.Range`

**Current state:** The best-documented module in the library. Has a rich
module-level Haddock (custom syntax walkthrough, two worked use-cases, GHCi
timing comparison). Most exported functions have examples.

**Specific gaps**

| Item | Gap |
|------|-----|
| `inRanges` | **No Haddock comment at all.** The most commonly called function in the library is completely undocumented. |
| `aboveRanges` / `belowRanges` | Single-sentence stubs with no examples, unlike the well-illustrated singular forms `aboveRange` / `belowRange`. |
| `union` / `intersection` / `difference` | Docs describe what they do but have no note about normalisation: the output is already merged, making a follow-up `mergeRanges` redundant. |
| `invert` | No mention of the double-invert identity (`invert . invert == id`), which is the most useful property to know when reasoning about it. |
| Cross-references | No `See also` links anywhere — e.g. `union` does not point to `intersection`, `mergeRanges` does not point to `joinRanges`, `aboveRange` does not point to `belowRange`. |
| `Bound` / `BoundType` re-exports | The data types are listed in the export section under `-- * Data types` but have no prose explaining why a user would construct them directly versus using the operators. |

**Recommended additions**

```haskell
-- | Given a list of ranges, returns 'True' if the value falls within any of them.
-- This is the primary membership test for the library and is significantly more
-- performant than @'elem' x [lo..hi]@ for large ranges.
--
-- >>> inRanges [1 +=+ 10, 20 +=+ 30] (5 :: Integer)
-- True
-- >>> inRanges [1 +=+ 10, 20 +=+ 30] (15 :: Integer)
-- False
-- >>> inRanges [] (0 :: Integer)
-- False
--
-- See also 'inRange' for testing against a single range.
inRanges :: (Ord a) => [Range a] -> a -> Bool
```

```haskell
-- | Checks if the value is above all of the given ranges.
-- Equivalent to @'all' ('aboveRange' r) ranges@.
--
-- >>> aboveRanges [1 +=+ 5, 10 +=+ 15] (20 :: Integer)
-- True
-- >>> aboveRanges [1 +=+ 5, lbi 10] (20 :: Integer)
-- False
aboveRanges :: (Ord a) => [Range a] -> a -> Bool
```

Add a note to `union`, `intersection`, and `difference`:

```haskell
-- | Performs a set union … The output is already in merged (canonical) form;
-- a subsequent call to 'mergeRanges' is redundant.
```

Add to `invert`:

```haskell
-- | … Note that @invert . invert == id@ for any list of ranges.
```

---

### 1.2 `Data.Ranges`

**Current state:** The most poorly documented exposed module. The module doc
comment is incomplete mid-sentence. Almost every function and instance is
undocumented. Re-exported operators carry no docs.

**Specific gaps**

| Item | Gap |
|------|-----|
| Module doc | Ends mid-sentence: *"…which lets you write code like:"* — followed by nothing. |
| `Ranges` newtype | No Haddock. A user reading the generated HTML has no description of what this type is or why they would use it over `[Range a]`. |
| `Semigroup` / `Monoid` instances | No doc. These are the main value-add of this module — `<>` meaning union-and-merge should be spelled out. |
| `Functor` instance | No doc. |
| All operators (`+=+`, `+=*`, etc.) | Re-exported without any accompanying docs. The generated Haddock shows blank entries. |
| `inRanges`, `union`, `intersection`, `difference`, `invert`, `fromRanges`, `joinRanges` | No docs on any of these. |

**Recommended additions**

Complete and extend the module doc:

```haskell
-- | This module provides a simpler interface than the 'Data.Range' module,
-- allowing you to work with multiple ranges at the same time via the 'Ranges'
-- newtype.
--
-- The primary advantage over 'Data.Range' is that 'Ranges' implements
-- 'Semigroup' and 'Monoid', where @('<>')@ means /union-and-merge/. This
-- composes naturally with standard Haskell idioms:
--
-- >>> import Data.Foldable (fold)
-- >>> fold [1 +=+ 5, 3 +=+ 8, lbi 20 :: Ranges Integer]
-- Ranges [1 +=+ 8,lbi 20]
--
-- For most use cases 'Data.Range' is sufficient. Prefer 'Data.Ranges' when:
--
-- * You want to accumulate ranges with 'mconcat' or '<>'.
-- * You are threading ranges through code that expects 'Monoid'.
-- * You want 'Functor' to map a function over all range boundaries.
```

Document the newtype and its instances:

```haskell
-- | A set of ranges represented as a merged, canonical list of non-overlapping
-- 'Range' values. The 'Semigroup' instance merges ranges on @('<>')@, so
-- @Ranges [1 +=+ 5] <> Ranges [3 +=+ 8]@ yields @Ranges [1 +=+ 8]@.
newtype Ranges a = Ranges { unRanges :: [Range a] }
```

Document the re-exported operators by adding a section note:

```haskell
-- * Range creation
-- $creation
-- The following operators construct a single-element 'Ranges'. They mirror
-- the operators in "Data.Range" but return 'Ranges' instead of 'Range',
-- so they can be combined directly with '<>'.
```

---

### 1.3 `Data.Range.Ord`

**Current state:** Written from scratch as part of this codebase session, so
it has the best structural coverage. The module doc, `KeyRange`, and
`SortedRange` all have solid descriptions. Internal helpers are unexported and
need no docs.

**Specific gaps**

| Item | Gap |
|------|-----|
| Module doc examples | The `Map` key example uses `lbi` and `+=+` without showing the required import of `Data.Range`. A self-contained example would lower the copy-paste barrier. |
| `KeyRange` | No `See also` pointing to `SortedRange` to explain the relationship. |
| `SortedRange` | No example showing the before/after effect of `sortOn SortedRange` in the Haddock. |
| Both newtypes | No note explaining that `unKeyRange` / `unSortedRange` are the unwrapping accessors, and when you would use them. |

**Recommended additions**

Extend the `SortedRange` doc:

```haskell
-- >>> import Data.List (sortOn)
-- >>> sortOn SortedRange [lbi 10, 1 +=+ 5, ube 0 :: Range Integer]
-- [ube 0,1 +=+ 5,lbi 10]
```

Add `-- | See also 'SortedRange'.` to `KeyRange` and vice versa.

Self-contained `Map` example in the module doc (include the `Data.Range` import).

---

### 1.4 `Data.Range.Parser`

**Current state:** The module doc and main functions are described, but two
known limitations are undocumented, the module example output is formatted
incorrectly for doctest, and the `ParseError` re-export has no explanation.

**Specific gaps**

| Item | Gap |
|------|-----|
| Negative number limitation | The parser only handles non-negative integers. `"-5"` is parsed as `UpperBoundRange 5`, not `SingletonRange (-5)`. This footgun (noted in improvement suggestion 4) is nowhere in the docs. |
| Empty / non-matching input | `parseRanges "abc"` returns `Right []` rather than a parse error, due to `sepBy`. This surprising behaviour is not documented. |
| Module example | The doctest-style example is missing the `>>>` prefix on the result line, so it would fail under `doctest`. |
| `ParseError` re-export | Exported but undocumented — users don't know this is Parsec's `ParseError` re-exported for convenience. |
| `ranges` parser | Described as returning *"a parsec parser"* but no mention of how to embed it in a larger Parsec grammar. |
| `customParseRanges` | No example showing a custom separator configuration. |
| `Read` constraint | No note that the `Read` instance determines which numeric type is parsed; exotic types need a well-behaved `Read`. |

**Recommended additions**

Fix the module doc example and add the known-limitation notes:

```haskell
-- | This package provides a simple range parser designed for CLI programs.
-- By default:
--
-- >>> parseRanges "-5,8-10,13-15,20-" :: Either ParseError [Range Integer]
-- Right [UpperBoundRange 5,SpanRange 8 10,SpanRange 13 15,LowerBoundRange 20]
--
-- The @*@ character produces an infinite range:
--
-- >>> parseRanges "*" :: Either ParseError [Range Integer]
-- Right [InfiniteRange]
--
-- __Known limitations:__
--
-- * Only non-negative integer literals are supported. The input @"-5"@ is
--   parsed as @UpperBoundRange 5@, not @SingletonRange (-5)@. For negative
--   values, use 'customParseRanges' with a different 'rangeSeparator', or
--   pre-process the input.
--
-- * Unrecognised input is silently consumed as an empty list rather than
--   producing a parse error (a consequence of 'sepBy'). For example,
--   @parseRanges "abc"@ returns @Right []@.
```

Document `ParseError`:

```haskell
-- | Re-exported from "Text.Parsec" for convenience, so callers do not need
-- to import Parsec directly just to match on parse failures.
```

Add a `customParseRanges` example:

```haskell
-- >>> let args = defaultArgs { unionSeparator = ";", rangeSeparator = ".." }
-- >>> customParseRanges args "1..5;10" :: Either ParseError [Range Integer]
-- Right [1 +=+ 5,SingletonRange 10]
```

---

### 1.5 `Data.Range.Algebra`

**Current state:** Has the best introductory framing (F-Algebra explanation
with external link), but the example code is broken and several core types are
completely undocumented.

**Specific gaps**

| Item | Gap |
|------|-----|
| Module example | The `(A.eval …)` expression is missing the `>>>` prefix, so the example is not doctest-runnable and renders oddly in Haddock. |
| `RangeExpr` type | Exported but has **no Haddock comment**. Users see the type name in the export list and have no description of what it is. |
| `Algebra` type alias | Exported but has **no Haddock comment**. |
| `eval` | Doc says "convert your built expressions into ranges" but `eval` can also return `a -> Bool` — the predicate case is not mentioned. |
| `const` | Shadowing `Prelude.const` is surprising. No note that `Prelude hiding (const)` is needed. |
| Performance motivation | The module doc mentions amortising conversions but doesn't explain *when* the overhead becomes worth it — a single expression tree has no benefit over direct calls. |
| No predicate example | The module shows only the `[Range a]` evaluation path. The `a -> Bool` path — arguably the more interesting one — has no worked example. |

**Recommended additions**

Document `RangeExpr` and `Algebra`:

```haskell
-- | An expression tree representing a sequence of set operations on ranges.
-- Construct trees with 'const', 'union', 'intersection', 'difference', and
-- 'invert', then evaluate with 'eval'.
--
-- The type parameter @a@ is the range representation that the tree will
-- eventually evaluate to (e.g. @[Range Integer]@ or @Integer -> Bool@).
newtype RangeExpr a  -- (re-exported from Internal)

-- | The type of an evaluation function for a 'RangeExpr'. You will not
-- normally need to reference this alias directly; it exists to express the
-- signature of 'eval'.
type Algebra f a  -- (re-exported from Control.Monad.Free)
```

Fix and expand the module examples:

```haskell
-- == Examples
--
-- Evaluate to a concrete list of ranges:
--
-- >>> import qualified Data.Range.Algebra as A
-- >>> A.eval . A.invert $ A.const [SingletonRange (5 :: Integer)]
-- [ube 4,lbi 6]
--
-- Evaluate to a predicate (no intermediate list is constructed):
--
-- >>> let expr = A.union (A.const [1 +=+ 10]) (A.const [20 +=+ 30]) :: A.RangeExpr [Range Integer]
-- >>> (A.eval expr :: Integer -> Bool) 25
-- True
--
-- __When to use this module:__ Build an expression tree when you are
-- combining three or more operations in a pipeline. A single @union a b@
-- is no faster through the algebra; the benefit accrues when the same
-- expression is evaluated against multiple target types, or when the tree
-- is constructed once and evaluated repeatedly.
```

Extend the `eval` doc:

```haskell
-- | Evaluates a 'RangeExpr' to its target representation. Two evaluation
-- targets are supported out of the box:
--
-- * @[Range a]@ — produces a merged, canonical list of ranges.
-- * @a -> Bool@ — produces a predicate; no intermediate list is built.
--
-- Additional targets can be defined by implementing 'RangeAlgebra'.
eval :: Algebra RangeExpr a
```

Add a note to `const`:

```haskell
-- | Lifts a value as a constant leaf into an expression tree.
-- Note that this shadows 'Prelude.const'; the import in "Data.Range.Algebra"
-- uses @import Prelude hiding (const)@.
const :: a -> RangeExpr a
```

---

## 2. Cross-cutting improvements

### 2.1 Module relationship overview

No module currently explains how the five modules relate to each other.
The `Data.Range` module doc should gain a short section:

```haskell
-- = Module guide
--
-- * "Data.Range" — __start here__. Functions on @[Range a]@.
-- * "Data.Ranges" — 'Newtype' wrapper with 'Monoid' / 'Semigroup' semantics.
-- * "Data.Range.Ord" — 'Ord' newtypes for 'Map' keys and positional sorting.
-- * "Data.Range.Parser" — Parsec-based parser for CLI range strings.
-- * "Data.Range.Algebra" — F-Algebra for deferred, efficient expression trees.
```

### 2.2 Doctest coverage

Several existing examples are not doctest-runnable:

| Module | Example issue |
|--------|---------------|
| `Data.Range.Algebra` | Missing `>>>` prefix on `(A.eval …)` line |
| `Data.Range.Parser` | Output shown without `>>>` prefix |
| `Data.Range` | All examples appear correct |

Adding `doctest` as a test stanza to `range.cabal` would catch regressions
automatically:

```cabal
test-suite doctest-range
  type:             exitcode-stdio-1.0
  main-is:          Test/Doctest.hs
  build-depends:    base, doctest >= 0.20 && < 1, range
  default-language: Haskell2010
  ghc-options:      -Wall
```

```haskell
-- Test/Doctest.hs
module Main where
import Test.DocTest
main :: IO ()
main = doctest
  [ "Data/Range.hs"
  , "Data/Ranges.hs"
  , "Data/Range/Ord.hs"
  , "Data/Range/Parser.hs"
  , "Data/Range/Algebra.hs"
  ]
```

### 2.3 Haddock section headers

`Data.Range` uses `-- *` section headers well. The other modules use them
inconsistently or not at all:

- `Data.Ranges`: add the same sections as `Data.Range` (`Range creation`,
  `Comparison functions`, `Set operations`, etc.).
- `Data.Range.Ord`: add `-- * Structural ordering` and `-- * Positional ordering`
  sections in the export list.
- `Data.Range.Parser`: add `-- * Parsing` and `-- * Configuration` sections.
- `Data.Range.Algebra`: add `-- * Building expressions` and `-- * Evaluation` sections.

### 2.4 `since` annotations

Now that the library has a version history, new additions should carry
`@since` annotations so users know when they can rely on a symbol:

```haskell
-- | ...
-- @since 0.3.2.0
newtype KeyRange a = ...
```

This is especially valuable for `Data.Range.Ord` (introduced in 0.3.2.0) and
any additions to `Data.Ranges` (which has accumulated undocumented behaviour
across versions).

---

## 3. Priority ordering

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| 1 | `Data.Ranges` module doc (incomplete sentence) | Tiny | Blocks generated docs being coherent |
| 2 | `inRanges` Haddock in `Data.Range` | Tiny | Most-called function has zero docs |
| 3 | `Data.Range.Parser` known limitations | Small | Prevents silent footguns |
| 4 | `Data.Range.Algebra` fix broken example + doc `RangeExpr`/`Algebra` | Small | Broken examples erode trust |
| 5 | `Data.Ranges` document all functions and instances | Medium | Module is nearly opaque |
| 6 | Module relationship guide in `Data.Range` | Small | High discoverability value |
| 7 | `Data.Range.Algebra` predicate example + `eval` expansion | Small | Hides most useful feature |
| 8 | `@since` annotations on new symbols | Small | Good hygiene for library versioning |
| 9 | `Data.Range.Ord` `sortOn` example + cross-references | Tiny | Rounds out already-good docs |
| 10 | Add `doctest` test stanza | Medium | Prevents future doc regressions |
| 11 | Cross-references (`See also`) throughout `Data.Range` | Medium | Discoverability |
