{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-- Orphan instances are acceptable in test modules

module Test.Generators where

import Test.QuickCheck
import Control.Monad (liftM)

import Data.Range
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
            return $ first +=+ second
         generateLowerBound = liftM lbi arbitrarySizedIntegral
         generateUpperBound = liftM ubi arbitrarySizedIntegral
         generateInfiniteRange :: Gen (Range a)
         generateInfiniteRange = return InfiniteRange

instance (Num a, Integral a, Ord a, Enum a) => Arbitrary (Alg.RangeExpr [Range a]) where
  arbitrary = frequency
    [ (3, Alg.const <$> arbitrary)
    , (1, Alg.invert <$> arbitrary)
    , (1, Alg.union <$> arbitrary <*> arbitrary)
    , (1, Alg.intersection <$> arbitrary <*> arbitrary)
    , (1, Alg.difference <$> arbitrary <*> arbitrary)
    ]
