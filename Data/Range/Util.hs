module Data.Range.Util where

-- This module is supposed to contain all of the functions that are required by the rest
-- of the code but could be easily pulled into separate and completely non-related
-- codebases or libraries.

insertionSort :: (Ord a) => (a -> a -> Ordering) -> [a] -> [a] -> [a]
insertionSort comp xs ys = go xs ys
   where
      go (f : fs) (s : ss) = case comp f s of 
         LT -> f : go fs (s : ss)
         EQ -> f : s : go fs ss
         GT -> s : go (f : fs) ss
      go [] xs = xs
      go xs [] = xs

isBetween :: (Ord a) => a -> (a, a) -> Bool
isBetween a (x, y) = (x <= a) && (a <= y)