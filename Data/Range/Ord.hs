{-# LANGUAGE Safe #-}

-- | Ordering newtypes for 'Range'.
--
-- 'Range' deliberately has no 'Ord' instance because there is no single
-- natural ordering — the right choice depends on the use case. This module
-- provides two explicit wrappers:
--
-- * 'KeyRange' — a consistent structural ordering, suitable for use as a
--   'Data.Map.Map' key or in a 'Data.Set.Set'.
--
-- * 'SortedRange' — a positional ordering by location on the number line,
--   suitable for sorting ranges for display.
--
-- == Example: Map keyed on ranges
--
-- @
-- import Data.Range (Range, (+=+), lbi)
-- import Data.Range.Ord (KeyRange(..))
-- import qualified Data.Map.Strict as Map
--
-- type RuleMap = Map (KeyRange Integer) String
--
-- rules :: RuleMap
-- rules = Map.fromList
--   [ (KeyRange (1 +=+ 10),  \"low\")
--   , (KeyRange (11 +=+ 50), \"medium\")
--   , (KeyRange (lbi 51),    \"high\")
--   ]
-- @
--
-- == Example: sorting ranges by position on the number line
--
-- @
-- import Data.List (sortOn)
-- import Data.Range (Range, (+=+), lbi, ube)
-- import Data.Range.Ord (SortedRange(..))
--
-- sortOn SortedRange [lbi 10, 1 +=+ 5, ube 0 :: Range Integer]
-- -- [ube 0, 1 +=+ 5, lbi 10]
--
-- -- or equivalently:
-- displayRanges :: Ord a => [Range a] -> [Range a]
-- displayRanges = sortOn SortedRange
-- @
module Data.Range.Ord
   ( -- * Structural ordering
     -- | Use 'KeyRange' when you need 'Range' values as 'Data.Map.Map' keys or
     -- in a 'Data.Set.Set'. The ordering is consistent but not semantically
     -- meaningful on the number line.
     KeyRange(..)
     -- * Positional ordering
     -- | Use 'SortedRange' when you want to sort ranges by where they sit on
     -- the number line (lower bound first, upper bound as tiebreaker).
   , SortedRange(..)
   ) where

-- $setup
-- >>> import Data.Range
-- >>> import Data.Range.Ord
-- >>> import Data.List (sortOn)

import Data.Range.Data
import Data.Range.Util (compareLower, compareHigher)

-- ---------------------------------------------------------------------------
-- KeyRange: structural ordering
-- ---------------------------------------------------------------------------

-- | Wraps 'Range' with a structural 'Ord' instance, suitable for use as a
-- 'Data.Map.Map' key or in a 'Data.Set.Set'.
--
-- Constructor order: @SingletonRange < SpanRange < LowerBoundRange <
-- UpperBoundRange < InfiniteRange@. Fields within the same constructor are
-- compared lexicographically.
--
-- This ordering is not semantically meaningful on the number line —
-- @SingletonRange 5@ and @SpanRange (Bound 5 Inclusive) (Bound 5 Inclusive)@
-- are considered distinct. It is only appropriate where any consistent total
-- order will do (deduplication, 'Data.Map.Map' keys).
--
-- Use 'unKeyRange' to unwrap the underlying 'Range'.
--
-- See also 'SortedRange' for ordering by position on the number line.
--
-- @since 0.3.2.0
newtype KeyRange a = KeyRange { unKeyRange :: Range a }
   deriving (Eq, Show)

constructorRank :: Range a -> Int
constructorRank (SingletonRange _)  = 0
constructorRank (SpanRange _ _)     = 1
constructorRank (LowerBoundRange _) = 2
constructorRank (UpperBoundRange _) = 3
constructorRank InfiniteRange       = 4

compareRangeFields :: Ord a => Range a -> Range a -> Ordering
compareRangeFields (SingletonRange a)  (SingletonRange b)  = compare a b
compareRangeFields (SpanRange lo1 hi1) (SpanRange lo2 hi2) =
   case compare lo1 lo2 of
      EQ -> compare hi1 hi2
      r  -> r
compareRangeFields (LowerBoundRange a) (LowerBoundRange b) = compare a b
compareRangeFields (UpperBoundRange a) (UpperBoundRange b) = compare a b
compareRangeFields InfiniteRange       InfiniteRange       = EQ
compareRangeFields _                   _                   = EQ

instance Ord a => Ord (KeyRange a) where
   compare (KeyRange x) (KeyRange y) =
      case compare (constructorRank x) (constructorRank y) of
         EQ -> compareRangeFields x y
         r  -> r

-- ---------------------------------------------------------------------------
-- SortedRange: positional ordering
-- ---------------------------------------------------------------------------

-- | Extended bound adding @-∞@ and @+∞@ sentinels, used internally by
-- 'SortedRange'.
data ExtBound a = NegInfinity | FiniteBound (Bound a) | PosInfinity

compareExtBound :: (Bound a -> Bound a -> Ordering) -> ExtBound a -> ExtBound a -> Ordering
compareExtBound _   NegInfinity     NegInfinity     = EQ
compareExtBound _   NegInfinity     _               = LT
compareExtBound _   _               NegInfinity     = GT
compareExtBound _   PosInfinity     PosInfinity     = EQ
compareExtBound _   PosInfinity     _               = GT
compareExtBound _   _               PosInfinity     = LT
compareExtBound cmp (FiniteBound a) (FiniteBound b) = cmp a b

lowerExtBound :: Range a -> ExtBound a
lowerExtBound (UpperBoundRange _) = NegInfinity
lowerExtBound InfiniteRange       = NegInfinity
lowerExtBound (LowerBoundRange b) = FiniteBound b
lowerExtBound (SpanRange lo _)    = FiniteBound lo
lowerExtBound (SingletonRange x)  = FiniteBound (Bound x Inclusive)

upperExtBound :: Range a -> ExtBound a
upperExtBound (LowerBoundRange _) = PosInfinity
upperExtBound InfiniteRange       = PosInfinity
upperExtBound (UpperBoundRange b) = FiniteBound b
upperExtBound (SpanRange _ hi)    = FiniteBound hi
upperExtBound (SingletonRange x)  = FiniteBound (Bound x Inclusive)

-- | Wraps 'Range' with a positional 'Ord' instance: ranges are ordered by
-- where they sit on the number line, lower bound first with upper bound as a
-- tiebreaker.
--
-- The 'Eq' instance is consistent with 'Ord': two 'SortedRange' values are
-- equal iff they have the same lower and upper bounds. This means
-- @SortedRange (SingletonRange 5)@ and @SortedRange (5 +=+ 5)@ are considered
-- equal (they occupy the same point on the number line).
--
-- Use 'unSortedRange' to unwrap the underlying 'Range'. Typical usage:
--
-- >>> import Data.List (sortOn)
-- >>> sortOn SortedRange [SingletonRange 5, SingletonRange 1, SingletonRange 3 :: Range Integer]
-- [SingletonRange 1,SingletonRange 3,SingletonRange 5]
--
-- See also 'KeyRange' for a structural ordering suitable for 'Data.Map.Map' keys.
--
-- @since 0.3.2.0
newtype SortedRange a = SortedRange { unSortedRange :: Range a }

instance Show a => Show (SortedRange a) where
   show (SortedRange r) = "SortedRange (" ++ show r ++ ")"

instance Ord a => Eq (SortedRange a) where
   x == y = compare x y == EQ

instance Ord a => Ord (SortedRange a) where
   compare (SortedRange a) (SortedRange b) =
      case compareExtBound compareLower (lowerExtBound a) (lowerExtBound b) of
         EQ -> compareExtBound compareHigher (upperExtBound a) (upperExtBound b)
         r  -> r
