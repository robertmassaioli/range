{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-- Orphan instances are acceptable in test modules

module Test.Generators where

import Test.QuickCheck
import Control.Monad (liftM)

import Data.Ranges
import qualified Data.Range.Algebra as Alg

instance (Num a, Integral a, Ord a, Enum a) => Arbitrary (Range a) where
   arbitrary = oneof
      [ generateSingleton
      , generateSpan
      , generateLowerBound
      , generateUpperBound
      , generateInfiniteRange
      ]
      where
         generateSingleton = liftM SingletonRange arbitrarySizedIntegral
         generateSpan = do
            first <- arbitrarySizedIntegral
            second <- arbitrarySizedIntegral `suchThat` (> first)
            return $ SpanRange (Bound first Inclusive) (Bound second Inclusive)
         generateLowerBound = liftM (\x -> LowerBoundRange (Bound x Inclusive)) arbitrarySizedIntegral
         generateUpperBound = liftM (\x -> UpperBoundRange (Bound x Inclusive)) arbitrarySizedIntegral
         generateInfiniteRange :: Gen (Range a)
         generateInfiniteRange = return InfiniteRange

instance (Num a, Integral a, Ord a, Enum a) => Arbitrary (Ranges a) where
  arbitrary = mergeRanges <$> listOf arbitrary

instance (Num a, Integral a, Ord a, Enum a) => Arbitrary (Alg.RangeExpr [Range a]) where
  arbitrary = frequency
    [ (3, Alg.const <$> arbitrary)
    , (1, Alg.invert <$> arbitrary)
    , (1, Alg.union <$> arbitrary <*> arbitrary)
    , (1, Alg.intersection <$> arbitrary <*> arbitrary)
    , (1, Alg.difference <$> arbitrary <*> arbitrary)
    ]
