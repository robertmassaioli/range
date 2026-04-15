{-# LANGUAGE Safe #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances #-}

-- | Internally the range library converts your ranges into an internal
-- efficient representation. When you perform multiple unions and intersections
-- in a row, converting to and from that representation on every step is extra
-- work. The @RangeExpr@ algebra amortises this cost: build a tree of operations
-- first, then evaluate the whole tree in one pass.
--
-- __When to use this module:__ Build a 'RangeExpr' when you are combining three
-- or more operations in a pipeline, or when you want to evaluate the same
-- expression against multiple targets (e.g. both 'Data.Ranges.Ranges' and
-- @a -> 'Bool'@). A single @union a b@ is no faster through the algebra than
-- a direct call.
--
-- __Note:__ This module is based on F-Algebras. If you have never encountered
-- them before, see
-- <https://www.schoolofhaskell.com/user/bartosz/understanding-algebras this introduction>
-- from the School of Haskell.
--
-- == Examples
--
-- Evaluate to a 'Data.Ranges.Ranges' value (the typical use):
--
-- @
-- import qualified Data.Range.Algebra as A
-- import Data.Ranges
--
-- expr :: A.RangeExpr (Ranges Integer)
-- expr = A.invert (A.const (SingletonRange 5))
--
-- A.eval expr :: Ranges Integer
-- -- Ranges [ube 4,lbi 6]
-- @
--
-- Evaluate the same expression as a predicate (no intermediate structure built):
--
-- @
-- import qualified Data.Range.Algebra as A
-- import Data.Ranges
--
-- let expr = A.union (A.const (1 +=+ 10)) (A.const (20 +=+ 30)) :: A.RangeExpr (Ranges Integer)
-- A.eval (fmap inRanges expr) 25  -- True
-- A.eval (fmap inRanges expr) 15  -- False
-- @
--
module Data.Range.Algebra
  ( -- * Expression trees
    RangeExpr
    -- ** Building expressions
  , const, invert, union, intersection, difference
    -- * Evaluation
  , Algebra, RangeAlgebra(..)
  ) where

import Prelude hiding (const)

import Data.Range.Data
import Data.Range.Algebra.Internal
import Data.Range.Algebra.Range
import Data.Range.Algebra.Predicate

import Control.Monad.Free

-- | Lifts a value as a constant leaf into an expression tree.
--
-- Note: this function shadows 'Prelude.const'. The "Data.Range.Algebra" module
-- uses @import Prelude hiding (const)@; callers that import both should qualify.
const :: a -> RangeExpr a
const = RangeExpr . Pure

-- | Wraps an expression in a set-complement (invert) node.
-- When evaluated, produces all values /not/ covered by the inner expression.
-- Note that @'invert' . 'invert' == 'id'@.
invert :: RangeExpr a -> RangeExpr a
invert = RangeExpr . Free . Invert . getFree

-- | Wraps two expressions in a set-union node.
-- When evaluated, produces all values covered by either expression.
union :: RangeExpr a -> RangeExpr a -> RangeExpr a
union a b = RangeExpr . Free $ Union (getFree a) (getFree b)

-- | Wraps two expressions in a set-intersection node.
-- When evaluated, produces only values covered by both expressions.
intersection :: RangeExpr a -> RangeExpr a -> RangeExpr a
intersection a b = RangeExpr . Free $ Intersection (getFree a) (getFree b)

-- | Wraps two expressions in a set-difference node.
-- When evaluated, produces values in the first expression that are absent from the second.
difference :: RangeExpr a -> RangeExpr a -> RangeExpr a
difference a b = RangeExpr . Free $ Difference (getFree a) (getFree b)

-- | A type class for types that a 'RangeExpr' can be evaluated to.
-- Three instances are provided out of the box; additional targets can be added
-- by implementing this class.
class RangeAlgebra a where
  -- | Collapses a 'RangeExpr' tree into its target representation by
  -- evaluating every node bottom-up. Three evaluation targets are supported:
  --
  -- * 'Data.Ranges.Ranges' @a@ — canonical, indexed set with pre-built
  --   membership predicate. The primary target for user code; instance defined
  --   in "Data.Ranges".
  -- * @['Data.Range.Data.Range' a]@ — a merged, canonical list. Used internally
  --   and useful when you need to inspect individual ranges.
  -- * @a -> 'Bool'@ — a membership predicate; no intermediate structure built.
  eval :: Algebra RangeExpr a

-- | Evaluates to a merged, canonical list of non-overlapping ranges.
-- Used internally by "Data.Ranges" and useful when you need to inspect
-- individual 'Range' values. Prefer the 'Data.Ranges.Ranges' instance for
-- general use.
instance (Ord a) => RangeAlgebra [Range a] where
  eval = iter rangeAlgebra . getFree

-- | Evaluates to a membership predicate @a -> 'Bool'@.
-- No intermediate structure is constructed. With 'Data.Ranges.Ranges' leaves,
-- use @'eval' ('fmap' 'Data.Ranges.inRanges' expr)@ to reach this instance.
instance RangeAlgebra (a -> Bool) where
  eval = iter predicateAlgebra . getFree
