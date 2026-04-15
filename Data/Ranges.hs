{-# LANGUAGE Safe #-}

-- | The primary interface to the range library.
--
-- A 'Range' describes a membership set over any 'Ord' type. This module
-- provides the 'Ranges' type — a canonicalised, indexed collection of
-- 'Range' values — along with construction operators, set operations, and
-- membership predicates.
--
-- = Quick start
--
-- Build ranges with the construction operators and combine them with @('<>')@:
--
-- >>> (1 +=+ 5 :: Ranges Integer) <> (3 +=+ 8)
-- Ranges [1 +=+ 8]
--
-- Test membership:
--
-- >>> inRanges (1 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 5
-- True
-- >>> inRanges (1 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 15
-- False
--
-- Use 'mconcat' to build from a list:
--
-- >>> mconcat [1 +=+ 5, 10 +=+ 15, 12 +=+ 20 :: Ranges Integer]
-- Ranges [1 +=+ 5,10 +=+ 20]
--
-- = Transforming ranges
--
-- 'Ranges' does not implement 'Functor'. Mapping a function over boundary
-- values is not a well-defined operation for half-infinite ranges: an
-- order-reversing function like @negate@ applied to 'lbi' would need to
-- produce 'ubi', but 'Functor' cannot express that structural flip.
--
-- The idiomatic alternative is to __map the query value__, not the ranges.
-- Instead of converting boundaries to a new domain, convert incoming queries
-- back to the range's domain:
--
-- @
-- -- Unit conversion: test a Fahrenheit value against Celsius ranges
-- let safeTemp = 20 +=+ 37 :: Ranges Double  -- defined in °C
-- let inSafeTemp f = inRanges safeTemp ((f - 32) * 5 / 9)
-- @
--
-- This is always correct regardless of whether the conversion is monotone,
-- never requires re-canonicalisation, and avoids the constructor-flip hazard.
--
-- = Module guide
--
-- * "Data.Ranges" — __start here__. 'Ranges' type, all set operations.
-- * "Data.Range" — deprecated re-export shim; use "Data.Ranges" instead.
-- * "Data.Range.Ord" — 'Data.Range.Ord.KeyRange' and 'Data.Range.Ord.SortedRange' for 'Ord'-requiring contexts.
-- * "Data.Range.Parser" — Parsec-based parser for range strings.
-- * "Data.Range.Algebra" — F-Algebra for deferred, efficient expression trees.
module Data.Ranges (
  -- * Core types
  Range(..),
  Bound(..),
  BoundType(..),
  -- * The Ranges type
  Ranges(unRanges),
  -- * Range creation
  -- $creation
  (+=+),
  (+=*),
  (*=+),
  (*=*),
  lbi,
  lbe,
  ubi,
  ube,
  inf,
  -- * Single-range predicates
  inRange,
  aboveRange,
  belowRange,
  rangesOverlap,
  rangesAdjoin,
  -- * Multi-range predicates
  inRanges,
  aboveRanges,
  belowRanges,
  -- * Set operations
  mergeRanges,
  union,
  intersection,
  difference,
  invert,
  -- * Enumerable methods
  fromRanges,
  joinRanges
) where

-- $setup
-- >>> import Data.Ranges
-- >>> import Data.Foldable (fold)

import Control.DeepSeq (NFData, rnf)

import Data.Range.Data
import Data.Range.Util
  ( againstLowerBound, againstUpperBound, boundIsBetween, boundsOverlapType
  , invertBound, pointJoinType, takeEvenly
  )
import Data.Range.RangeInternal
  ( loadRanges, exportRangeMerge, joinRM, buildSpanQuery
  , RangeMerge(..)
  )
import qualified Data.Range.Operators as Op
import qualified Data.Range.Algebra as Alg

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | Build an O(log n) membership predicate from a canonical range list.
buildQuery :: Ord a => [Range a] -> a -> Bool
buildQuery rs = case loadRanges rs of
  IRM            -> const True
  RM lb ub spans -> buildSpanQuery lb ub spans

-- | Smart constructor. Canonicalises the range list and pre-builds the
-- membership predicate. Every 'Ranges' value in this module is produced
-- through this function.
mkRanges :: Ord a => [Range a] -> Ranges a
mkRanges xs =
  let canonical = Alg.eval $ Alg.union (Alg.const []) (Alg.const xs)
  in Ranges canonical (buildQuery canonical)

-- ---------------------------------------------------------------------------
-- The Ranges type
-- ---------------------------------------------------------------------------

-- $creation
-- Each operator constructs a single-element 'Ranges'. Because 'Ranges' is a
-- 'Semigroup', you can combine them directly with '<>':
--
-- >>> (1 +=+ 5 :: Ranges Integer) <> (3 +=+ 8)
-- Ranges [1 +=+ 8]
--
-- The operators mirror those in "Data.Range.Operators" but return 'Ranges'
-- instead of 'Range', so they compose naturally without wrapping.

-- | A set of ranges represented as a merged, canonical list of
-- non-overlapping 'Range' values, with a pre-built O(log n) membership
-- predicate.
--
-- Construct values with the operators ('+=+', 'lbi', etc.) or with
-- 'mergeRanges'. Combine with @('<>')@ or 'mconcat'.
--
-- __Semigroup__: @('<>')@ computes the set union and merges the result into
-- canonical form.
--
-- >>> (1 +=+ 5 :: Ranges Integer) <> (3 +=+ 8)
-- Ranges [1 +=+ 8]
--
-- __Monoid__: 'mempty' is the empty set. 'mconcat' merges an entire list in a
-- single pass, more efficiently than repeated @('<>')@:
--
-- >>> mconcat [1 +=+ 5, 10 +=+ 15, 12 +=+ 20 :: Ranges Integer]
-- Ranges [1 +=+ 5,10 +=+ 20]
--
-- Use 'unRanges' to extract the underlying list.
data Ranges a = Ranges
  { unRanges     :: [Range a]  -- ^ The canonical (sorted, non-overlapping) list.
  , _rangesQuery :: a -> Bool  -- ^ Cached O(log n) membership predicate.
  }

-- | Two 'Ranges' values are equal when their canonical range lists are equal.
instance Eq a => Eq (Ranges a) where
  a == b = unRanges a == unRanges b

instance Show a => Show (Ranges a) where
  showsPrec i r = showParen (i > 10) $ ("Ranges " ++) . shows (unRanges r)

-- | Forces the canonical range list; the cached predicate closure is not
-- forced (it is derived from the list and adds no new thunks).
instance NFData a => NFData (Ranges a) where
  rnf r = rnf (unRanges r)

instance Ord a => Semigroup (Ranges a) where
  (<>) a b = mkRanges (unRanges a ++ unRanges b)

-- | Evaluates a 'Alg.RangeExpr' tree whose leaves are 'Ranges' values,
-- producing a canonicalised 'Ranges' with a pre-built membership predicate.
--
-- This is the primary evaluation target for user-facing algebra expressions.
-- The implementation converts leaves to @['Range' a]@ internally, folds the
-- tree in a single @'RangeMerge'@ pass (the same efficient path as the
-- @['Range' a]@ instance), then wraps the result with 'mkRanges'.
instance (Ord a) => Alg.RangeAlgebra (Ranges a) where
  eval expr = mkRanges (Alg.eval (fmap unRanges expr))

instance Ord a => Monoid (Ranges a) where
  mempty  = mkRanges []
  mconcat = mkRanges . concatMap unRanges

-- ---------------------------------------------------------------------------
-- Construction operators
-- ---------------------------------------------------------------------------

-- | Mathematically equivalent to @[x, y]@. See 'SpanRange' for the
-- underlying constructor.
--
-- >>> 1 +=+ 5 :: Ranges Integer
-- Ranges [1 +=+ 5]
(+=+) :: Ord a => a -> a -> Ranges a
(+=+) a b = mkRanges [(Op.+=+) a b]

-- | Mathematically equivalent to @[x, y)@.
--
-- >>> 1 +=* 5 :: Ranges Integer
-- Ranges [1 +=* 5]
(+=*) :: Ord a => a -> a -> Ranges a
(+=*) a b = mkRanges [(Op.+=*) a b]

-- | Mathematically equivalent to @(x, y]@.
--
-- >>> 1 *=+ 5 :: Ranges Integer
-- Ranges [1 *=+ 5]
(*=+) :: Ord a => a -> a -> Ranges a
(*=+) a b = mkRanges [(Op.*=+) a b]

-- | Mathematically equivalent to @(x, y)@.
--
-- >>> 1 *=* 5 :: Ranges Integer
-- Ranges [1 *=* 5]
(*=*) :: Ord a => a -> a -> Ranges a
(*=*) a b = mkRanges [(Op.*=*) a b]

-- | Mathematically equivalent to @[x, ∞)@.
--
-- >>> lbi 5 :: Ranges Integer
-- Ranges [lbi 5]
lbi :: Ord a => a -> Ranges a
lbi = mkRanges . (:[]) . Op.lbi

-- | Mathematically equivalent to @(x, ∞)@.
lbe :: Ord a => a -> Ranges a
lbe = mkRanges . (:[]) . Op.lbe

-- | Mathematically equivalent to @(−∞, x]@.
ubi :: Ord a => a -> Ranges a
ubi = mkRanges . (:[]) . Op.ubi

-- | Mathematically equivalent to @(−∞, x)@.
ube :: Ord a => a -> Ranges a
ube = mkRanges . (:[]) . Op.ube

-- | The infinite range, covering all values.
inf :: Ord a => Ranges a
inf = mkRanges [Op.inf]

-- ---------------------------------------------------------------------------
-- Single-range predicates
-- ---------------------------------------------------------------------------

-- | Returns 'True' if the value falls within the single range.
-- Respects 'Inclusive' and 'Exclusive' bounds.
--
-- See 'inRanges' for testing against a 'Ranges' collection.
--
-- >>> inRange (SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive)) (5 :: Integer)
-- True
-- >>> inRange (SpanRange (Bound 1 Inclusive) (Bound 10 Exclusive)) (10 :: Integer)
-- False
inRange :: Ord a => Range a -> a -> Bool
inRange (SingletonRange a)      value = value == a
inRange (SpanRange x y)         value = Overlap == boundIsBetween (Bound value Inclusive) (x, y)
inRange (LowerBoundRange lower) value = Overlap == againstLowerBound (Bound value Inclusive) lower
inRange (UpperBoundRange upper) value = Overlap == againstUpperBound (Bound value Inclusive) upper
inRange InfiniteRange           _     = True

-- | Returns 'True' if the value is strictly above (greater than the upper
-- bound of) the given range.
--
-- >>> aboveRange (SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive)) (6 :: Integer)
-- True
-- >>> aboveRange (LowerBoundRange (Bound 0 Inclusive)) (6 :: Integer)
-- False
aboveRange :: Ord a => Range a -> a -> Bool
aboveRange (SingletonRange a)      value = value > a
aboveRange (SpanRange _ y)         value = Overlap == againstLowerBound (Bound value Inclusive) (invertBound y)
aboveRange (LowerBoundRange _)     _     = False
aboveRange (UpperBoundRange upper) value = Overlap == againstLowerBound (Bound value Inclusive) (invertBound upper)
aboveRange InfiniteRange           _     = False

-- | Returns 'True' if the value is strictly below (less than the lower
-- bound of) the given range.
--
-- >>> belowRange (SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive)) (0 :: Integer)
-- True
-- >>> belowRange (UpperBoundRange (Bound 6 Inclusive)) (0 :: Integer)
-- False
belowRange :: Ord a => Range a -> a -> Bool
belowRange (SingletonRange a)      value = value < a
belowRange (SpanRange x _)         value = Overlap == againstUpperBound (Bound value Inclusive) (invertBound x)
belowRange (LowerBoundRange lower) value = Overlap == againstUpperBound (Bound value Inclusive) (invertBound lower)
belowRange (UpperBoundRange _)     _     = False
belowRange InfiniteRange           _     = False

-- | Returns 'True' if two ranges share at least one value.
--
-- >>> rangesOverlap (SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive)) (SpanRange (Bound 3 Inclusive) (Bound 7 Inclusive) :: Range Integer)
-- True
-- >>> rangesOverlap (SpanRange (Bound 1 Inclusive) (Bound 5 Exclusive)) (SpanRange (Bound 5 Inclusive) (Bound 7 Inclusive) :: Range Integer)
-- False
rangesOverlap :: Ord a => Range a -> Range a -> Bool
rangesOverlap a b = Overlap == rangesOverlapType a b

-- | Returns 'True' if two ranges touch at a single exclusive boundary but
-- share no values.
--
-- >>> rangesAdjoin (SpanRange (Bound 1 Inclusive) (Bound 5 Exclusive)) (SpanRange (Bound 5 Inclusive) (Bound 7 Inclusive) :: Range Integer)
-- True
-- >>> rangesAdjoin (SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive)) (SpanRange (Bound 3 Inclusive) (Bound 7 Inclusive) :: Range Integer)
-- False
rangesAdjoin :: Ord a => Range a -> Range a -> Bool
rangesAdjoin a b = Adjoin == rangesOverlapType a b

rangesOverlapType :: Ord a => Range a -> Range a -> OverlapType
rangesOverlapType (SingletonRange a) x =
  rangesOverlapType (SpanRange (Bound a Inclusive) (Bound a Inclusive)) x
rangesOverlapType (SpanRange x y)        (SpanRange a b)         = boundsOverlapType (x, y) (a, b)
rangesOverlapType (SpanRange _ y)        (LowerBoundRange lower) = againstLowerBound y lower
rangesOverlapType (SpanRange x _)        (UpperBoundRange upper) = againstUpperBound x upper
rangesOverlapType (LowerBoundRange _)    (LowerBoundRange _)     = Overlap
rangesOverlapType (LowerBoundRange lo)   (UpperBoundRange up)    = againstUpperBound lo up
rangesOverlapType (UpperBoundRange _)    (UpperBoundRange _)     = Overlap
rangesOverlapType InfiniteRange          _                       = Overlap
rangesOverlapType a b = rangesOverlapType b a

-- ---------------------------------------------------------------------------
-- Multi-range predicates
-- ---------------------------------------------------------------------------

-- | Returns 'True' if the value falls within any of the given ranges.
--
-- The membership predicate is pre-built when the 'Ranges' value is
-- constructed, so each call is O(log n) in the number of spans. Partial
-- application is idiomatic:
--
-- @
-- let memberOf = inRanges myRanges
-- filter memberOf largeList
-- @
--
-- >>> inRanges (1 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 5
-- True
-- >>> inRanges (1 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 15
-- False
inRanges :: Ord a => Ranges a -> a -> Bool
inRanges = _rangesQuery

-- | Returns 'True' if the value is strictly above all of the given ranges.
--
-- >>> aboveRanges (1 +=+ 5 <> 10 +=+ 15 :: Ranges Integer) 20
-- True
-- >>> aboveRanges (1 +=+ 5 <> lbi 10 :: Ranges Integer) 20
-- False
aboveRanges :: Ord a => Ranges a -> a -> Bool
aboveRanges r a = all (`aboveRange` a) (unRanges r)

-- | Returns 'True' if the value is strictly below all of the given ranges.
--
-- >>> belowRanges (5 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 1
-- True
-- >>> belowRanges (ubi 10 <> 20 +=+ 30 :: Ranges Integer) 1
-- False
belowRanges :: Ord a => Ranges a -> a -> Bool
belowRanges r a = all (`belowRange` a) (unRanges r)

-- ---------------------------------------------------------------------------
-- Set operations
-- ---------------------------------------------------------------------------

-- | Canonicalise a raw list of 'Range' values into a 'Ranges'. Overlapping
-- ranges are merged; the result is sorted and non-overlapping.
--
-- >>> mergeRanges [LowerBoundRange (Bound 12 Inclusive), SpanRange (Bound 1 Inclusive) (Bound 10 Inclusive), SpanRange (Bound 5 Inclusive) (Bound 15 Inclusive) :: Range Integer]
-- Ranges [lbi 1]
mergeRanges :: Ord a => [Range a] -> Ranges a
mergeRanges = mkRanges

-- | Set union. Equivalent to @('<>')@.
--
-- >>> union (1 +=+ 10) (5 +=+ 15 :: Ranges Integer)
-- Ranges [1 +=+ 15]
union :: Ord a => Ranges a -> Ranges a -> Ranges a
union a b = mkRanges $ Alg.eval $
  Alg.union (Alg.const (unRanges a)) (Alg.const (unRanges b))

-- | Set intersection. Returns only values present in both.
--
-- >>> intersection (1 +=+ 10) (5 +=+ 15 :: Ranges Integer)
-- Ranges [5 +=+ 10]
intersection :: Ord a => Ranges a -> Ranges a -> Ranges a
intersection a b = mkRanges $ Alg.eval $
  Alg.intersection (Alg.const (unRanges a)) (Alg.const (unRanges b))

-- | Set difference: values in the first 'Ranges' not in the second.
--
-- >>> difference (1 +=+ 10) (5 +=+ 15 :: Ranges Integer)
-- Ranges [1 +=* 5]
difference :: Ord a => Ranges a -> Ranges a -> Ranges a
difference a b = mkRanges $ Alg.eval $
  Alg.difference (Alg.const (unRanges a)) (Alg.const (unRanges b))

-- | Complement: all values /not/ covered by the given 'Ranges'.
-- @'invert' . 'invert' == 'id'@.
--
-- >>> invert (1 +=* 10 <> 15 *=+ 20 :: Ranges Integer)
-- Ranges [ube 1,10 +=+ 15,lbe 20]
invert :: Ord a => Ranges a -> Ranges a
invert = mkRanges . Alg.eval . Alg.invert . Alg.const . unRanges

-- ---------------------------------------------------------------------------
-- Enumerable methods
-- ---------------------------------------------------------------------------

-- | Instantiate all values covered by the ranges as a list.
-- __Warning:__ not efficient. Prefer 'inRanges' for membership tests.
-- Combine with 'take' to avoid evaluating infinite ranges.
--
-- >>> take 5 . fromRanges $ (1 +=+ 10 :: Ranges Integer)
-- [1,2,3,4,5]
--
-- >>> take 6 . fromRanges $ (1 +=+ 3 :: Ranges Integer) <> (10 +=+ 12)
-- [1,10,2,11,3,12]
fromRanges :: (Ord a, Enum a) => Ranges a -> [a]
fromRanges = takeEvenly . fmap fromRange . unRanges
  where
    fromRange (SingletonRange x) = [x]
    fromRange (SpanRange (Bound a aType) (Bound b bType)) =
      [ (if aType == Inclusive then a else succ a)
        .. (if bType == Inclusive then b else pred b) ]
    fromRange (LowerBoundRange (Bound x xType)) =
      iterate succ (if xType == Inclusive then x else succ x)
    fromRange (UpperBoundRange (Bound x xType)) =
      iterate pred (if xType == Inclusive then x else pred x)
    fromRange InfiniteRange =
      zero : takeEvenly [tail (iterate succ zero), tail (iterate pred zero)]
      where zero = toEnum 0

-- | Join adjacent ranges that are contiguous for 'Enum' types.
-- For example, @[1 +=+ 5, 6 +=+ 10]@ collapses to @[1 +=+ 10]@ for
-- 'Integer' because there is no integer between 5 and 6.
--
-- >>> joinRanges (mconcat [1 +=+ 5, 6 +=+ 10] :: Ranges Integer)
-- Ranges [1 +=+ 10]
joinRanges :: (Ord a, Enum a) => Ranges a -> Ranges a
joinRanges = mkRanges . exportRangeMerge . joinRM . loadRanges . unRanges
