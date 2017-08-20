-----------------------------------------------------------------------------
-- |
-- Module     : Hadrian.Haskell.Cabal
-- Copyright  : (c) Andrey Mokhov 2014-2017
-- License    : MIT (see the file LICENSE)
-- Maintainer : andrey.mokhov@gmail.com
-- Stability  : experimental
--
-- Basic functionality for extracting Haskell package metadata stored in
-- @.cabal@ files.
-----------------------------------------------------------------------------
module Hadrian.Haskell.Cabal (
    pkgNameVersion, pkgIdentifier, pkgDependencies
    ) where

import Development.Shake

import Hadrian.Haskell.Cabal.Parse
import Hadrian.Haskell.Package
import Hadrian.Oracles.TextFile

-- | Read the @.cabal@ file of a given package and return the package name and
-- version. The @.cabal@ file is tracked.
pkgNameVersion :: Package -> Action (PackageName, String)
pkgNameVersion pkg = do
    cabal <- readCabalFile (pkgCabalFile pkg)
    return (name cabal, version cabal)

-- | Read the @.cabal@ file of a given package and return the package identifier.
-- If the @.cabal@ file does not exist return the package name. If the @.cabal@
-- file exists it is tracked.
pkgIdentifier :: Package -> Action String
pkgIdentifier pkg = do
    cabalExists <- doesFileExist (pkgCabalFile pkg)
    if cabalExists
    then do
        cabal <- readCabalFile (pkgCabalFile pkg)
        return $ if (null $ version cabal)
            then name cabal
            else name cabal ++ "-" ++ version cabal
    else return (pkgName pkg)

-- | Read the @.cabal@ file of a given package and return the sorted list of its
-- dependencies. The current version does not take care of Cabal conditionals
-- and therefore returns a crude overapproximation of actual dependencies. The
-- @.cabal@ file is tracked.
pkgDependencies :: Package -> Action [PackageName]
pkgDependencies pkg = do
    cabal <- readCabalFile (pkgCabalFile pkg)
    return (dependencies cabal)