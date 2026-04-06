# Proposal: Enforce `RangeMerge` Invariants

## Problem

`RangeMerge a` is the library's core internal representation, and its correctness depends on three invariants documented in a comment block at `Data/Range/RangeInternal.hs:13-21`:

1. **No span–bound overlap.** The span ranges never overlap the lower or upper bounds.
2. **Sorted spans.** The span ranges are always sorted in ascending order by the first element.
3. **No infinite collapse.** The lower and upper bounds never overlap in such a way that together they form an infinite range.

Every function in `RangeInternal.hs` assumes these hold on entry. If a caller constructs or mutates a `RangeMerge` that violates them — for instance, by using record update syntax to splice in unsorted spans — the operations silently produce wrong results. There is currently no runtime check, no type-level enforcement, and no test-time validation.

The `RM` constructor and all three record fields (`largestLowerBound`, `largestUpperBound`, `spanRanges`) are exported from `Data.Range.RangeInternal` without restriction. The test suite (`Test/RangeMerge.hs`) constructs `RM` values directly in its `Arbitrary` instance and pattern-matches on them. The algebra (`Algebra.Internal`) consumes `RangeMerge` via `rangeMergeAlgebra`.

## Consumers of the `RM` constructor (directly affected by any change)

| File | Usage |
|------|-------|
| `Data/Range/RangeInternal.hs` | Defines `RM`, `IRM`, `emptyRangeMerge`, all operations |
| `Data/Range/Algebra/Internal.hs` | `rangeMergeAlgebra` consumes `RangeMerge` values |
| `Data/Range/Algebra/Range.hs` | `rangeAlgebra` calls `loadRanges`/`exportRangeMerge` |
| `Data/Range.hs` | Imports `exportRangeMerge`, `joinRM`, `loadRanges` |
| `Test/RangeMerge.hs` | `Arbitrary` instance constructs `RM` directly; tests pattern-match |

## Options

### Option 1: Add a `validateRangeMerge` function and use it in tests

Add a pure validation function that checks all three invariants:

```haskell
validateRangeMerge :: Ord a => RangeMerge a -> Bool
validateRangeMerge IRM = True
validateRangeMerge (RM lower upper spans) =
   spansAreSorted spans
   && spansAreNonOverlapping spans
   && spansDoNotOverlapBounds lower upper spans
   && boundsDoNotFormInfinite lower upper
```

Then use it as a postcondition in QuickCheck properties:

```haskell
prop_union_preserves_invariant :: (RangeMerge Integer, RangeMerge Integer) -> Bool
prop_union_preserves_invariant (a, b) = validateRangeMerge (unionRangeMerges a b)
```

**Pros:**
- Zero impact on existing code structure. The `RM` constructor and record fields remain unchanged.
- Immediately catches bugs in tests — if `unionRangeMerges` or `invertRM` produces an invalid `RangeMerge`, the property fails.
- The `Arbitrary` instance in `Test/RangeMerge.hs` (which already carefully constructs valid `RM` values) can use `validateRangeMerge` as a sanity check too.
- Non-breaking. No module export changes.

**Cons:**
- Runtime enforcement is opt-in: only catches problems where the validation is called. Production code can still silently construct invalid values.
- Doesn't prevent future developers from accidentally constructing bad `RM` values.

### Option 2: Smart constructor with opaque type

Make `RangeMerge` abstract by not exporting `RM` from `Data.Range.RangeInternal`. Instead, export a smart constructor that validates:

```haskell
mkRangeMerge :: Ord a => Maybe (Bound a) -> Maybe (Bound a) -> [(Bound a, Bound a)] -> RangeMerge a
mkRangeMerge lower upper spans
   | isSorted && noOverlap && noBoundOverlap && notInfinite = RM lower upper spans
   | otherwise = error "mkRangeMerge: invariant violation"
```

Provide pattern synonyms or accessor functions so existing consumers can still inspect the structure without reaching into the constructor.

**Pros:**
- Prevents invalid construction at the source. Every `RangeMerge` value is guaranteed to satisfy the invariants if it exists.
- Forces all construction through a single validated entry point.

**Cons:**
- High-impact refactor. Every file that pattern-matches on `RM` needs to change — `RangeInternal.hs` itself uses `RM` pervasively in internal functions, `Test/RangeMerge.hs` constructs it in `Arbitrary`, and `Algebra/Internal.hs` consumes it.
- `error` in a smart constructor is a partial function; this trades silent wrong answers for runtime crashes, which may be worse depending on your philosophy.
- The internal operations (`unionRangeMerges`, `invertRM`, etc.) construct intermediate `RM` values as part of their computation. Forcing these through validation adds overhead to every operation in the hot path.
- The `{-# LANGUAGE Safe #-}` pragma is used throughout — `error` is safe, but it shifts the failure mode.

### Option 3: `assert`-guarded record construction

Leave the `RM` constructor exported, but add `assert` checks to every function that **returns** a `RangeMerge`. The `assert` function from `Control.Exception` is a no-op when compiled without `-fno-ignore-asserts` (the default), so there's zero production overhead:

```haskell
unionRangeMerges :: (Ord a) => RangeMerge a -> RangeMerge a -> RangeMerge a
unionRangeMerges IRM _ = IRM
unionRangeMerges _ IRM = IRM
unionRangeMerges one two = assert (validateRangeMerge result) result
   where
      result = ... -- existing implementation
```

**Pros:**
- Zero overhead in production builds (asserts are stripped by default).
- Catches bugs during development and testing without changing the type or constructor visibility.
- Minimal code change — just wrap return values.
- Can be enabled selectively with `-fno-ignore-asserts` via a cabal flag for CI.

**Cons:**
- `Control.Exception.assert` is not in `{-# LANGUAGE Safe #-}` — it's in `Trustworthy`. The modules currently use `Safe`, and importing `Control.Exception` would require changing them to `Trustworthy`, which is a weakening of the safety guarantee.
- Still opt-in at compile time. Developers who forget to enable asserts don't get the check.
- Asserts in Haskell are less idiomatic than in imperative languages; some maintainers may find them surprising.

### Option 4: Validation in tests only, via a `QuickCheck` modifier

Create a `ValidatedRM` newtype that wraps `RangeMerge` and checks invariants on generation and shrinking:

```haskell
newtype ValidatedRM a = ValidatedRM { getRM :: RangeMerge a }

instance (Ord a, Arbitrary a, ...) => Arbitrary (ValidatedRM a) where
   arbitrary = do
      rm <- arbitrary
      if validateRangeMerge (getRM rm) then return rm else discard
   shrink (ValidatedRM rm) =
      [ValidatedRM s | s <- shrink rm, validateRangeMerge s]
```

Then use `ValidatedRM Integer` instead of `RangeMerge Integer` in all test properties to ensure only valid inputs are tested. Additionally, add postcondition properties that check outputs are valid.

**Pros:**
- No change to production code at all. Not a single line of `RangeInternal.hs` changes.
- Validates both inputs (via `Arbitrary`) and outputs (via postcondition properties).
- The existing `Arbitrary (RangeMerge a)` instance already constructs valid values, but this adds an explicit check that would catch any future regression in the generator.

**Cons:**
- Only catches issues that surface during testing. Like Option 1, does not prevent invalid construction at compile time.
- `discard` in the generator can slow down test execution if many invalid candidates are generated (though in practice, the existing `Arbitrary` instance produces valid values almost always).

## Recommendation

**Start with Option 1, with an eye toward Option 4.**

Option 1 is the right first step: implement `validateRangeMerge`, add postcondition properties to the existing `RangeMerge` tests, and add new properties that check every operation preserves the invariants. This is the highest value-to-effort ratio.

Then optionally adopt Option 4 (the `ValidatedRM` wrapper) if you want belt-and-suspenders on the test inputs too — this is a small addition on top of Option 1.

Options 2 and 3 require significantly more refactoring for marginal benefit. The `RangeMerge` type is purely internal (not exported to library users), so the risk surface is limited to the 5 files that touch it directly. Making the type opaque (Option 2) would pay off more in a library where external consumers construct `RangeMerge` values, but that's not the case here. The `assert` approach (Option 3) conflicts with the `Safe` Haskell pragma that the library uses throughout.
