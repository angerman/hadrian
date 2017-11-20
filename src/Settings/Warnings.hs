module Settings.Warnings (defaultGhcWarningsArgs, warningArgs) where

import Expression
import Oracles.Flag
import Oracles.Setting
import Settings
import GHC.Packages

-- See @mk/warnings.mk@ for warning-related arguments in the Make build system.

-- | Default Haskell warning-related arguments.
defaultGhcWarningsArgs :: Args
defaultGhcWarningsArgs = mconcat
    [ notStage0 ? pure [ "-Werror", "-Wnoncanonical-monad-instances" ]
    , (not <$> flag GccIsClang) ? mconcat
      [ (not <$> windowsHost ) ? arg "-optc-Werror=unused-but-set-variable"
      , arg "-optc-Wno-error=inline" ]
    , flag GccIsClang ? arg "-optc-Wno-unknown-pragmas" ]

-- | Package-specific warnings-related arguments, mostly suppressing various warnings.
warningArgs :: Args
warningArgs = builder Ghc ? do
    isIntegerSimple <- (== integerSimple) <$> getIntegerPackage
    mconcat
        [ stage0 ? mconcat
        [ libraryPackage       ? pure [ "-fno-warn-deprecated-flags" ]
        , package terminfo     ? pure [ "-fno-warn-unused-imports" ]
        , package transformers ? pure [ "-fno-warn-unused-matches"
                                      , "-fno-warn-unused-imports" ] ]
        , notStage0 ? mconcat
        [ libraryPackage       ? pure [ "-Wno-deprecated-flags" ]
        , package base         ? pure [ "-Wno-trustworthy-safe" ]
        , package binary       ? pure [ "-Wno-deprecations" ]
        , package bytestring   ? pure [ "-Wno-inline-rule-shadowing" ]
        , package compiler     ? pure [ "-Wcpp-undef" ]
        -- FIXME: See https://phabricator.haskell.org/D4121#117481.
        , input "//SysTools.hs" ? pure [ "-Wno-unused-imports" ]
        , package directory    ? pure [ "-Wno-unused-imports" ]
        , package ghc          ? pure [ "-Wcpp-undef" ]
        , package ghcPrim      ? pure [ "-Wno-trustworthy-safe" ]
        , package haddock      ? pure [ "-Wno-unused-imports"
                                      , "-Wno-deprecations" ]
        , package haskeline    ? pure [ "-Wno-deprecations"
                                      , "-Wno-unused-imports"
                                      , "-Wno-redundant-constraints"
                                      , "-Wno-simplifiable-class-constraints" ]
        , package pretty       ? pure [ "-Wno-unused-imports" ]
        , package primitive    ? pure [ "-Wno-unused-imports"
                                      , "-Wno-deprecations" ]
        , package rts          ? pure [ "-Wcpp-undef" ]
        , package terminfo     ? pure [ "-Wno-unused-imports" ]
        , isIntegerSimple      ?
          package text         ? pure [ "-Wno-unused-imports" ]
        , package transformers ? pure [ "-Wno-unused-matches"
                                      , "-Wno-unused-imports"
                                      , "-Wno-redundant-constraints"
                                      , "-Wno-orphans" ]
        , package win32        ? pure [ "-Wno-trustworthy-safe" ]
        , package xhtml        ? pure [ "-Wno-unused-imports" ] ]
        , package dataBitcode  ? pure [ "-Wno-name-shadowing"
                                      , "-Wno-unused-top-binds"
                                      , "-Wno-unused-matches"
                                      , "-Wno-orphans"
                                      , "-Wno-incomplete-patterns"
                                      , "-Wno-unused-do-bind"
                                      , "-Wno-unused-imports"
                                      , "-Wno-missing-methods"
                                      , "-Wno-type-defaults"
                                      ]
        , package dataBitcodeLlvm ? pure [ "-Wno-name-shadowing"
                                      , "-Wno-unused-top-binds"
                                      , "-Wno-unused-matches"
                                      , "-Wno-orphans"
                                      , "-Wno-incomplete-patterns"
                                      , "-Wno-unused-do-bind"
                                      , "-Wno-unused-imports"
                                      , "-Wno-missing-methods"
                                      , "-Wno-unused-local-binds"
                                      , "-Wno-overlapping-patterns"
                                      , "-Wno-type-defaults"
                                      ]
        , package dataBitcodeEdsl ? pure [ "-Wno-name-shadowing"
                                      , "-Wno-unused-top-binds"
                                      , "-Wno-unused-matches"
                                      , "-Wno-orphans"
                                      , "-Wno-incomplete-patterns"
                                      , "-Wno-unused-do-bind"
                                      , "-Wno-unused-imports"
                                      , "-Wno-missing-methods"
                                      , "-Wno-type-defaults"
                                      , "-Wno-unused-local-binds"
                                      , "-Wno-overlapping-patterns"
                                      , "-Wno-type-defaults"
                                      , "-Wno-missing-signatures"
                                      ]
        ]