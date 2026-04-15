module Main where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Test.Tasty.Bench

import Data.Ranges
import qualified Data.Range.Algebra as Alg

-- ---------------------------------------------------------------------------
-- Input generators
-- ---------------------------------------------------------------------------

-- | N disjoint spans: [0,1], [3,4], [6,7], ...
disjointSpans :: Int -> [Range Integer]
disjointSpans n =
  [ SpanRange (Bound (fromIntegral (i * 3)) Inclusive) (Bound (fromIntegral (i * 3 + 1)) Inclusive)
  | i <- [0 .. n - 1]
  ]

-- | N fully overlapping spans all starting near 0 and ending far out
overlappingSpans :: Int -> [Range Integer]
overlappingSpans n =
  [ SpanRange (Bound (fromIntegral i) Inclusive) (Bound (fromIntegral (i + 1000)) Inclusive)
  | i <- [0 .. n - 1]
  ]

-- | N disjoint spans offset by 500000 (no overlap with disjointSpans)
offsetSpans :: Int -> [Range Integer]
offsetSpans n =
  [ SpanRange (Bound (fromIntegral (i * 3) + 500000) Inclusive) (Bound (fromIntegral (i * 3 + 1) + 500000) Inclusive)
  | i <- [0 .. n - 1]
  ]

-- | A pre-merged Ranges (already normalised)
mergedInput :: Int -> Ranges Integer
mergedInput = mergeRanges . disjointSpans

-- | A pre-merged offset Ranges (for disjoint intersection benchmarks)
offsetMerged :: Int -> Ranges Integer
offsetMerged = mergeRanges . offsetSpans

-- | Pre-merged overlapping Ranges
overlappingMerged :: Int -> Ranges Integer
overlappingMerged = mergeRanges . overlappingSpans

-- | Equivalent enumerated list for elem comparison
elemList :: Int -> [Integer]
elemList n = concatMap (\i -> [fromIntegral (i * 3) .. fromIntegral (i * 3 + 1)]) [0 .. n - 1]

-- | Build a left-skewed union tree of N singleton ranges via the Algebra
unionTree :: Int -> Alg.RangeExpr [Range Integer]
unionTree n = foldl1 Alg.union [Alg.const [SingletonRange (fromIntegral i)] | i <- [1 .. n :: Int]]

-- | Build a left-skewed intersection tree of N overlapping span ranges via the Algebra
intersectionTree :: Int -> Alg.RangeExpr [Range Integer]
intersectionTree n = foldl1 Alg.intersection
  [ Alg.const [ SpanRange (Bound (fromIntegral (i * 2)) Inclusive)
                           (Bound (fromIntegral (i * 2 + 100)) Inclusive) ]
  | i <- [1 .. n :: Int]
  ]

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  -- Pre-evaluate all inputs so construction cost is excluded from benchmarks
  ds10    <- evaluate . force $ disjointSpans 10
  ds100   <- evaluate . force $ disjointSpans 100
  ds1000  <- evaluate . force $ disjointSpans 1000
  os10    <- evaluate . force $ overlappingSpans 10
  os100   <- evaluate . force $ overlappingSpans 100
  os1000  <- evaluate . force $ overlappingSpans 1000
  ms10    <- evaluate . force $ mergedInput 10
  ms100   <- evaluate . force $ mergedInput 100
  ms1000  <- evaluate . force $ mergedInput 1000
  ms10000 <- evaluate . force $ mergedInput 10000
  off10   <- evaluate . force $ offsetMerged 10
  off100  <- evaluate . force $ offsetMerged 100
  off1000 <- evaluate . force $ offsetMerged 1000
  oms10   <- evaluate . force $ overlappingMerged 10
  oms100  <- evaluate . force $ overlappingMerged 100
  oms1000 <- evaluate . force $ overlappingMerged 1000
  el1000  <- evaluate . force $ elemList 1000
  el10000 <- evaluate . force $ elemList 10000

  defaultMain
    [ bgroup "point-queries"
        [ bgroup "inRange"
            [ bench "SpanRange"       $ whnf (inRange (SpanRange (Bound 1 Inclusive) (Bound 1000000 Inclusive)))      (500000 :: Integer)
            , bench "LowerBoundRange" $ whnf (inRange (LowerBoundRange (Bound 0 Inclusive)))                          (999999 :: Integer)
            , bench "UpperBoundRange" $ whnf (inRange (UpperBoundRange (Bound 1000000 Inclusive)))                    (1 :: Integer)
            , bench "SingletonRange"  $ whnf (inRange (SingletonRange 42))                                            (42 :: Integer)
            , bench "InfiniteRange"   $ whnf (inRange (InfiniteRange :: Range Integer))                               0
            ]
        , bgroup "inRanges/disjoint-spans"
            [ bench "10"    $ whnf (inRanges ms10)    29
            , bench "100"   $ whnf (inRanges ms100)   299
            , bench "1000"  $ whnf (inRanges ms1000)  2999
            , bench "10000" $ whnf (inRanges ms10000) 29999
            ]
        , bgroup "inRanges/vs-elem"
            -- Checking for the last element — worst case for both
            [ bench "inRanges-1000"  $ whnf (inRanges ms1000)  2998
            , bench "elem-1000"      $ whnf (elem (2998 :: Integer)) el1000
            , bench "inRanges-10000" $ whnf (inRanges ms10000) 29998
            , bench "elem-10000"     $ whnf (elem (29998 :: Integer)) el10000
            ]
        , bgroup "aboveRanges/disjoint-spans"
            [ bench "10"   $ whnf (aboveRanges ms10)   10000
            , bench "100"  $ whnf (aboveRanges ms100)  10000
            , bench "1000" $ whnf (aboveRanges ms1000) 10000
            ]
        , bgroup "belowRanges/disjoint-spans"
            [ bench "10"   $ whnf (belowRanges ms10)   (-1)
            , bench "100"  $ whnf (belowRanges ms100)  (-1)
            , bench "1000" $ whnf (belowRanges ms1000) (-1)
            ]
        ]

    , bgroup "set-operations"
        [ bgroup "mergeRanges/already-merged"
            [ bench "10"   $ nf mergeRanges ds10
            , bench "100"  $ nf mergeRanges ds100
            , bench "1000" $ nf mergeRanges ds1000
            ]
        , bgroup "mergeRanges/fully-overlapping"
            [ bench "10"   $ nf mergeRanges os10
            , bench "100"  $ nf mergeRanges os100
            , bench "1000" $ nf mergeRanges os1000
            ]
        , bgroup "mergeRanges/disjoint"
            [ bench "10"   $ nf mergeRanges ds10
            , bench "100"  $ nf mergeRanges ds100
            , bench "1000" $ nf mergeRanges ds1000
            ]
        , bgroup "union"
            [ bench "10"   $ nf (union ms10)   ms10
            , bench "100"  $ nf (union ms100)  ms100
            , bench "1000" $ nf (union ms1000) ms1000
            ]
        , bgroup "intersection/disjoint"
            -- Two pre-merged sets offset so they share no values — result is empty
            [ bench "10"   $ nf (intersection ms10)   off10
            , bench "100"  $ nf (intersection ms100)  off100
            , bench "1000" $ nf (intersection ms1000) off1000
            ]
        , bgroup "intersection/overlapping"
            [ bench "10"   $ nf (intersection oms10)   oms10
            , bench "100"  $ nf (intersection oms100)  oms100
            , bench "1000" $ nf (intersection oms1000) oms1000
            ]
        , bgroup "difference"
            [ bench "10"   $ nf (difference ms10)   ms10
            , bench "100"  $ nf (difference ms100)  ms100
            , bench "1000" $ nf (difference ms1000) ms1000
            ]
        , bgroup "invert"
            [ bench "10"   $ nf invert ms10
            , bench "100"  $ nf invert ms100
            , bench "1000" $ nf invert ms1000
            ]
        ]

    , bgroup "construction-conversion"
        [ bgroup "fromRanges/take-N"
            [ bench "take-100"   $ nf (take 100   . fromRanges) ms10
            , bench "take-1000"  $ nf (take 1000  . fromRanges) ms10
            , bench "take-10000" $ nf (take 10000 . fromRanges) ms10
            ]
        , bgroup "joinRanges/adjacent"
            [ bench "10"   $ nf joinRanges ms10
            , bench "100"  $ nf joinRanges ms100
            , bench "1000" $ nf joinRanges ms1000
            ]
        ]

    , bgroup "algebra"
        [ bgroup "eval/union-tree"
            [ bench "5"  $ nf Alg.eval (unionTree 5)
            , bench "10" $ nf Alg.eval (unionTree 10)
            , bench "20" $ nf Alg.eval (unionTree 20)
            ]
        , bgroup "eval/intersection-tree"
            [ bench "5"  $ nf Alg.eval (intersectionTree 5)
            , bench "10" $ nf Alg.eval (intersectionTree 10)
            , bench "20" $ nf Alg.eval (intersectionTree 20)
            ]
        ]
    ]
