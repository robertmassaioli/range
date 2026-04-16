module Test.RangeBounds
   ( rangeBoundsTestCases
   ) where

import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck (Positive(..), Property, (==>))

import Data.Ranges
import Test.Generators ()

-- ---------------------------------------------------------------------------
-- inRange: exclusive vs inclusive endpoint behaviour
-- ---------------------------------------------------------------------------

-- Exclusive lower bound: the boundary value itself is NOT in the range.
prop_exclusive_lower_excludes_endpoint :: Positive Integer -> Bool
prop_exclusive_lower_excludes_endpoint (Positive x) =
   not $ inRange (SpanRange (Bound x Exclusive) (Bound (x + 10) Inclusive)) x

-- Inclusive lower bound: the boundary value IS in the range.
prop_inclusive_lower_includes_endpoint :: Positive Integer -> Bool
prop_inclusive_lower_includes_endpoint (Positive x) =
   inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Inclusive)) x

-- Exclusive upper bound: the boundary value itself is NOT in the range.
prop_exclusive_upper_excludes_endpoint :: Positive Integer -> Bool
prop_exclusive_upper_excludes_endpoint (Positive x) =
   not $ inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Exclusive)) (x + 10)

-- Inclusive upper bound: the boundary value IS in the range.
prop_inclusive_upper_includes_endpoint :: Positive Integer -> Bool
prop_inclusive_upper_includes_endpoint (Positive x) =
   inRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Inclusive)) (x + 10)

test_inrange_endpoints :: Test
test_inrange_endpoints = testGroup "inRange endpoint inclusion"
   [ testProperty "exclusive lower bound excludes endpoint" prop_exclusive_lower_excludes_endpoint
   , testProperty "inclusive lower bound includes endpoint" prop_inclusive_lower_includes_endpoint
   , testProperty "exclusive upper bound excludes endpoint" prop_exclusive_upper_excludes_endpoint
   , testProperty "inclusive upper bound includes endpoint" prop_inclusive_upper_includes_endpoint
   ]

-- ---------------------------------------------------------------------------
-- aboveRange / belowRange: exclusive bound semantics
-- ---------------------------------------------------------------------------

-- A value equal to an exclusive upper bound is ABOVE the range
-- (the range ends strictly before that value).
prop_above_exclusive_upper :: Positive Integer -> Bool
prop_above_exclusive_upper (Positive x) =
   aboveRange (SpanRange (Bound x Inclusive) (Bound (x + 10) Exclusive)) (x + 10)

-- A value equal to an exclusive lower bound is BELOW the range
-- (the range starts strictly after that value).
prop_below_exclusive_lower :: Positive Integer -> Bool
prop_below_exclusive_lower (Positive x) =
   belowRange (SpanRange (Bound x Exclusive) (Bound (x + 10) Inclusive)) x

test_above_below_exclusive :: Test
test_above_below_exclusive = testGroup "aboveRange/belowRange with exclusive bounds"
   [ testProperty "value at exclusive upper bound is above range" prop_above_exclusive_upper
   , testProperty "value at exclusive lower bound is below range" prop_below_exclusive_lower
   ]

-- ---------------------------------------------------------------------------
-- Half-infinite ranges: exclusive bounds
-- ---------------------------------------------------------------------------

-- lbe: exclusive lower bound does not include the endpoint but includes succ
prop_lbe_excludes_endpoint :: Integer -> Bool
prop_lbe_excludes_endpoint x =
   not (inRange (LowerBoundRange (Bound x Exclusive)) x)
   && inRange (LowerBoundRange (Bound x Exclusive)) (x + 1)

-- ube: exclusive upper bound does not include the endpoint but includes pred
prop_ube_excludes_endpoint :: Integer -> Bool
prop_ube_excludes_endpoint x =
   not (inRange (UpperBoundRange (Bound x Exclusive)) x)
   && inRange (UpperBoundRange (Bound x Exclusive)) (x - 1)

test_halfinfinte_exclusive :: Test
test_halfinfinte_exclusive = testGroup "half-infinite exclusive bounds"
   [ testProperty "lbe excludes endpoint, includes successor" prop_lbe_excludes_endpoint
   , testProperty "ube excludes endpoint, includes predecessor" prop_ube_excludes_endpoint
   ]

-- ---------------------------------------------------------------------------
-- Mutual exclusion: belowRanges / inRanges / aboveRanges
-- ---------------------------------------------------------------------------

-- For any point and any non-empty Ranges, no two of below/in/above can be
-- simultaneously true. (A point in the gap between disjoint ranges is none
-- of the three — that is also correct.)
--
-- The non-empty guard is necessary: for Ranges [], belowRanges and aboveRanges
-- both return True vacuously (there are no ranges to fail to be above/below),
-- so the mutual-exclusion invariant only holds for non-empty range sets.
prop_below_in_above_mutually_exclusive :: (Integer, Ranges Integer) -> Property
prop_below_in_above_mutually_exclusive (x, rs) =
   not (null (unRanges rs)) ==>
   let b = belowRanges rs x
       i = inRanges   rs x
       a = aboveRanges rs x
   in not (b && i) && not (a && i) && not (b && a)

test_partition :: Test
test_partition = testGroup "below/in/above mutual exclusion"
   [ testProperty "at most one of belowRanges/inRanges/aboveRanges holds"
       prop_below_in_above_mutually_exclusive
   ]

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

rangeBoundsTestCases :: [Test]
rangeBoundsTestCases =
   [ test_inrange_endpoints
   , test_above_below_exclusive
   , test_halfinfinte_exclusive
   , test_partition
   ]
