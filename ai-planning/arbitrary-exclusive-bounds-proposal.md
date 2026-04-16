# Proposal: Fix Arbitrary (Range a) to Generate Exclusive Bounds

## Problem

`Test/Generators.hs` defines the `Arbitrary (Range a)` instance used by every
QuickCheck property in the test suite. The `generateSpan` generator always
produces `Inclusive` bounds on both endpoints:

```haskell
generateSpan = do
   first  <- arbitrarySizedIntegral
   second <- arbitrarySizedIntegral `suchThat` (> first)
   return $ SpanRange (Bound first Inclusive) (Bound second Inclusive)
```

Similarly `generateLowerBound` and `generateUpperBound` always use `Inclusive`:

```haskell
generateLowerBound = liftM (\x -> LowerBoundRange (Bound x Inclusive)) arbitrarySizedIntegral
generateUpperBound = liftM (\x -> UpperBoundRange (Bound x Inclusive)) arbitrarySizedIntegral
```

Consequence: **no property test involving generated `Range` values ever
exercises exclusive bounds.** There are four `SpanRange` operators (`+=+`,
`+=*`, `*=+`, `*=*`), four bound constructors (`lbi`, `lbe`, `ubi`, `ube`),
and the correctness of all of them is untested at the public API level.
`RangeMerge`-level tests do use `maybeBound` to generate `Exclusive` bounds,
but those tests operate on the internal `RangeMerge` type rather than the
public `Range`/`Ranges` API.

---

## Fix

### 1. Add `Arbitrary BoundType` to `Test/Generators.hs`

```haskell
instance Arbitrary BoundType where
  arbitrary = elements [Inclusive, Exclusive]
```

`BoundType` is a two-constructor type with no constraints; `elements` is the
right combinator.

### 2. Fix `generateSpan`

```haskell
generateSpan = do
   first    <- arbitrarySizedIntegral
   second   <- arbitrarySizedIntegral `suchThat` (> first)
   loBound  <- arbitrary
   hiBound  <- arbitrary
   return $ SpanRange (Bound first loBound) (Bound second hiBound)
```

The `suchThat (> first)` guard already ensures `first /= second`, so
`isEmptySpan` will never fire (it only eliminates spans where both endpoints
are equal with at least one exclusive). All four `BoundType` combinations
are now equally likely.

### 3. Fix `generateLowerBound` and `generateUpperBound`

```haskell
generateLowerBound = do
   x     <- arbitrarySizedIntegral
   bound <- arbitrary
   return $ LowerBoundRange (Bound x bound)

generateUpperBound = do
   x     <- arbitrarySizedIntegral
   bound <- arbitrary
   return $ UpperBoundRange (Bound x bound)
```

---

## New tests

Fix the generator and add a dedicated test group covering exclusive-bound
semantics. These tests exercise the four endpoint cases that generated tests
cannot currently reach.

### Proposed additions to `Test/RangeParser.hs` — no changes needed

The parser only produces `Inclusive` bounds (it reads integers and constructs
`Bound x Inclusive`). Exclusive bound testing belongs in the range predicate
tests, not the parser tests.

### Proposed additions to a new `Test/RangeBounds.hs`

Create `Test/RangeBounds.hs` (exported as `rangeBoundsTestCases :: [Test]`
and added to `Test/Range.hs`'s `tests` list and `range.cabal`'s
`other-modules`).

#### Unit tests — `inRange` exclusive endpoint behaviour

These four cases are the core correctness guarantee for exclusive bounds.
Each is a `Bool` property (no QuickCheck generation needed — the point being
tested is the boundary value itself):

```haskell
-- Exclusive lower bound: endpoint is NOT in range
prop_exclusive_lower_excludes_endpoint :: Positive Integer -> Bool
prop_exclusive_lower_excludes_endpoint (Positive x) =
   not $ inRange (SpanRange (Bound x Exclusive) (Bound (x + 10) Inclusive)) x

-- Inclusive lower bound: endpoint IS in range
prop_inclusive_lower_includes_endpoint :: Positive Integer -> Bool
prop_inclusive_lower_includes_endpoint (Positive x) =
   inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Inclusive)) x

-- Exclusive upper bound: endpoint is NOT in range
prop_exclusive_upper_excludes_endpoint :: Positive Integer -> Bool
prop_exclusive_upper_excludes_endpoint (Positive x) =
   not $ inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Exclusive)) (x + 10)

-- Inclusive upper bound: endpoint IS in range
prop_inclusive_upper_includes_endpoint :: Positive Integer -> Bool
prop_inclusive_upper_includes_endpoint (Positive x) =
   inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Inclusive)) (x + 10)
```

#### Unit tests — `aboveRange` and `belowRange` with exclusive bounds

```haskell
-- A value equal to an exclusive upper bound IS above the range
-- (the range ends just before that value)
prop_above_exclusive_upper :: Positive Integer -> Bool
prop_above_exclusive_upper (Positive x) =
   aboveRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Exclusive)) (x + 10)

-- A value equal to an exclusive lower bound IS below the range
prop_below_exclusive_lower :: Positive Integer -> Bool
prop_below_exclusive_lower (Positive x) =
   belowRange (SpanRange (Bound x Exclusive) (Bound (x + 10) Inclusive)) x
```

#### Unit tests — half-infinite exclusive bounds

```haskell
-- lbe: exclusive lower bound does not include the endpoint
prop_lbe_excludes_endpoint :: Integer -> Bool
prop_lbe_excludes_endpoint x =
   not (inRange (LowerBoundRange (Bound x Exclusive)) x)
   && inRange (LowerBoundRange (Bound x Exclusive)) (x + 1)

-- ube: exclusive upper bound does not include the endpoint
prop_ube_excludes_endpoint :: Integer -> Bool
prop_ube_excludes_endpoint x =
   not (inRange (UpperBoundRange (Bound x Exclusive)) x)
   && inRange (UpperBoundRange (Bound x Exclusive)) (x - 1)
```

#### QuickCheck properties — algebraic laws hold for all bound types

Once the generator is fixed, the existing law properties in `RangeLaws.hs`
will automatically exercise exclusive bounds. No new law properties are needed
for this — the value comes from the generator fix, not from new properties.

However, one new property specifically targets the consistency between
`belowRanges`, `inRanges`, and `aboveRanges` across all generated ranges,
since those three predicates share the canonical-order invariant:

```haskell
-- For any point and any Ranges, exactly one of below/in/above holds.
prop_below_in_above_partition :: (Integer, Ranges Integer) -> Bool
prop_below_in_above_partition (x, rs) =
   let b = belowRanges rs x
       i = inRanges   rs x
       a = aboveRanges rs x
   -- Exactly one must be True, OR none (when x is between two disjoint ranges).
   -- The invariant is: below and in cannot both be true; above and in cannot
   -- both be true; below and above cannot both be true.
   in not (b && i) && not (a && i) && not (b && a)
```

This is a weak invariant (it does not require exactly one to be true — a
value in the gap between two disjoint ranges is neither below, in, nor above)
but it catches the most likely exclusive-bound bugs.

---

## Summary of changes

| File | Change |
|------|--------|
| `Test/Generators.hs` | Add `Arbitrary BoundType`; fix `generateSpan`, `generateLowerBound`, `generateUpperBound` to use random `BoundType` |
| `Test/RangeBounds.hs` | New file: 8 unit tests for exclusive bound semantics + 1 partition property |
| `Test/Range.hs` | Import `Test.RangeBounds`; add `rangeBoundsTestCases` to `tests` |
| `range.cabal` | Add `Test.RangeBounds` to `test-range` `other-modules` |

Expected test count: +9 (from 73 to 82).

---

## Risk

The generator change will affect all existing QuickCheck properties. There is
a small risk that a property currently passing with only inclusive bounds will
fail with exclusive bounds, exposing a real bug. This is the intended outcome —
that is exactly what item 2 is pointing at.

If a property fails after the generator fix, investigate the failure before
suppressing it. A counterexample with exclusive bounds is a real correctness
issue, not a test artifact.
