{-# LANGUAGE Safe #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}

module Data.Range.Algebra.Internal where

import Prelude hiding (const)

import Data.Range.RangeInternal

import Control.Monad.Free
import Data.Functor.Classes

data RangeExprF r
  = Invert r
  | Union r r
  | Intersection r r
  | Difference r r
  deriving (Show, Eq, Functor)

instance Eq1 RangeExprF where
  liftEq eq (Invert a) (Invert b) = eq a b
  liftEq eq (Union a c) (Union b d) = eq a b && eq c d
  liftEq eq (Intersection a c) (Intersection b d) = eq a b && eq c d
  liftEq eq (Difference a c) (Difference b d) = eq a b && eq c d
  liftEq _ _ _ = False

instance Show1 RangeExprF where
  liftShowsPrec showPrec _ p (Invert x) = showString "not " . showParen True (showPrec (p + 1) x)
  liftShowsPrec showPrec _ p (Union a b) =
    showPrec (p + 1) a .
    showString " \\/ " .
    showPrec (p + 1) b
  liftShowsPrec showPrec _ p (Intersection a b) =
    showPrec (p + 1) a .
    showString " /\\ " .
    showPrec (p + 1) b
  liftShowsPrec showPrec _ p (Difference a b) =
    showPrec (p + 1) a .
    showString " - " .
    showPrec (p + 1) b

-- | An expression tree representing a sequence of set operations on ranges.
-- Construct trees with 'Data.Range.Algebra.const', 'Data.Range.Algebra.union',
-- 'Data.Range.Algebra.intersection', 'Data.Range.Algebra.difference', and
-- 'Data.Range.Algebra.invert', then collapse the tree with 'Data.Range.Algebra.eval'.
--
-- The type parameter @a@ is the range representation the tree will eventually
-- evaluate to (e.g. @['Data.Range.Range' Integer]@ or @Integer -> 'Bool'@).
--
-- @RangeExpr@ is a 'Functor', so you can map over the leaf values before evaluation.
newtype RangeExpr a = RangeExpr { getFree :: Free RangeExprF a }
  deriving (Show, Eq, Functor)

-- | The type of an evaluation function for a 'RangeExpr'. You will not normally
-- need to reference this alias directly; it exists to express the signature of
-- 'Data.Range.Algebra.eval'.
--
-- Concretely, @Algebra f a = f a -> a@, meaning: given a functor @f@ applied to
-- an already-evaluated @a@, produce the final @a@. The 'Control.Monad.Free.iter'
-- function from the @free@ package drives the bottom-up fold.
type Algebra f a = f a -> a

rangeMergeAlgebra :: (Ord a) => Algebra RangeExprF (RangeMerge a)
rangeMergeAlgebra (Invert a) = invertRM a
rangeMergeAlgebra (Union a b) = a `unionRangeMerges` b
rangeMergeAlgebra (Intersection a b) = a `intersectionRangeMerges` b
rangeMergeAlgebra (Difference a b) = a `intersectionRangeMerges` invertRM b
