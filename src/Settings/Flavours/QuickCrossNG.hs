module Settings.Flavours.QuickCrossNG (quickCrossNGFlavour) where

import Expression
import Types.Flavour
import {-# SOURCE #-} Settings.Default
import GHC.Packages

llvmngPackages :: [Package]
llvmngPackages = [ dataBitcode, dataBitcodeLlvm, dataBitcodeEdsl ]

dataBitcode, dataBitcodeLlvm, dataBitcodeEdsl :: Package
dataBitcode         = hsLib  "data-bitcode"
dataBitcodeLlvm     = hsLib  "data-bitcode-llvm"
dataBitcodeEdsl     = hsLib  "data-bitcode-edsl"

llvmngWarningArgs :: Args
llvmngWarningArgs = builder Ghc ?
  mconcat [ package dataBitcode  ? pure [ "-Wno-name-shadowing"
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

-- Please update doc/flavours.md when changing this file.
quickCrossNGFlavour :: Flavour
quickCrossNGFlavour = defaultFlavour
    { name        = "quick-cross-ng"
    , args        = defaultBuilderArgs <> quickCrossNGArgs <> defaultPackageArgs <> llvmngWarningArgs
    , integerLibrary = pure integerSimple
    , libraryWays = pure [vanilla]
    , extraPackages = llvmngPackages
    , packages    = fmap (++ llvmngPackages) . packages defaultFlavour
    }

quickCrossNGArgs :: Args
quickCrossNGArgs = sourceArgs SourceArgs
    { hsDefault  = pure ["-O0", "-H64m"]
    , hsLibrary  = notStage0 ? mconcat [ arg "-O", arg "-fllvmng" ]
    , hsCompiler = stage0 ? arg "-O"
    , hsGhc      = mconcat
                   [ stage0 ? arg "-O"
                   , stage1 ? mconcat [ arg "-O0", arg "-fllvmng" ] ] }