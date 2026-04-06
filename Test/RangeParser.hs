module Test.RangeParser
   ( rangeParserTestCases
   ) where

import Test.Framework (Test, testGroup)
import Test.QuickCheck
import Test.Framework.Providers.QuickCheck2

import Data.Range
import Data.Range.Parser

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

shouldParse :: String -> [Range Integer] -> Bool
shouldParse input expected = case parseRanges input of
   Right result -> result == expected
   Left _       -> False

shouldFail :: String -> Bool
shouldFail input = case (parseRanges input :: Either ParseError [Range Integer]) of
   Left _  -> True
   Right _ -> False

-- ---------------------------------------------------------------------------
-- Haddock example tests
-- ---------------------------------------------------------------------------

-- The example from the module documentation:
-- >>> parseRanges "-5,8-10,13-15,20-" :: Either ParseError [Range Integer]
-- Right [UpperBoundRange 5,SpanRange 8 10,SpanRange 13 15,LowerBoundRange 20]
prop_haddock_example :: Bool
prop_haddock_example = shouldParse "-5,8-10,13-15,20-"
   [ UpperBoundRange (Bound 5 Inclusive)
   , SpanRange (Bound 8 Inclusive) (Bound 10 Inclusive)
   , SpanRange (Bound 13 Inclusive) (Bound 15 Inclusive)
   , LowerBoundRange (Bound 20 Inclusive)
   ]

test_haddock :: Test
test_haddock = testGroup "haddock examples"
   [ testProperty "documented example parses correctly" prop_haddock_example
   ]

-- ---------------------------------------------------------------------------
-- Singleton ranges
-- ---------------------------------------------------------------------------

prop_parse_singleton :: Positive Integer -> Bool
prop_parse_singleton (Positive n) = shouldParse (show n) [SingletonRange n]

prop_parse_singleton_zero :: Bool
prop_parse_singleton_zero = shouldParse "0" [SingletonRange 0]

test_singletons :: Test
test_singletons = testGroup "singleton ranges"
   [ testProperty "positive integer parses as singleton" prop_parse_singleton
   , testProperty "zero parses as singleton" prop_parse_singleton_zero
   ]

-- ---------------------------------------------------------------------------
-- Span ranges
-- ---------------------------------------------------------------------------

prop_parse_span :: (Positive Integer, Positive Integer) -> Bool
prop_parse_span (Positive a, Positive b) =
   shouldParse (show a ++ "-" ++ show b)
      [SpanRange (Bound a Inclusive) (Bound b Inclusive)]

test_spans :: Test
test_spans = testGroup "span ranges"
   [ testProperty "a-b parses as span" prop_parse_span
   ]

-- ---------------------------------------------------------------------------
-- Bound ranges
-- ---------------------------------------------------------------------------

prop_parse_lower_bound :: Positive Integer -> Bool
prop_parse_lower_bound (Positive n) =
   shouldParse (show n ++ "-") [LowerBoundRange (Bound n Inclusive)]

prop_parse_upper_bound :: Positive Integer -> Bool
prop_parse_upper_bound (Positive n) =
   shouldParse ("-" ++ show n) [UpperBoundRange (Bound n Inclusive)]

test_bounds :: Test
test_bounds = testGroup "bound ranges"
   [ testProperty "n- parses as lower bound" prop_parse_lower_bound
   , testProperty "-n parses as upper bound" prop_parse_upper_bound
   ]

-- ---------------------------------------------------------------------------
-- Wildcard / infinite range
-- ---------------------------------------------------------------------------

prop_parse_wildcard :: Bool
prop_parse_wildcard = shouldParse "*" [InfiniteRange]

prop_parse_wildcard_in_union :: Bool
prop_parse_wildcard_in_union = shouldParse "*,5"
   [InfiniteRange, SingletonRange 5]

test_wildcard :: Test
test_wildcard = testGroup "wildcard / infinite range"
   [ testProperty "* parses as InfiniteRange" prop_parse_wildcard
   , testProperty "* in union parses correctly" prop_parse_wildcard_in_union
   ]

-- ---------------------------------------------------------------------------
-- Union (comma-separated)
-- ---------------------------------------------------------------------------

prop_parse_union :: Bool
prop_parse_union = shouldParse "1,2,3"
   [SingletonRange 1, SingletonRange 2, SingletonRange 3]

prop_parse_mixed_union :: Bool
prop_parse_mixed_union = shouldParse "5,10-20,30-"
   [ SingletonRange 5
   , SpanRange (Bound 10 Inclusive) (Bound 20 Inclusive)
   , LowerBoundRange (Bound 30 Inclusive)
   ]

test_union :: Test
test_union = testGroup "union (comma-separated)"
   [ testProperty "singletons separated by commas" prop_parse_union
   , testProperty "mixed types separated by commas" prop_parse_mixed_union
   ]

-- ---------------------------------------------------------------------------
-- Edge cases and invalid inputs
-- ---------------------------------------------------------------------------

prop_empty_string_parses :: Bool
prop_empty_string_parses = case (parseRanges "" :: Either ParseError [Range Integer]) of
   Right [] -> True
   _        -> False

-- The parser uses sepBy which returns [] on no matches,
-- so non-range input like "abc" or "-" parses as Right [].
-- This is a known limitation of the current parser design.
prop_non_range_input_parses_empty :: Bool
prop_non_range_input_parses_empty =
   case (parseRanges "abc" :: Either ParseError [Range Integer]) of
      Right [] -> True
      _        -> False

test_edge_cases :: Test
test_edge_cases = testGroup "edge cases"
   [ testProperty "empty string produces empty list" prop_empty_string_parses
   , testProperty "non-range input produces empty list" prop_non_range_input_parses_empty
   ]

-- ---------------------------------------------------------------------------
-- Custom parser args
-- ---------------------------------------------------------------------------

prop_custom_separators :: Bool
prop_custom_separators =
   let args = defaultArgs { unionSeparator = ";", rangeSeparator = ".." }
       result = customParseRanges args "1..5;10" :: Either ParseError [Range Integer]
   in case result of
      Right ranges -> ranges ==
         [ SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive)
         , SingletonRange 10
         ]
      Left _ -> False

test_custom :: Test
test_custom = testGroup "custom parser args"
   [ testProperty "custom separators work" prop_custom_separators
   ]

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

rangeParserTestCases :: [Test]
rangeParserTestCases =
   [ test_haddock
   , test_singletons
   , test_spans
   , test_bounds
   , test_wildcard
   , test_union
   , test_edge_cases
   , test_custom
   ]
