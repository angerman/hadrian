module Settings.Flavours.Quickest (quickestFlavour) where

import Flavour
import Expression
import {-# SOURCE #-} Settings.Default

quickestFlavour :: Flavour
quickestFlavour = defaultFlavour
    { name        = "quickest"
    , args        = defaultBuilderArgs <> quickestArgs <> defaultPackageArgs
    , libraryWays = pure [vanilla]
    , rtsWays     = quickestRtsWays }

quickestArgs :: Args
quickestArgs = sourceArgs SourceArgs
    { hsDefault  = pure ["-O0", "-H64m"]
    , hsLibrary  = mempty
    , hsCompiler = stage0 ? arg "-O"
    , hsGhc      = stage0 ? arg "-O" }

quickestRtsWays :: Ways
quickestRtsWays = mconcat
    [ pure [vanilla]
    , buildHaddock defaultFlavour ? pure [threaded] ]
