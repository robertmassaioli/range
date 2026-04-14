# Proposal: Comprehensive Boundary and Exclusive-Bound Test Coverage

## Relationship to Recommendation #3

Recommendation #3 in `ten-improvement-recommendations.md` already identifies the core
problem: `Test/Generators.hs` always generates `Inclusive` bounds, so QuickCheck
never exercises the exclusive-bound code paths. This proposal is the detailed
implementation plan for that recommendation, grounded in a concrete bug that was
found in the 0.4.0.0 development cycle.

---

## The Bug That Motivated This

### What went wrong

`buildSpanQuery` (and the old `inRanges` before it) used `boundCmp` to check
whether a value falls inside a span:

```haskell
-- Old / buggy
Just (lo, hi) -> boundCmp v (lo, hi) == EQ
```

`boundCmp` is a three-way comparator designed for binary search navigation. It maps
the relationship between a point and a span to `LT / EQ / GT`. Its implementation:

```haskell
boundCmp ab (xb, yb)
  | boundIsBetween ab (xb, yb) /= Separate = EQ   -- ← the problem
  | a <= x    = LT
  | otherwise = GT
```

`boundIsBetween` returns one of three values:

| Result    | Meaning |
|-----------|---------|
| `Overlap` | point is strictly **inside** the span |
| `Adjoin`  | point is exactly **at an exclusive boundary** — touching but outside |
| `Separate`| point is completely outside |

The `EQ` branch fires for *both* `Overlap` and `Adjoin`. So for the span
`(-10, -6)` (exclusive on both ends) and the query value `-6`:

```
boundIsBetween (Bound (-6) Inclusive) (Bound (-10) Exclusive, Bound (-6) Exclusive)
  -- upper = -6 (Exclusive), value = -6 (Inclusive)
  -- pointJoinType Inclusive Exclusive = Adjoin
  → Adjoin
```

`Adjoin /= Separate` is `True`, so `boundCmp` returns `EQ`, and `buildSpanQuery`
returned `True` — claiming `-6` is inside `(-10, -6)`. The correct answer is `False`.

The fix was to use `boundIsBetween` directly and check for `Overlap` only:

```haskell
-- Fixed
Just (lo, hi) -> Overlap == boundIsBetween v (lo, hi)
```

This is consistent with how `inRange` on a single `SpanRange` works:

```haskell
inRange (SpanRange x y) value = Overlap == boundIsBetween (Bound value Inclusive) (x, y)
```

### Why the existing tests did not catch it

The `algebra equivalence` QuickCheck property checks that `eval` (concrete range
list) and `evalPredicate` (predicate algebra) agree on membership. This property
*can* detect the bug — but only if:

1. The generated expression evaluates to a range with at least one **exclusive
   endpoint** after set operations (e.g. after `invert`)
2. The generated query value **lands exactly on that exclusive endpoint**

Condition 2 has probability ≈ 0 for uniformly random `Integer` values. Over 100
QuickCheck trials with the default seed, this combination never occurred.

The `inRange` (single-range) tests are not affected at all — they use `== Overlap`
directly and are correct.

There is also `prop_in_range_out_of_range_after_invert` which asserts that
`inRanges rs point /= inRanges (invert rs) point`. This would also catch the bug,
but only for the same unlikely boundary collision.

### Why refactoring triggered the failure

The one-argument refactor of `inRanges`:

```haskell
-- Old (two-arg)
inRanges rs val = let v = ... in case loadRanges rs of ...

-- New (one-arg)
inRanges rs = case loadRanges rs of
  IRM            -> const True
  RM lb ub spans -> buildSpanQuery lb ub spans
```

changed GHC's compiled output (different closure layout, different thunk structure).
`test-framework` seeds QuickCheck's RNG from the test binary's runtime state. The
new binary produced a different effective seed, which happened to generate the exact
counterexample `([-6], not [SingletonRange 9, SingletonRange -10, lbi (-6)])` within
the first 14 trials.

This is the classic "latent bug revealed by unrelated change" pattern: the bug
existed before the refactor; the refactor just shifted the dice roll.

---

## Proposed Test Improvements

### Fix 1 — Update `Arbitrary (Range a)` to generate exclusive bounds (Recommendation #3)

In `Test/Generators.hs`, `generateSpan` always produces `Inclusive` bounds:

```haskell
generateSpan first second = first +=+ second  -- always Inclusive/Inclusive
```

Replace with a generator that independently picks `BoundType` for each end:

```haskell
generateSpan :: (Arbitrary a) => a -> a -> Gen (Range a)
generateSpan first second = do
  loType <- elements [Inclusive, Exclusive]
  hiType <- elements [Inclusive, Exclusive]
  return $ SpanRange (Bound first loType) (Bound second hiType)
```

Also update `generateLowerBound` and `generateUpperBound` similarly. This change
alone would have made the existing `algebra equivalence` and `invert complement`
properties reliably catch the boundary bug, since `invert` on an `Inclusive`-bounded
span produces `Exclusive`-bounded spans, and those would then appear in the canonical
range list that QuickCheck uses as query targets.

### Fix 2 — Add a property: `inRanges [r] val == inRange r val`

This is the fundamental contract between the single-range and multi-range APIs. It
currently has no explicit test:

```haskell
prop_inRanges_agrees_with_inRange :: Range Integer -> Integer -> Bool
prop_inRanges_agrees_with_inRange r val =
  inRanges [r] val == inRange r val
```

With exclusive bounds in the generator (Fix 1), QuickCheck will generate `SpanRange`
values with exclusive endpoints and values at those exact endpoints via its boundary
shrinking, reliably catching the class of bug described above.

### Fix 3 — Test `invert` complement at boundary points explicitly

The existing `prop_in_range_out_of_range_after_invert` uses a random `(point,
ranges)` pair and relies on the point hitting a boundary by chance. Replace it with
a version that *always tests the boundaries of the generated ranges*:

```haskell
prop_invert_complement_at_boundaries :: [Range Integer] -> Bool
prop_invert_complement_at_boundaries rs =
  let boundaries = concatMap boundaryValues rs
  in all (\v -> inRanges rs v /= inRanges (invert rs) v) boundaries
  where
    boundaryValues (SpanRange (Bound x _) (Bound y _)) = [x, y]
    boundaryValues (SingletonRange x)                   = [x]
    boundaryValues (LowerBoundRange (Bound x _))        = [x]
    boundaryValues (UpperBoundRange (Bound x _))        = [x]
    boundaryValues InfiniteRange                        = []
```

Keep the original random-point test too — the two are complementary.

### Fix 4 — Test `eval` / `evalPredicate` equivalence at boundary points

Augment `prop_equivalence_eval_and_evalPredicate` with a boundary-focused variant:

```haskell
prop_eval_evalPredicate_at_boundaries
  :: Alg.RangeExpr [Range Integer] -> Bool
prop_eval_evalPredicate_at_boundaries expr =
  let ranges     = Alg.eval expr :: [Range Integer]
      predicate  = Alg.eval $ fmap inRanges expr
      boundaries = concatMap boundaryValues ranges
  in all (\v -> inRanges ranges v == predicate v) boundaries
```

This would catch the original bug on the very first trial: `invert` produces
`Exclusive`-bounded spans, those spans' boundary values are extracted, and the
membership test is checked directly at those values.

### Fix 5 — Add a generator biased toward boundary values

Add a `SpanWithBoundary` generator that always produces a span and one of its
exact boundary values, ensuring every trial exercises the boundary case:

```haskell
data SpanWithBoundary = SpanWithBoundary (Range Integer) Integer
  deriving Show

instance Arbitrary SpanWithBoundary where
  arbitrary = do
    lo    <- arbitrarySizedIntegral
    hi    <- arbitrarySizedIntegral `suchThat` (>= lo)
    loTy  <- arbitrary
    hiTy  <- arbitrary
    val   <- elements [lo, hi]   -- always pick a boundary value
    return $ SpanWithBoundary (SpanRange (Bound lo loTy) (Bound hi hiTy)) val

prop_boundary_membership_consistent :: SpanWithBoundary -> Bool
prop_boundary_membership_consistent (SpanWithBoundary r val) =
  inRanges [r] val == inRange r val
```

---

## Implementation Priority

| Fix | Effort | Impact |
|-----|--------|--------|
| Fix 1: exclusive bounds in `Arbitrary` | Low — one-line change per generator | **High** — improves all existing properties at once |
| Fix 2: `inRanges == inRange` contract  | Low — new property | **High** — directly pins the invariant that was broken |
| Fix 3: complement at boundaries        | Low — extract boundary values | Medium — strengthens existing invert test |
| Fix 4: algebra equivalence at boundaries | Low — reuse boundary extractor | Medium — closes the specific failure mode we saw |
| Fix 5: `SpanWithBoundary` generator    | Low — small new Arbitrary instance | Medium — forces boundary coverage on every run |

Fix 1 is the highest leverage change: it costs almost nothing and immediately
improves the coverage of every property in the suite that operates on `Range` values.
Fix 2 provides the clearest documentation of the contract. Both should be implemented
together as a single commit.
