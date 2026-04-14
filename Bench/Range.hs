module Main where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Test.Tasty.Bench

import Data.Range
import qualified Data.Range.Algebra as Alg

-- ---------------------------------------------------------------------------
-- Input generators
-- ---------------------------------------------------------------------------

-- | N disjoint spans: [0,1], [3,4], [6,7], ...
disjointSpans :: Int -> [Range Integer]
disjointSpans n = [fromIntegral (i * 3) +=+ fromIntegral (i * 3 + 1) | i <- [0 .. n - 1]]

-- | N fully overlapping spans all starting near 0 and ending far out
overlappingSpans :: Int -> [Range Integer]
overlappingSpans n = [fromIntegral i +=+ fromIntegral (i + 1000) | i <- [0 .. n - 1]]

-- | A pre-merged range list (already normalised)
mergedInput :: Int -> [Range Integer]
mergedInput = mergeRanges . disjointSpans

-- | Equivalent enumerated list for elem comparison
elemList :: Int -> [Integer]
elemList n = concatMap (\i -> [fromIntegral (i * 3) .. fromIntegral (i * 3 + 1)]) [0 .. n - 1]

-- | Build a left-skewed union tree of N singleton ranges via the Algebra
unionTree :: Int -> Alg.RangeExpr [Range Integer]
unionTree n = foldl1 Alg.union [Alg.const [SingletonRange (fromIntegral i)] | i <- [1 .. n :: Int]]

-- | Build a left-skewed intersection tree of N overlapping span ranges via the Algebra
intersectionTree :: Int -> Alg.RangeExpr [Range Integer]
intersectionTree n = foldl1 Alg.intersection
  [Alg.const [fromIntegral (i * 2) +=+ fromIntegral (i * 2 + 100)] | i <- [1 .. n :: Int]]

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  -- Pre-evaluate all inputs so construction cost is excluded from benchmarks
  ds10    <- evaluate . force $ disjointSpans 10
  ds100   <- evaluate . force $ disjointSpans 100
  ds1000  <- evaluate . force $ disjointSpans 1000
  ds10000 <- evaluate . force $ disjointSpans 10000
  os10    <- evaluate . force $ overlappingSpans 10
  os100   <- evaluate . force $ overlappingSpans 100
  os1000  <- evaluate . force $ overlappingSpans 1000
  ms10    <- evaluate . force $ mergedInput 10
  ms100   <- evaluate . force $ mergedInput 100
  ms1000  <- evaluate . force $ mergedInput 1000
  el1000  <- evaluate . force $ elemList 1000
  el10000 <- evaluate . force $ elemList 10000

  defaultMain
    [ bgroup "point-queries"
        [ bgroup "inRange"
            [ bench "SpanRange"       $ whnf (inRange (1 +=+ 1000000))        (500000 :: Integer)
            , bench "LowerBoundRange" $ whnf (inRange (lbi 0))                (999999 :: Integer)
            , bench "UpperBoundRange" $ whnf (inRange (ubi 1000000))          (1 :: Integer)
            , bench "SingletonRange"  $ whnf (inRange (SingletonRange 42))    (42 :: Integer)
            , bench "InfiniteRange"   $ whnf (inRange (InfiniteRange :: Range Integer)) 0
            ]
        , bgroup "inRanges/disjoint-spans"
            [ bench "10"    $ whnf (inRanges ds10)    29
            , bench "100"   $ whnf (inRanges ds100)   299
            , bench "1000"  $ whnf (inRanges ds1000)  2999
            , bench "10000" $ whnf (inRanges ds10000) 29999
            ]
        , bgroup "inRanges/vs-elem"
            -- Checking for the last element — worst case for both
            [ bench "inRanges-1000"  $ whnf (inRanges ds1000)  2998
            , bench "elem-1000"      $ whnf (elem (2998 :: Integer)) el1000
            , bench "inRanges-10000" $ whnf (inRanges ds10000) 29998
            , bench "elem-10000"     $ whnf (elem (29998 :: Integer)) el10000
            ]
        , bgroup "aboveRanges/disjoint-spans"
            [ bench "10"   $ whnf (aboveRanges ds10)   10000
            , bench "100"  $ whnf (aboveRanges ds100)  10000
            , bench "1000" $ whnf (aboveRanges ds1000) 10000
            ]
        , bgroup "belowRanges/disjoint-spans"
            [ bench "10"   $ whnf (belowRanges ds10)   (-1)
            , bench "100"  $ whnf (belowRanges ds100)  (-1)
            , bench "1000" $ whnf (belowRanges ds1000) (-1)
            ]
        ]

    , bgroup "set-operations"
        [ bgroup "mergeRanges/already-merged"
            [ bench "10"   $ nf mergeRanges ms10
            , bench "100"  $ nf mergeRanges ms100
            , bench "1000" $ nf mergeRanges ms1000
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
            -- Two sets offset so they don't overlap — result is empty
            [ bench "10"   $ nf (intersection ms10)   (fmap (fmap (+500000)) ms10)
            , bench "100"  $ nf (intersection ms100)  (fmap (fmap (+500000)) ms100)
            , bench "1000" $ nf (intersection ms1000) (fmap (fmap (+500000)) ms1000)
            ]
        , bgroup "intersection/overlapping"
            [ bench "10"   $ nf (intersection os10)   os10
            , bench "100"  $ nf (intersection os100)  os100
            , bench "1000" $ nf (intersection os1000) os1000
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
            [ bench "take-100"   $ nf (take 100   . fromRanges) ds10
            , bench "take-1000"  $ nf (take 1000  . fromRanges) ds10
            , bench "take-10000" $ nf (take 10000 . fromRanges) ds10
            ]
        , bgroup "joinRanges/adjacent"
            [ bench "10"   $ nf joinRanges ds10
            , bench "100"  $ nf joinRanges ds100
            , bench "1000" $ nf joinRanges ds1000
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
