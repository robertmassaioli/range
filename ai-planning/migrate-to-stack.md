# Proposal: Migrate from Cabal to Haskell Stack

## Background

This repository currently uses raw Cabal for building and testing (`cabal new-build`, `cabal new-test`). The CI pipeline (`bitbucket-pipelines.yml`) tests against multiple GHC versions (latest, 8.2, 8.0) using Cabal sandboxes for older versions. The cabal file uses `cabal-version: >=1.8` and has CPP guards for GHC < 8 compatibility (conditional `semigroups` dependency).

Since the most recent commit already removed GHC 7 support, and the library targets modern GHC, migrating to Stack with a pinned LTS resolver simplifies the build story considerably.

## Target

- **Resolver**: lts-24.36
- **GHC**: 9.10.3 (provided by the resolver)

## Changes Required

### 1. Add `stack.yaml`

Create a `stack.yaml` pointing to `lts-24.36` with the local package:

```yaml
resolver: lts-24.36
packages:
  - .
```

No extra-deps should be needed — all dependencies (`parsec`, `free`, `QuickCheck`, `test-framework`, `test-framework-quickcheck2`, `random`) are in this LTS snapshot.

### 2. Update `range.cabal`

- Bump `cabal-version` to `>=1.10` (or `2.0`) since Stack and modern Cabal expect it.
- Remove the `if impl(ghc < 8)` conditional blocks — GHC 9.10.3 makes these dead code. This means:
  - Remove the conditional `semigroups >= 0.19` dependency (it's in `base` since GHC 8.0).
  - Remove the conditional split on `free` — just use `free >= 4.12`.
- Tighten version bounds to match what's actually tested (the LTS versions).
- Add `default-language: Haskell2010` to both the library and test-suite stanzas (required by modern Cabal, currently missing).

### 3. Remove the `{-# LANGUAGE CPP #-}` / `#if` guards

With GHC < 8 support gone:
- `Data/Ranges.hs`: Remove the `#if !MIN_VERSION_base(4,8,0)` guard around `import Control.Applicative`.
- `Data/Range/Algebra/Internal.hs`: Remove the `#if MIN_VERSION_base(4,9,0)` guards around `Eq1`/`Show1` instances — these are always available on GHC 9.10.

### 4. Update `bitbucket-pipelines.yml`

Replace the multi-GHC Cabal-based pipeline with a single Stack-based step:

```yaml
image: fpco/stack-build:lts-24.36

pipelines:
  default:
    - step:
        name: "Build and Test"
        caches:
          - stack-root
          - stack-work
        script:
          - stack setup
          - stack build --test
```

Or, if Bitbucket Pipelines is no longer in use, consider replacing with GitHub Actions.

### 5. Add `stack.yaml.lock` to version control

After the first `stack build`, commit `stack.yaml.lock` so that builds are fully reproducible.

### 6. Update `.gitignore`

Add:
```
/.stack-work
```

### 7. Update `README.markdown`

Replace the installation/development instructions to use `stack` commands:
- `stack build` instead of `cabal install`
- `stack test` instead of `cabal test`

### 8. Update `CLAUDE.md`

Replace build/test commands with Stack equivalents:
- `stack build` — build the library
- `stack test` — run all tests
- `stack ghci range:test-range` — load tests in REPL for faster iteration

## Risk Assessment

- **Low risk**: This is a build tooling change only. No library code logic changes.
- **The CPP removal** is safe because GHC 7 support was already removed in the most recent commit.
- **Dependency resolution** is handled by the LTS snapshot, eliminating version bound conflicts.

## Verification

After migration:
1. `stack build` compiles cleanly with no warnings (library uses `-Wall`)
2. `stack test` passes all existing QuickCheck properties
3. `stack haddock` generates documentation without errors
