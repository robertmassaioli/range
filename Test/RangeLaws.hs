module Test.RangeLaws
   ( rangeLawTestCases
   ) where

import Test.Framework (Test, testGroup)
import Test.QuickCheck
import Test.Framework.Providers.QuickCheck2

import Data.Range
import Test.Generators ()

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Ranges is always in canonical form; compare the underlying lists.
eq :: Ord a => Ranges a -> Ranges a -> Bool
eq a b = unRanges a == unRanges b

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------

prop_mergeRanges_idempotent :: Ranges Integer -> Bool
prop_mergeRanges_idempotent xs =
   mergeRanges (unRanges xs) `eq` xs

prop_union_idempotent :: Ranges Integer -> Bool
prop_union_idempotent xs =
   union xs xs `eq` xs

prop_intersection_idempotent :: Ranges Integer -> Bool
prop_intersection_idempotent xs =
   intersection xs xs `eq` xs

test_idempotency :: Test
test_idempotency = testGroup "idempotency"
   [ testProperty "mergeRanges is idempotent"       prop_mergeRanges_idempotent
   , testProperty "union with self is self"          prop_union_idempotent
   , testProperty "intersection with self is self"   prop_intersection_idempotent
   ]

-- ---------------------------------------------------------------------------
-- Commutativity
-- ---------------------------------------------------------------------------

prop_union_commutative :: (Ranges Integer, Ranges Integer) -> Bool
prop_union_commutative (a, b) =
   union a b `eq` union b a

prop_intersection_commutative :: (Ranges Integer, Ranges Integer) -> Bool
prop_intersection_commutative (a, b) =
   intersection a b `eq` intersection b a

test_commutativity :: Test
test_commutativity = testGroup "commutativity"
   [ testProperty "union is commutative"         prop_union_commutative
   , testProperty "intersection is commutative"  prop_intersection_commutative
   ]

-- ---------------------------------------------------------------------------
-- Associativity
-- ---------------------------------------------------------------------------

prop_union_associative :: (Ranges Integer, Ranges Integer, Ranges Integer) -> Bool
prop_union_associative (a, b, c) =
   union (union a b) c `eq` union a (union b c)

prop_intersection_associative :: (Ranges Integer, Ranges Integer, Ranges Integer) -> Bool
prop_intersection_associative (a, b, c) =
   intersection (intersection a b) c `eq` intersection a (intersection b c)

test_associativity :: Test
test_associativity = testGroup "associativity"
   [ testProperty "union is associative"         prop_union_associative
   , testProperty "intersection is associative"  prop_intersection_associative
   ]

-- ---------------------------------------------------------------------------
-- Distributivity
-- ---------------------------------------------------------------------------

prop_intersection_distributes_over_union
   :: (Ranges Integer, Ranges Integer, Ranges Integer) -> Bool
prop_intersection_distributes_over_union (a, b, c) =
   intersection a (union b c) `eq` union (intersection a b) (intersection a c)

prop_union_distributes_over_intersection
   :: (Ranges Integer, Ranges Integer, Ranges Integer) -> Bool
prop_union_distributes_over_intersection (a, b, c) =
   union a (intersection b c) `eq` intersection (union a b) (union a c)

test_distributivity :: Test
test_distributivity = testGroup "distributivity"
   [ testProperty "intersection distributes over union"
         prop_intersection_distributes_over_union
   , testProperty "union distributes over intersection"
         prop_union_distributes_over_intersection
   ]

-- ---------------------------------------------------------------------------
-- Identity laws
-- ---------------------------------------------------------------------------

prop_union_identity_empty :: Ranges Integer -> Bool
prop_union_identity_empty xs =
   union xs mempty `eq` xs

prop_intersection_identity_infinite :: Ranges Integer -> Bool
prop_intersection_identity_infinite xs =
   intersection xs inf `eq` xs

prop_union_absorb_infinite :: Ranges Integer -> Bool
prop_union_absorb_infinite xs =
   union xs inf `eq` inf

prop_intersection_absorb_empty :: Ranges Integer -> Bool
prop_intersection_absorb_empty xs =
   intersection xs mempty `eq` mempty

test_identity_absorption :: Test
test_identity_absorption = testGroup "identity and absorption"
   [ testProperty "union with mempty is identity"                prop_union_identity_empty
   , testProperty "intersection with inf is identity"            prop_intersection_identity_infinite
   , testProperty "union with inf absorbs"                       prop_union_absorb_infinite
   , testProperty "intersection with mempty absorbs"             prop_intersection_absorb_empty
   ]

-- ---------------------------------------------------------------------------
-- Difference as intersection with complement
-- ---------------------------------------------------------------------------

prop_difference_eq_intersection_invert
   :: (Ranges Integer, Ranges Integer) -> Bool
prop_difference_eq_intersection_invert (a, b) =
   difference a b `eq` intersection a (invert b)

test_difference :: Test
test_difference = testGroup "difference"
   [ testProperty "difference a b == intersection a (invert b)"
         prop_difference_eq_intersection_invert
   ]

-- ---------------------------------------------------------------------------
-- Double inversion
-- ---------------------------------------------------------------------------

prop_invert_twice_identity :: Ranges Integer -> Bool
prop_invert_twice_identity xs =
   invert (invert xs) `eq` xs

test_invert :: Test
test_invert = testGroup "invert"
   [ testProperty "inverting twice is identity"  prop_invert_twice_identity
   ]

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

rangeLawTestCases :: [Test]
rangeLawTestCases =
   [ test_idempotency
   , test_commutativity
   , test_associativity
   , test_distributivity
   , test_identity_absorption
   , test_difference
   , test_invert
   ]
