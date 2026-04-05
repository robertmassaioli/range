# range - by Robert Massaioli

The range library is written in Haskell and it's purpose is to make it easy to deal with
ranges. For example you may have the following ranges:

    1-4, 6-23, 15-50, 90-

And you are given a value x, how do you know if the value x is in those ranges? That is
the question that this library answers. You just load your ranges using the library and then
you can query to see if values exist inside your ranges. This library aims to be as
efficient as light as possible while still being useful.

## Example Code

Here is a small example program written using this library:

``` haskell
module Main where

import Data.Range.Range

putStatus :: Bool -> String -> IO ()
putStatus result test = putStrLn $ "[" ++ (show result) ++ "] " ++ test

main = do
    inRanges [SingletonRange 4]   4                         `putStatus` "Singletons Match"
    inRanges [0 +=+ 10] 7                                   `putStatus` "Value in Range"
    inRanges [LowerBoundRange (Bound 80 Inclusive)] 12345   `putStatus` "Value in Long Range"
    inRanges [InfiniteRange]      8287423                   `putStatus` "Value in Infinite Range"
    inRanges [lbi 50, 1 +=+ 30] 44                          `putStatus` "NOT in Composite Range (expect false)"
```

If you wish to see a better example in a real program then you should check out [splitter][1].

## Installation Instructions

You can install the range library from Hackage using Cabal:

``` shell
cabal install range
```

If you wish to build from source using [Haskell Stack][2]:

``` shell
cd /path/to/haskell/range
stack build
```

To run the test suite:

``` shell
stack test
```

To run the benchmark suite:

``` shell
stack bench
```

For benchmark results in CSV format (useful for comparing across runs):

``` shell
stack bench --benchmark-arguments '--csv bench-results.csv'
```

And that is all that there is to it. I hope you enjoy using this library and make great
projects with it.

 [2]: https://docs.haskellstack.org/

 [1]: http://hackage.haskell.org/package/splitter