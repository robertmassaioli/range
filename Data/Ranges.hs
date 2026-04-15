{-# LANGUAGE Safe #-}

-- | This module provides the 'Ranges' type — a wrapper around @['Data.Range.Range' a]@ that
-- integrates with standard Haskell type classes, making it easy to accumulate and
-- compose ranges using familiar idioms.
--
-- The primary advantage over "Data.Range" is that 'Ranges' implements 'Semigroup'
-- and 'Monoid', where @('<>')@ means /union-and-merge/. This composes naturally with
-- standard Haskell functions:
--
-- >>> import Data.Foldable (fold)
-- >>> fold [1 +=+ 5, 3 +=+ 8, lbi 20 :: Ranges Integer]
-- Ranges [1 +=+ 8,lbi 20]
--
-- >>> mconcat [1 +=+ 5, 10 +=+ 15, 12 +=+ 20 :: Ranges Integer]
-- Ranges [1 +=+ 5,10 +=+ 20]
--
-- __When to use this module vs "Data.Range":__
--
-- * Use "Data.Range" when working with @['Range' a]@ directly or calling individual
--   set operations like 'union' and 'intersection'.
-- * Use this module when you want 'Monoid' / 'Semigroup' semantics, need 'Functor'
--   to map over all range boundaries, or are threading ranges through code that
--   expects a 'Monoid' (e.g. 'mconcat', 'fold', writer-style accumulation).
module Data.Ranges (
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
  -- * Comparison functions
  inRanges,
  aboveRanges,
  belowRanges,
  -- * Set operations
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

import qualified Data.Range as R

-- | Smart constructor. Canonicalises the range list and pre-builds the cached
-- lookup predicate. All internal paths that produce a 'Ranges' go through this.
mkRanges :: Ord a => [R.Range a] -> Ranges a
mkRanges xs =
  let canonical = R.mergeRanges xs
  in Ranges canonical (Just (R.inRanges canonical))

-- $creation
-- Each operator constructs a single-element 'Ranges'. Because 'Ranges' is a
-- 'Semigroup', you can combine them directly with '<>':
--
-- >>> (1 +=+ 5 :: Ranges Integer) <> (3 +=+ 8)
-- Ranges [1 +=+ 8]
--
-- The operators mirror those in "Data.Range" but return 'Ranges' instead of
-- @'R.Range'@, so they compose naturally without wrapping and unwrapping.

-- | A set of ranges represented as a merged, canonical list of
-- non-overlapping 'R.Range' values.
--
-- The 'Semigroup' instance merges ranges on @('<>')@:
--
-- >>> (1 +=+ 5 :: Ranges Integer) <> (3 +=+ 8)
-- Ranges [1 +=+ 8]
--
-- 'mempty' is the empty set (no ranges). 'mconcat' merges an entire list at once,
-- which is more efficient than repeated @('<>')@:
--
-- >>> mconcat [1 +=+ 5, 10 +=+ 15, 12 +=+ 20 :: Ranges Integer]
-- Ranges [1 +=+ 5,10 +=+ 20]
--
-- The 'Functor' instance maps a function over every boundary value in every range:
--
-- >>> fmap (*2) (1 +=+ 5 :: Ranges Integer)
-- Ranges [2 +=+ 10]
--
-- Use 'unRanges' to extract the underlying list. Do not construct 'Ranges'
-- directly; use the operators or set-operation functions so that the cached
-- lookup structure is always kept consistent.
data Ranges a = Ranges
  { unRanges     :: [R.Range a]     -- ^ The canonical (sorted, non-overlapping) range list.
  , _rangesQuery :: Maybe (a -> Bool) -- ^ Cached O(log n) predicate; Nothing after 'fmap'.
  }

instance Show a => Show (Ranges a) where
   showsPrec i r = ((++) "Ranges ") . showsPrec i (unRanges r)

-- | @('<>')@ computes the set union of two 'Ranges' and merges the result into
-- canonical (non-overlapping) form. Associative, with 'mempty' as the identity.
instance Ord a => Semigroup (Ranges a) where
   (<>) a b = mkRanges $ unRanges a ++ unRanges b

-- | 'mempty' is the empty set. 'mconcat' is more efficient than folding '<>'
-- because it merges all ranges in a single pass.
instance Ord a => Monoid (Ranges a) where
   mempty = mkRanges []
   mconcat = mkRanges . concat . fmap unRanges

-- | Maps a function over every boundary value in every range.
-- Note that mapping a non-monotonic function can produce ill-formed ranges
-- (e.g. a span whose lower bound ends up greater than its upper bound).
-- Use with care on ordered types.
--
-- The cached lookup predicate cannot be pre-built here because 'Functor' does
-- not allow an 'Ord' constraint. Calling 'inRanges' on the result will still
-- pre-build the map on partial application via 'Data.Range.inRanges'.
instance Functor Ranges where
   fmap f r = Ranges (fmap (fmap f) (unRanges r)) Nothing

-- | Mathematically equivalent to @[x, y]@. See 'R.+=+' for details.
(+=+) :: Ord a => a -> a -> Ranges a
(+=+) a b = mkRanges . pure $ (R.+=+) a b

-- | Mathematically equivalent to @[x, y)@. See 'R.+=*' for details.
(+=*) :: Ord a => a -> a -> Ranges a
(+=*) a b = mkRanges . pure $ (R.+=*) a b

-- | Mathematically equivalent to @(x, y]@. See 'R.*=+' for details.
(*=+) :: Ord a => a -> a -> Ranges a
(*=+) a b = mkRanges . pure $ (R.*=+) a b

-- | Mathematically equivalent to @(x, y)@. See 'R.*=*' for details.
(*=*) :: Ord a => a -> a -> Ranges a
(*=*) a b = mkRanges . pure $ (R.*=*) a b

-- | Mathematically equivalent to @[x, ∞)@. See 'R.lbi' for details.
lbi :: Ord a => a -> Ranges a
lbi = mkRanges . pure . R.lbi

-- | Mathematically equivalent to @(x, ∞)@. See 'R.lbe' for details.
lbe :: Ord a => a -> Ranges a
lbe = mkRanges . pure . R.lbe

-- | Mathematically equivalent to @(−∞, x]@. See 'R.ubi' for details.
ubi :: Ord a => a -> Ranges a
ubi = mkRanges . pure . R.ubi

-- | Mathematically equivalent to @(−∞, x)@. See 'R.ube' for details.
ube :: Ord a => a -> Ranges a
ube = mkRanges . pure . R.ube

-- | The infinite range, covering all values. See 'R.inf' for details.
inf :: Ord a => Ranges a
inf = mkRanges [R.inf]

-- | Returns 'True' if the value falls within any of the given ranges.
--
-- The lookup structure is pre-built when the 'Ranges' value is constructed,
-- so each membership test is O(log n) where n is the number of spans.
-- Partial application is idiomatic:
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
inRanges r = case _rangesQuery r of
  Just f  -> f
  Nothing -> R.inRanges (unRanges r)

-- | Returns 'True' if the value is strictly above (greater than the upper
-- bound of) all of the given ranges.
--
-- >>> aboveRanges (1 +=+ 5 <> 10 +=+ 15 :: Ranges Integer) 20
-- True
-- >>> aboveRanges (1 +=+ 5 <> lbi 10 :: Ranges Integer) 20
-- False
aboveRanges :: (Ord a) => Ranges a -> a -> Bool
aboveRanges r a = R.aboveRanges (unRanges r) a

-- | Returns 'True' if the value is strictly below (less than the lower
-- bound of) all of the given ranges.
--
-- >>> belowRanges (5 +=+ 10 <> 20 +=+ 30 :: Ranges Integer) 1
-- True
-- >>> belowRanges (ubi 10 <> 20 +=+ 30 :: Ranges Integer) 1
-- False
belowRanges :: (Ord a) => Ranges a -> a -> Bool
belowRanges r a = R.belowRanges (unRanges r) a

-- | Set union of two 'Ranges'. The output is in merged canonical form.
-- Equivalent to @('<>')@.
union :: (Ord a) => Ranges a -> Ranges a -> Ranges a
union a b = mkRanges $ R.union (unRanges a) (unRanges b)

-- | Set intersection of two 'Ranges'. Returns only values present in both.
--
-- >>> intersection (1 +=+ 10) (5 +=+ 15 :: Ranges Integer)
-- Ranges [5 +=+ 10]
intersection :: (Ord a) => Ranges a -> Ranges a -> Ranges a
intersection a b = mkRanges $ R.intersection (unRanges a) (unRanges b)

-- | Set difference: values in the first 'Ranges' that are not in the second.
--
-- >>> difference (1 +=+ 10) (5 +=+ 15 :: Ranges Integer)
-- Ranges [1 +=* 5]
difference :: (Ord a) => Ranges a -> Ranges a -> Ranges a
difference a b = mkRanges $ R.difference (unRanges a) (unRanges b)

-- | Returns the complement of the given 'Ranges': all values /not/ covered.
-- Note that @'invert' . 'invert' == 'id'@.
invert :: (Ord a) => Ranges a -> Ranges a
invert = mkRanges . R.invert . unRanges

-- | Instantiates all values covered by the ranges as a list.
-- __Warning:__ This is a convenience function and is not efficient. Prefer
-- membership checks with 'inRanges' where possible. Combine with 'take' to
-- avoid evaluating infinite ranges.
--
-- >>> take 6 . fromRanges $ (1 +=+ 3 :: Ranges Integer) <> (10 +=+ 12)
-- [1,10,2,11,3,12]
fromRanges :: (Ord a, Enum a) => Ranges a -> [a]
fromRanges = R.fromRanges . unRanges

-- | Joins adjacent ranges that are contiguous for 'Enum' types. For example,
-- @[1 +=+ 5, 6 +=+ 10]@ can be collapsed to @[1 +=+ 10]@ for 'Integer'
-- because there is no integer between 5 and 6.
--
-- >>> joinRanges (mconcat [1 +=+ 5, 6 +=+ 10] :: Ranges Integer)
-- Ranges [1 +=+ 10]
joinRanges :: (Ord a, Enum a) => Ranges a -> Ranges a
joinRanges = mkRanges . R.joinRanges . unRanges