{-# LANGUAGE Safe #-}
{-# LANGUAGE DeriveGeneric #-}

-- | The Data module for common data types within the code.
module Data.Range.Data where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

data OverlapType = Separate | Overlap | Adjoin
   deriving (Eq, Show, Generic)

instance NFData OverlapType

-- | Represents a type of boundary.
data BoundType
   = Inclusive -- ^ The value at the boundary should be included in the bound.
   | Exclusive -- ^ The value at the boundary should be excluded in the bound.
   deriving (Eq, Ord, Show, Generic)

instance NFData BoundType

-- | Represents a bound at a particular value with a 'BoundType'.
-- There is no implicit understanding if this is a lower or upper bound, it could be either.
data Bound a = Bound
   { boundValue :: a          -- ^ The value at the edge of this bound.
   , boundType :: BoundType   -- ^ The type of bound. Should be 'Inclusive' or 'Exclusive'.
   } deriving (Eq, Ord, Show, Generic)

instance NFData a => NFData (Bound a)

instance Functor Bound where
   fmap f (Bound v vType) = Bound (f v) vType

-- TODO can we implement Monoid for Range a with the addition of an empty?
-- Or maybe we can implement Monoid for a list of ranges...

-- | The Range Data structure; it is capable of representing any type of range. This is
-- the primary data structure in this library. Everything should be possible to convert
-- back into this datatype. All ranges in this structure are inclusively bound.
data Range a
   = SingletonRange a               -- ^ Represents a single element as a range. @SingletonRange a@ is equivalent to @SpanRange (Bound a Inclusive) (Bound a Inclusive)@.
   | SpanRange (Bound a) (Bound a)  -- ^ Represents a bounded span of elements. The first argument is expected to be less than or equal to the second argument.
   | LowerBoundRange (Bound a)      -- ^ Represents a range with a finite lower bound and an infinite upper bound.
   | UpperBoundRange (Bound a)      -- ^ Represents a range with an infinite lower bound and a finite upper bound.
   | InfiniteRange                  -- ^ Represents an infinite range over all values.
   deriving (Eq, Generic)

instance NFData a => NFData (Range a)

instance Show a => Show (Range a) where
   showsPrec i (SingletonRange a) = ((++) "SingletonRange ") . showsPrec i a
   showsPrec i (SpanRange (Bound l lType) (Bound r rType)) =
      showsPrec i l . showSymbol lType rType . showsPrec i r
      where
         showSymbol Inclusive Inclusive = (++) " +=+ "
         showSymbol Inclusive Exclusive = (++) " +=* "
         showSymbol Exclusive Inclusive = (++) " *=+ "
         showSymbol Exclusive Exclusive = (++) " *=* "
   showsPrec i (LowerBoundRange (Bound a Inclusive)) = ((++) "lbi ") . (showsPrec i a)
   showsPrec i (LowerBoundRange (Bound a Exclusive)) = ((++) "lbe ") . (showsPrec i a)
   showsPrec i (UpperBoundRange (Bound a Inclusive)) = ((++) "ubi ") . (showsPrec i a)
   showsPrec i (UpperBoundRange (Bound a Exclusive)) = ((++) "ube ") . (showsPrec i a)
   showsPrec _ (InfiniteRange) = (++) "inf"
