{-# LANGUAGE FlexibleContexts #-}

-- | A simple parser for human-readable range strings, designed for CLI programs.
--
-- By default, ranges are separated by commas and span endpoints by a hyphen:
--
-- >>> parseRanges "-5,8-10,13-15,20-" :: Either ParseError [Range Integer]
-- Right [UpperBoundRange (Bound 5 Inclusive),SpanRange (Bound 8 Inclusive) (Bound 10 Inclusive),SpanRange (Bound 13 Inclusive) (Bound 15 Inclusive),LowerBoundRange (Bound 20 Inclusive)]
--
-- The @*@ wildcard produces an infinite range:
--
-- >>> parseRanges "*" :: Either ParseError [Range Integer]
-- Right [InfiniteRange]
--
-- Use 'customParseRanges' to change the separator characters:
--
-- >>> let args = defaultArgs { unionSeparator = ";", rangeSeparator = ".." }
-- >>> customParseRanges args "1..5;10" :: Either ParseError [Range Integer]
-- Right [SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive),SingletonRange 10]
--
-- __Known limitations:__
--
-- * Only non-negative integer literals are recognised. The input @\"-5\"@ is parsed
--   as @UpperBoundRange 5@ (an upper-bounded range), not @SingletonRange (-5)@.
--   For negative values, use 'customParseRanges' with a different 'rangeSeparator',
--   or pre-process the input string.
--
-- * Unrecognised input is silently consumed as an empty list rather than producing
--   a parse error. For example, @parseRanges \"abc\"@ returns @Right []@. This is a
--   consequence of using 'Text.Parsec.sepBy' internally and is by design for
--   CLI use where partial input is common.
--
-- For more complex parsing (e.g. @.cabal@ or @package.json@ files), parse version
-- strings with Parsec or Alex\/Happy and convert the results into 'Range' values directly.
module Data.Range.Parser
   ( -- * Parsing
     parseRanges
   , customParseRanges
     -- * Configuration
   , RangeParserArgs(..)
   , defaultArgs
     -- * Lower-level parser
   , ranges
     -- * Re-exports
     -- | 'ParseError' is re-exported from "Text.Parsec" for convenience, so
     -- callers do not need to import Parsec directly just to match on parse failures.
   , ParseError
   ) where

import Text.Parsec
import Text.Parsec.String

import Data.Range

-- | Configuration for the range parser. All three fields are plain strings, so
-- multi-character separators (e.g. @\"..\"@) are supported.
data RangeParserArgs = Args
   { unionSeparator :: String -- ^ Separates multiple ranges in a union. Default: @\",\"@.
   , rangeSeparator :: String -- ^ Separates the two endpoints of a span. Default: @\"-\"@.
   , wildcardSymbol :: String -- ^ Symbol for an infinite range. Default: @\"*\"@.
   }
   deriving(Show)

-- | The default parser configuration: comma-separated ranges, hyphen-separated
-- endpoints, and @*@ as the wildcard. Modify individual fields with record syntax:
--
-- >>> defaultArgs { unionSeparator = ";", rangeSeparator = ".." }
-- Args {unionSeparator = ";", rangeSeparator = "..", wildcardSymbol = "*"}
defaultArgs :: RangeParserArgs
defaultArgs = Args
   { unionSeparator = ","
   , rangeSeparator = "-"
   , wildcardSymbol = "*"
   }

-- | Parses a range string using the default separators (@,@ and @-@). Returns
-- either a 'ParseError' or the list of parsed ranges.
--
-- The 'Read' instance of @a@ is used to parse individual numeric literals, so
-- the type must have a well-behaved 'Read'. Exotic types with unusual 'Read'
-- instances may not parse correctly.
--
-- See the module documentation for known limitations around negative numbers
-- and unrecognised input.
parseRanges :: (Read a) => String -> Either ParseError [Range a]
parseRanges = parse (ranges defaultArgs) "(range parser)"

-- | Like 'parseRanges' but with caller-supplied separator configuration.
-- Use this when the default @,@ and @-@ characters conflict with your input format.
--
-- >>> let args = defaultArgs { unionSeparator = ";", rangeSeparator = ".." }
-- >>> customParseRanges args "1..5;10" :: Either ParseError [Range Integer]
-- Right [SpanRange (Bound 1 Inclusive) (Bound 5 Inclusive),SingletonRange 10]
customParseRanges :: Read a => RangeParserArgs -> String -> Either ParseError [Range a]
customParseRanges args = parse (ranges args) "(range parser)"

string_ :: Stream s m Char => String -> ParsecT s u m ()
string_ x = string x >> return ()

-- | Returns a Parsec 'Parser' for a list of ranges using the given configuration.
-- Use this when embedding range parsing into a larger Parsec grammar; for
-- standalone parsing prefer 'parseRanges' or 'customParseRanges'.
ranges :: (Read a) => RangeParserArgs -> Parser [Range a]
ranges args = range `sepBy` (string $ unionSeparator args)
   where
      range :: (Read a) => Parser (Range a)
      range = choice
         [ infiniteRange
         , spanRange
         , singletonRange
         ]

      infiniteRange :: (Read a) => Parser (Range a)
      infiniteRange = do
         string_ $ wildcardSymbol args
         return InfiniteRange

      spanRange :: (Read a) => Parser (Range a)
      spanRange = try $ do
         first <- readSection
         string_ $ rangeSeparator args
         second <- readSection
         case (first, second) of
            (Just x, Just y)  -> return $ SpanRange (Bound x Inclusive) (Bound y Inclusive)
            (Just x, _)       -> return $ LowerBoundRange (Bound x Inclusive)
            (_, Just y)       -> return $ UpperBoundRange (Bound y Inclusive)
            _                 -> parserFail ("Range should have a number on one end: " ++ rangeSeparator args)

      singletonRange :: (Read a) => Parser (Range a)
      singletonRange = fmap (SingletonRange . read) $ many1 digit

readSection :: (Read a) => Parser (Maybe a)
readSection = fmap (fmap read) $ optionMaybe (many1 digit)
