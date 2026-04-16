# Test Warning Cleanup Proposal

`stack clean && stack test` produces warnings from the test suite compilation
and doctest runner. The library itself compiles cleanly. All warnings below
are in `Test/` or `range.cabal`.

They fall into six actionable categories plus two categories that are outside
our control.

---

## Category 1: Deprecated module imports — 4 warnings

**Diagnostic: GHC-15328 `-Wdeprecations`**

| File | Line | Import |
|------|------|--------|
| `Test/Generators.hs` | 10 | `import Data.Range` |
| `Test/RangeLaws.hs` | 9 | `import Data.Range` |
| `Test/RangeOrd.hs` | 13 | `import Data.Range` |
| `Test/Range.hs` | 13 | `import Data.Range` |

`Data.Range` is now a deprecated re-export shim for `Data.Ranges`. The test
suite should import from `Data.Ranges` directly. `Test/Range.hs` also uses
`qualified Data.Range.Algebra as Alg` — that import is fine (it's the algebra
module, not the deprecated shim).

**Fix:** Replace `import Data.Range` with `import Data.Ranges` in all four
files. Verify that any symbols used are re-exported by `Data.Ranges` (they
all are).

---

## Category 2: Missing cabal home-modules declaration — 1 warning (repeated 3×)

**Diagnostic: GHC-32850 `-Wmissing-home-modules`**

```
These modules are needed for compilation but not listed in your .cabal file's
other-modules for 'test-range':
    Data.Range, Data.Range.Algebra, Data.Range.Algebra.Internal,
    Data.Range.Algebra.Predicate, Data.Range.Algebra.Range,
    Data.Range.Data, Data.Range.Operators, Data.Range.Ord,
    Data.Range.Parser, Data.Range.RangeInternal, Data.Range.Spans,
    Data.Range.Util, Data.Ranges
```

The `test-range` stanza has `build-depends: range` and `ghc-options:
-fno-enable-rewrite-rules`. Because of `-fno-enable-rewrite-rules` (originally
added to suppress the now-deleted `load/export` RULES pragma), stack compiles
the library modules again under the test target's GHC flags. GHC sees source
files for those modules in the working tree but finds them undeclared in the
test stanza's `other-modules`, hence the warning.

**Fix (two steps):**

**Step 1** — remove `-fno-enable-rewrite-rules` from the `test-range`
`ghc-options`. The only RULES pragma it suppressed was deleted in a prior
commit. Keeping it just forces an unnecessary recompile.

**Step 2** — if the warning persists after Step 1, add the full list of
library modules to `other-modules` in the `test-range` stanza:

```cabal
Test-Suite test-range
  other-modules:
    Test.RangeMerge
    , Test.RangeLaws
    , Test.RangeParser
    , Test.RangeOrd
    , Test.Generators
    -- library modules accessed directly by tests:
    , Data.Range
    , Data.Ranges
    , Data.Range.Algebra
    , Data.Range.Algebra.Internal
    , Data.Range.Algebra.Predicate
    , Data.Range.Algebra.Range
    , Data.Range.Data
    , Data.Range.Operators
    , Data.Range.Ord
    , Data.Range.Parser
    , Data.Range.RangeInternal
    , Data.Range.Spans
    , Data.Range.Util
```

Step 1 alone may be sufficient; apply Step 2 only if the warning remains.

---

## Category 3: Unused imports — 3 warnings

**Diagnostics: GHC-66111 `-Wunused-imports`, GHC-38856 `-Wunused-imports`**

| File | Line | Import | Issue |
|------|------|--------|-------|
| `Test/RangeLaws.hs` | 6 | `import Test.QuickCheck` | Instances only; no explicit names used |
| `Test/RangeOrd.hs` | 11 | `import Test.QuickCheck` | Same |
| `Test/RangeOrd.hs` | 5 | `import Data.List (sort, sortOn)` | `sort` unused; only `sortOn` used |

**Fix:**
- Change `import Test.QuickCheck` to `import Test.QuickCheck ()` in
  `Test/RangeLaws.hs` and `Test/RangeOrd.hs`. The empty import list silences
  the warning while keeping any instances in scope.
- In `Test/RangeOrd.hs`, change `import Data.List (sort, sortOn)` to
  `import Data.List (sortOn)`.

---

## Category 4: Missing type signatures — 11 warnings

**Diagnostic: GHC-38417 `-Wmissing-signatures`**

| File | Binding |
|------|---------|
| `Test/RangeMerge.hs` | `test_loadRM`, `test_invertRM`, `test_unionRM`, `test_intersectionRM`, `test_complex_laws`, `rangeMergeTestCases` |
| `Test/Range.hs` | `tests_inRange`, `test_ranges_invert`, `test_algebra_equivalence`, `tests`, `main` |

All are top-level test group definitions or lists of type
`Test`/`[Test]`/`IO ()`. GHC can infer these but `-Wall` requires explicit
signatures.

**Fix:** Add type signatures. The types are straightforward:

```haskell
-- Test/RangeMerge.hs
test_loadRM            :: Test
test_invertRM          :: Test
test_unionRM           :: Test
test_intersectionRM    :: Test
test_complex_laws      :: Test
rangeMergeTestCases    :: [Test]

-- Test/Range.hs
tests_inRange          :: Test
test_ranges_invert     :: Test
test_algebra_equivalence :: Test
tests                  :: [Test]
main                   :: IO ()
```

(`Test` here is `Test.Framework.Test`, already imported as `testGroup` in
both files — the `Test` type alias is in scope via `Test.Framework`.)

---

## Category 5: Unused top-level binding — 1 warning

**Diagnostic: GHC-40910 `-Wunused-top-binds`**

`Test/RangeParser.hs:23` — `shouldFail` is defined but no test uses it.

```haskell
shouldFail input = case (parseRanges input :: Either ParseError (Ranges Integer)) of ...
```

**Options:**

A. **Delete `shouldFail`** if there are no planned negative-parse tests.
B. **Add a test that uses it** — negative parse cases (inputs that should fail
   to parse) would be a useful addition to the parser test suite.

Option B is preferable from a coverage standpoint. If no negative test cases
are planned in the near term, option A keeps the file clean.

---

## Category 6: Type defaulting — 1 warning

**Diagnostic: GHC-18042 `-Wtype-defaults`**

`Test/Range.hs:55` — the type variable in `prop_singleton_not_in_range` is
defaulted to `Integer`:

```haskell
testProperty "unequal singletons not in range" prop_singleton_not_in_range
```

**Fix:** Add an explicit type annotation at the call site:

```haskell
testProperty "unequal singletons not in range"
  (prop_singleton_not_in_range :: UnequalPair Integer -> Bool)
```

---

## Category 7 (not actionable): Doctest Safe Haskell extension warnings

**Diagnostic: GHC-98887**

```
-XGeneralizedNewtypeDeriving is not allowed in Safe Haskell; ignoring ...
-XTemplateHaskell is not allowed in Safe Haskell; ignoring ...
```

These appear during the doctest runner's GHC invocation. Doctest compiles
example code with the module's own flags, which include `{-# LANGUAGE Safe #-}`.
Third-party dependencies (e.g. `QuickCheck`) request these extensions, but
Safe Haskell silently ignores them. The warnings come from GHC's interaction
with those dependency flags — they are not from code we own.

**Options:**
- **Suppress in doctest config**: pass `--no-magic` or a custom GHC option
  list to the doctest runner to avoid inheriting Safe flags. This requires
  changes to `DocTest.hs`.
- **Accept**: these warnings are cosmetic noise from the test harness. They
  have no impact on correctness or coverage and do not appear during the
  library build.

Recommended: accept for now; revisit if the doctest runner gains better
support for Safe Haskell module options.

---

## Category 8 (not actionable): macOS linker warning

```
ld: warning: -U option is redundant when using -undefined dynamic_lookup
```

This is emitted by Apple's linker when building the doctest executable on
macOS. It is a known upstream issue in how the GHC runtime system links on
Apple Silicon / macOS 14+. Not actionable from this codebase.

---

## Summary table

| # | Category | Diagnostic | Count | Files | Fix |
|---|----------|------------|-------|-------|-----|
| 1 | Deprecated imports | GHC-15328 | 4 | `Generators`, `RangeLaws`, `RangeOrd`, `Range` | `import Data.Ranges` |
| 2 | Missing home-modules | GHC-32850 | 1 (×3) | `range.cabal` | Remove `-fno-enable-rewrite-rules`; add modules to `other-modules` if needed |
| 3 | Unused imports | GHC-66111, GHC-38856 | 3 | `RangeLaws`, `RangeOrd` | `import Test.QuickCheck ()`; drop `sort` |
| 4 | Missing signatures | GHC-38417 | 11 | `RangeMerge`, `Range` | Add `:: Test` / `:: [Test]` / `:: IO ()` |
| 5 | Unused binding | GHC-40910 | 1 | `RangeParser` | Delete `shouldFail` or add negative test cases |
| 6 | Type defaulting | GHC-18042 | 1 | `Range` | Annotate `UnequalPair Integer -> Bool` |
| 7 | Doctest Safe HS | GHC-98887 | many | (doctest runner) | Not actionable |
| 8 | macOS linker | — | 2 | (toolchain) | Not actionable |

---

## Recommended order of changes

1. **Category 1** — change `import Data.Range` to `import Data.Ranges` (4 files). This also removes the dependency on the deprecated shim and is the highest-signal fix.
2. **Category 3** — fix unused imports (2 lines). Trivial.
3. **Category 6** — add type annotation at `testProperty` call (1 line). Trivial.
4. **Category 5** — decide on `shouldFail`: delete or write negative test cases.
5. **Category 4** — add 11 type signatures. Mechanical but verbose.
6. **Category 2** — remove `-fno-enable-rewrite-rules` from cabal; re-run to check if the missing-home-modules warning is gone.
