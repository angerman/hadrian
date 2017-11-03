module Settings.Packages.GhcCabal (ghcCabalPackageArgs) where

import Hadrian.Haskell.Cabal

import Base
import Expression
import Utilities
import qualified Types.Context as Context

ghcCabalPackageArgs :: Args
ghcCabalPackageArgs = stage0 ? package ghcCabal ? builder Ghc ? do
    cabalDeps    <- expr $ stage1Dependencies cabal
    ctx          <- getContext
    Just cabalVersion <- expr $ pkgVersion (ctx { Context.package = cabal }) -- TODO: improve
    mconcat
        [ pure [ "-package " ++ pkgName pkg | pkg <- cabalDeps, pkg /= parsec ]
        , arg "--make"
        , arg "-j"
        , arg ("-DCABAL_VERSION=" ++ replace "." "," cabalVersion)
        -- , arg "-DCABAL_PARSEC"
        , arg "-DBOOTSTRAPPING"
        , arg "-DMIN_VERSION_binary_0_8_0"
        , arg "-ilibraries/Cabal/Cabal"
        , arg "-ilibraries/binary/src"
        , arg "-ilibraries/filepath"
        , arg "-ilibraries/hpc"
        ]
        -- , arg "-ilibraries/mtl"
        -- , arg "-ilibraries/text"
        -- , arg "-Ilibraries/text/include"
        -- , arg "-ilibraries/parsec"
        -- ]
