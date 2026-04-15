module Test.RangeOrd
   ( rangeOrdTestCases
   ) where

import Data.List (sort, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Test.Framework (Test, testGroup)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck

import Data.Range
import Data.Range.Ord

import Test.Generators ()

-- ---------------------------------------------------------------------------
-- Local helpers — the module-level operators now return Ranges, not Range
-- ---------------------------------------------------------------------------

-- | Inclusive span Range
spanI :: a -> a -> Range a
spanI a b = SpanRange (Bound a Inclusive) (Bound b Inclusive)

-- | Lower bound inclusive Range
lbiR :: a -> Range a
lbiR x = LowerBoundRange (Bound x Inclusive)

-- | Upper bound inclusive Range
ubiR :: a -> Range a
ubiR x = UpperBoundRange (Bound x Inclusive)

-- | Upper bound exclusive Range
ubeR :: a -> Range a
ubeR x = UpperBoundRange (Bound x Exclusive)

-- | Infinite Range
infR :: Range a
infR = InfiniteRange

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Verify that compare is consistent with Eq for KeyRange
keyEqOrdConsistent :: Ord a => KeyRange a -> KeyRange a -> Bool
keyEqOrdConsistent x y = (x == y) == (compare x y == EQ)

-- Verify that compare is consistent with Eq for SortedRange
sortEqOrdConsistent :: Ord a => SortedRange a -> SortedRange a -> Bool
sortEqOrdConsistent x y = (x == y) == (compare x y == EQ)

-- ---------------------------------------------------------------------------
-- KeyRange: unit tests
-- ---------------------------------------------------------------------------

-- Constructor ordering: SingletonRange < SpanRange < LowerBoundRange <
--                       UpperBoundRange < InfiniteRange
prop_key_constructor_singleton_lt_span :: Bool
prop_key_constructor_singleton_lt_span =
   KeyRange (SingletonRange (0 :: Integer)) < KeyRange (spanI 0 0)

prop_key_constructor_span_lt_lower :: Bool
prop_key_constructor_span_lt_lower =
   KeyRange (spanI 0 (0 :: Integer)) < KeyRange (lbiR 0)

prop_key_constructor_lower_lt_upper :: Bool
prop_key_constructor_lower_lt_upper =
   KeyRange (lbiR (0 :: Integer)) < KeyRange (ubiR 0)

prop_key_constructor_upper_lt_infinite :: Bool
prop_key_constructor_upper_lt_infinite =
   KeyRange (ubiR (0 :: Integer)) < KeyRange (infR :: Range Integer)

-- Within the same constructor, compare by fields
prop_key_singletons_by_value :: Bool
prop_key_singletons_by_value =
   KeyRange (SingletonRange (3 :: Integer)) < KeyRange (SingletonRange 5)

prop_key_spans_by_lower_first :: Bool
prop_key_spans_by_lower_first =
   KeyRange (spanI (1 :: Integer) 10) < KeyRange (spanI 2 10)

prop_key_spans_by_upper_on_equal_lower :: Bool
prop_key_spans_by_upper_on_equal_lower =
   KeyRange (spanI (1 :: Integer) 5) < KeyRange (spanI 1 10)

prop_key_lower_bounds_by_value :: Bool
prop_key_lower_bounds_by_value =
   KeyRange (lbiR (1 :: Integer)) < KeyRange (lbiR 2)

prop_key_upper_bounds_by_value :: Bool
prop_key_upper_bounds_by_value =
   KeyRange (ubiR (1 :: Integer)) < KeyRange (ubiR 2)

prop_key_infinite_eq_infinite :: Bool
prop_key_infinite_eq_infinite =
   compare (KeyRange (infR :: Range Integer)) (KeyRange infR) == EQ

test_keyrange_unit :: Test
test_keyrange_unit = testGroup "KeyRange unit"
   [ testProperty "SingletonRange < SpanRange"     prop_key_constructor_singleton_lt_span
   , testProperty "SpanRange < LowerBoundRange"    prop_key_constructor_span_lt_lower
   , testProperty "LowerBoundRange < UpperBoundRange" prop_key_constructor_lower_lt_upper
   , testProperty "UpperBoundRange < InfiniteRange" prop_key_constructor_upper_lt_infinite
   , testProperty "singletons ordered by value"    prop_key_singletons_by_value
   , testProperty "spans ordered by lower bound first" prop_key_spans_by_lower_first
   , testProperty "spans ordered by upper bound when lower equal" prop_key_spans_by_upper_on_equal_lower
   , testProperty "lower bounds ordered by value"  prop_key_lower_bounds_by_value
   , testProperty "upper bounds ordered by value"  prop_key_upper_bounds_by_value
   , testProperty "InfiniteRange equals itself"    prop_key_infinite_eq_infinite
   ]

-- ---------------------------------------------------------------------------
-- KeyRange: QuickCheck properties
-- ---------------------------------------------------------------------------

prop_key_reflexive :: Range Integer -> Bool
prop_key_reflexive r = compare (KeyRange r) (KeyRange r) == EQ

prop_key_eq_ord_consistent :: Range Integer -> Range Integer -> Bool
prop_key_eq_ord_consistent x y = keyEqOrdConsistent (KeyRange x) (KeyRange y)

prop_key_antisymmetric :: Range Integer -> Range Integer -> Bool
prop_key_antisymmetric x y =
   case compare (KeyRange x) (KeyRange y) of
      LT -> compare (KeyRange y) (KeyRange x) == GT
      GT -> compare (KeyRange y) (KeyRange x) == LT
      EQ -> compare (KeyRange y) (KeyRange x) == EQ

prop_key_set_dedup :: [Range Integer] -> Bool
prop_key_set_dedup rs =
   -- Every range we put in we can get back out; Set operations work
   let keyed = map KeyRange rs
       s     = Set.fromList keyed
   in all (`Set.member` s) keyed

prop_key_map_lookup :: Range Integer -> String -> Bool
prop_key_map_lookup r v =
   Map.lookup (KeyRange r) (Map.singleton (KeyRange r) v) == Just v

test_keyrange_properties :: Test
test_keyrange_properties = testGroup "KeyRange properties"
   [ testProperty "reflexive"                prop_key_reflexive
   , testProperty "Eq/Ord consistent"        prop_key_eq_ord_consistent
   , testProperty "antisymmetric"            prop_key_antisymmetric
   , testProperty "usable in Set"            prop_key_set_dedup
   , testProperty "usable as Map key"        prop_key_map_lookup
   ]

-- ---------------------------------------------------------------------------
-- SortedRange: unit tests
-- ---------------------------------------------------------------------------

-- Ranges with NegInfinity lower bound sort before those with a finite lower bound
prop_sorted_upper_before_span :: Bool
prop_sorted_upper_before_span =
   SortedRange (ubiR (0 :: Integer)) < SortedRange (lbiR 0)

prop_sorted_infinite_before_lower :: Bool
prop_sorted_infinite_before_lower =
   SortedRange (infR :: Range Integer) < SortedRange (lbiR 1)

-- Spans ordered by lower bound
prop_sorted_singletons_by_value :: Bool
prop_sorted_singletons_by_value =
   SortedRange (SingletonRange (3 :: Integer)) < SortedRange (SingletonRange 5)

prop_sorted_spans_by_lower :: Bool
prop_sorted_spans_by_lower =
   SortedRange (spanI (1 :: Integer) 10) < SortedRange (spanI 2 10)

-- When lower bounds are equal, tiebreak by upper bound (smaller upper = comes first)
prop_sorted_tiebreak_by_upper :: Bool
prop_sorted_tiebreak_by_upper =
   SortedRange (spanI (1 :: Integer) 5) < SortedRange (spanI 1 10)

-- InfiniteRange and UpperBoundRange both start at -∞;
-- InfiniteRange ends at +∞ so it sorts after a finite UpperBoundRange
prop_sorted_upper_before_infinite :: Bool
prop_sorted_upper_before_infinite =
   SortedRange (ubiR (0 :: Integer)) < SortedRange (infR :: Range Integer)

-- The canonical display order: UpperBoundRange, SpanRange, LowerBoundRange
prop_sorted_display_order :: Bool
prop_sorted_display_order =
   sortOn SortedRange [lbiR 10, spanI (1 :: Integer) 5, ubeR 0]
   == [ubeR 0, spanI 1 5, lbiR 10]

-- SingletonRange 5 and 5 +=+ 5 occupy the same position so compare as EQ
prop_sorted_singleton_eq_degenerate_span :: Bool
prop_sorted_singleton_eq_degenerate_span =
   compare (SortedRange (SingletonRange (5 :: Integer)))
           (SortedRange (SpanRange (Bound 5 Inclusive) (Bound 5 Inclusive)))
   == EQ

test_sortedrange_unit :: Test
test_sortedrange_unit = testGroup "SortedRange unit"
   [ testProperty "UpperBoundRange before LowerBoundRange"  prop_sorted_upper_before_span
   , testProperty "InfiniteRange before LowerBoundRange"    prop_sorted_infinite_before_lower
   , testProperty "singletons ordered by value"             prop_sorted_singletons_by_value
   , testProperty "spans ordered by lower bound"            prop_sorted_spans_by_lower
   , testProperty "tiebreak by upper bound"                 prop_sorted_tiebreak_by_upper
   , testProperty "UpperBoundRange before InfiniteRange"    prop_sorted_upper_before_infinite
   , testProperty "sortOn gives display order"              prop_sorted_display_order
   , testProperty "singleton equals degenerate span"        prop_sorted_singleton_eq_degenerate_span
   ]

-- ---------------------------------------------------------------------------
-- SortedRange: QuickCheck properties
-- ---------------------------------------------------------------------------

prop_sorted_reflexive :: Range Integer -> Bool
prop_sorted_reflexive r = compare (SortedRange r) (SortedRange r) == EQ

prop_sorted_eq_ord_consistent :: Range Integer -> Range Integer -> Bool
prop_sorted_eq_ord_consistent x y = sortEqOrdConsistent (SortedRange x) (SortedRange y)

prop_sorted_antisymmetric :: Range Integer -> Range Integer -> Bool
prop_sorted_antisymmetric x y =
   case compare (SortedRange x) (SortedRange y) of
      LT -> compare (SortedRange y) (SortedRange x) == GT
      GT -> compare (SortedRange y) (SortedRange x) == LT
      EQ -> compare (SortedRange y) (SortedRange x) == EQ

-- Sorting twice is idempotent
prop_sorted_sort_idempotent :: [Range Integer] -> Bool
prop_sorted_sort_idempotent rs =
   sortOn SortedRange (sortOn SortedRange rs) == sortOn SortedRange rs

test_sortedrange_properties :: Test
test_sortedrange_properties = testGroup "SortedRange properties"
   [ testProperty "reflexive"             prop_sorted_reflexive
   , testProperty "Eq/Ord consistent"     prop_sorted_eq_ord_consistent
   , testProperty "antisymmetric"         prop_sorted_antisymmetric
   , testProperty "sort is idempotent"    prop_sorted_sort_idempotent
   ]

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

rangeOrdTestCases :: [Test]
rangeOrdTestCases =
   [ test_keyrange_unit
   , test_keyrange_properties
   , test_sortedrange_unit
   , test_sortedrange_properties
   ]
