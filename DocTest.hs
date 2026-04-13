module Main (main) where

import Test.DocTest

main :: IO ()
main = doctest
   [ "Data/Range.hs"
   , "Data/Ranges.hs"
   , "Data/Range/Ord.hs"
   , "Data/Range/Parser.hs"
   , "Data/Range/Algebra.hs"
   ]
