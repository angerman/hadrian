%
% (c) The University of Glasgow, 2000-2006
%
\section[Finder]{Module Finder}

\begin{code}
module Finder (
    flushFinderCaches,
    FindResult(..),
    findImportedModule,
    findExactModule,
    findHomeModule,
    findExposedPackageModule,
    mkHomeModLocation,
    mkHomeModLocation2,
    mkHiOnlyModLocation,
    addHomeModuleToFinder,
    uncacheModule,
    mkStubPaths,

    findObjectLinkableMaybe,
    findObjectLinkable,

    cannotFindModule,
    cannotFindInterface,

  ) where

import Module
import HscTypes
import Packages
import FastString
import Util
import PrelNames        ( gHC_PRIM )
import DynFlags		( DynFlags(..), isOneShot, GhcMode(..) )
import Outputable
import FiniteMap
import LazyUniqFM
import Maybes		( expectJust )

import Distribution.Package hiding (PackageId)
import Data.IORef	( IORef, writeIORef, readIORef, modifyIORef )
import System.Directory
import System.FilePath
import Control.Monad
import System.Time	( ClockTime )


type FileExt = String	-- Filename extension
type BaseName = String	-- Basename of file

-- -----------------------------------------------------------------------------
-- The Finder

-- The Finder provides a thin filesystem abstraction to the rest of
-- the compiler.  For a given module, it can tell you where the
-- source, interface, and object files for that module live.

-- It does *not* know which particular package a module lives in.  Use
-- Packages.lookupModuleInAllPackages for that.

-- -----------------------------------------------------------------------------
-- The finder's cache

-- remove all the home modules from the cache; package modules are
-- assumed to not move around during a session.
flushFinderCaches :: HscEnv -> IO ()
flushFinderCaches hsc_env = do
  writeIORef fc_ref emptyUFM
  flushModLocationCache this_pkg mlc_ref
 where
	this_pkg = thisPackage (hsc_dflags hsc_env)
	fc_ref = hsc_FC hsc_env
	mlc_ref = hsc_MLC hsc_env

flushModLocationCache :: PackageId -> IORef ModLocationCache -> IO ()
flushModLocationCache this_pkg ref = do
  fm <- readIORef ref
  writeIORef ref $! filterFM is_ext fm
  return ()
  where is_ext mod _ | modulePackageId mod /= this_pkg = True
		     | otherwise = False

addToFinderCache :: IORef FinderCache -> ModuleName -> FindResult -> IO ()
addToFinderCache       ref key val = modifyIORef ref $ \c -> addToUFM c key val

addToModLocationCache :: IORef ModLocationCache -> Module -> ModLocation -> IO ()
addToModLocationCache  ref key val = modifyIORef ref $ \c -> addToFM c key val

removeFromFinderCache :: IORef FinderCache -> ModuleName -> IO ()
removeFromFinderCache      ref key = modifyIORef ref $ \c -> delFromUFM c key

removeFromModLocationCache :: IORef ModLocationCache -> Module -> IO ()
removeFromModLocationCache ref key = modifyIORef ref $ \c -> delFromFM c key

lookupFinderCache :: IORef FinderCache -> ModuleName -> IO (Maybe FindResult)
lookupFinderCache ref key = do 
   c <- readIORef ref
   return $! lookupUFM c key

lookupModLocationCache :: IORef ModLocationCache -> Module
                       -> IO (Maybe ModLocation)
lookupModLocationCache ref key = do
   c <- readIORef ref
   return $! lookupFM c key

-- -----------------------------------------------------------------------------
-- The two external entry points

-- | Locate a module that was imported by the user.  We have the
-- module's name, and possibly a package name.  Without a package
-- name, this function will use the search path and the known exposed
-- packages to find the module, if a package is specified then only
-- that package is searched for the module.

findImportedModule :: HscEnv -> ModuleName -> Maybe FastString -> IO FindResult
findImportedModule hsc_env mod_name mb_pkg =
  case mb_pkg of
	Nothing                        -> unqual_import
	Just pkg | pkg == fsLit "this" -> home_import -- "this" is special
	         | otherwise           -> pkg_import
  where
    home_import   = findHomeModule hsc_env mod_name

    pkg_import    = findExposedPackageModule hsc_env mod_name mb_pkg

    unqual_import = home_import 
			`orIfNotFound`
		      findExposedPackageModule hsc_env mod_name Nothing

-- | Locate a specific 'Module'.  The purpose of this function is to
-- create a 'ModLocation' for a given 'Module', that is to find out
-- where the files associated with this module live.  It is used when
-- reading the interface for a module mentioned by another interface, 
-- for example (a "system import").

findExactModule :: HscEnv -> Module -> IO FindResult
findExactModule hsc_env mod =
   let dflags = hsc_dflags hsc_env in
   if modulePackageId mod == thisPackage dflags
	then findHomeModule hsc_env (moduleName mod)
	else findPackageModule hsc_env mod

-- -----------------------------------------------------------------------------
-- Helpers

orIfNotFound :: IO FindResult -> IO FindResult -> IO FindResult
this `orIfNotFound` or_this = do
  res <- this
  case res of
    NotFound places1 _mb_pkg1 mod_hiddens1 pkg_hiddens1 -> do
	res2 <- or_this
	case res2 of
	   NotFound places2 mb_pkg2 mod_hiddens2 pkg_hiddens2 -> 
              return (NotFound (places1 ++ places2)
                               mb_pkg2 -- snd arg is the package search
                               (mod_hiddens1 ++ mod_hiddens2)
                               (pkg_hiddens1 ++ pkg_hiddens2))
	   _other -> return res2
    _other -> return res


homeSearchCache :: HscEnv -> ModuleName -> IO FindResult -> IO FindResult
homeSearchCache hsc_env mod_name do_this = do
  m <- lookupFinderCache (hsc_FC hsc_env) mod_name
  case m of 
    Just result -> return result
    Nothing     -> do
	result <- do_this
	addToFinderCache (hsc_FC hsc_env) mod_name result
	case result of
	   Found loc mod -> addToModLocationCache (hsc_MLC hsc_env) mod loc
	   _other        -> return ()
	return result

findExposedPackageModule :: HscEnv -> ModuleName -> Maybe FastString
                         -> IO FindResult
findExposedPackageModule hsc_env mod_name mb_pkg
        -- not found in any package:
  | null found_exposed = return (NotFound [] Nothing mod_hiddens pkg_hiddens)
        -- found in just one exposed package:
  | [(pkg_conf, _)] <- found_exposed
        = let pkgid = packageConfigId pkg_conf in
          findPackageModule_ hsc_env (mkModule pkgid mod_name) pkg_conf
  | otherwise
        = return (FoundMultiple (map (packageConfigId.fst) found_exposed))
  where
	dflags = hsc_dflags hsc_env
        found = lookupModuleInAllPackages dflags mod_name

        for_this_pkg = filter ((`matches` mb_pkg) . fst) found

        found_exposed = [ (pkg_conf,exposed_mod) 
                        | x@(pkg_conf,exposed_mod) <- for_this_pkg,
                          is_exposed x ]

        is_exposed (pkg_conf,exposed_mod) = exposed pkg_conf && exposed_mod

        mod_hiddens = [ packageConfigId pkg_conf
                      | (pkg_conf,False) <- found ]

        pkg_hiddens = [ packageConfigId pkg_conf
                      | (pkg_conf,_) <- found, not (exposed pkg_conf) ]

        _pkg_conf `matches` Nothing  = True
        pkg_conf  `matches` Just pkg =
           case packageName pkg_conf of 
              PackageName n -> pkg == mkFastString n


modLocationCache :: HscEnv -> Module -> IO FindResult -> IO FindResult
modLocationCache hsc_env mod do_this = do
  mb_loc <- lookupModLocationCache mlc mod
  case mb_loc of
     Just loc -> return (Found loc mod)
     Nothing  -> do
        result <- do_this
	case result of
    	    Found loc mod -> addToModLocationCache (hsc_MLC hsc_env) mod loc
    	    _other -> return ()
	return result
  where
    mlc = hsc_MLC hsc_env

addHomeModuleToFinder :: HscEnv -> ModuleName -> ModLocation -> IO Module
addHomeModuleToFinder hsc_env mod_name loc = do
  let mod = mkModule (thisPackage (hsc_dflags hsc_env)) mod_name
  addToFinderCache (hsc_FC hsc_env) mod_name (Found loc mod)
  addToModLocationCache (hsc_MLC hsc_env) mod loc
  return mod

uncacheModule :: HscEnv -> ModuleName -> IO ()
uncacheModule hsc_env mod = do
  let this_pkg = thisPackage (hsc_dflags hsc_env)
  removeFromFinderCache (hsc_FC hsc_env) mod
  removeFromModLocationCache (hsc_MLC hsc_env) (mkModule this_pkg mod)

-- -----------------------------------------------------------------------------
-- 	The internal workers

-- | Search for a module in the home package only.
findHomeModule :: HscEnv -> ModuleName -> IO FindResult
findHomeModule hsc_env mod_name =
   homeSearchCache hsc_env mod_name $
   let 
     dflags = hsc_dflags hsc_env
     home_path = importPaths dflags
     hisuf = hiSuf dflags
     mod = mkModule (thisPackage dflags) mod_name

     source_exts = 
      [ ("hs",   mkHomeModLocationSearched dflags mod_name "hs")
      , ("lhs",  mkHomeModLocationSearched dflags mod_name "lhs")
      ]
     
     hi_exts = [ (hisuf,  	 	mkHiOnlyModLocation dflags hisuf)
	       , (addBootSuffix hisuf,	mkHiOnlyModLocation dflags hisuf)
	       ]
     
     	-- In compilation manager modes, we look for source files in the home
     	-- package because we can compile these automatically.  In one-shot
     	-- compilation mode we look for .hi and .hi-boot files only.
     exts | isOneShot (ghcMode dflags) = hi_exts
          | otherwise      	       = source_exts
   in

  -- special case for GHC.Prim; we won't find it in the filesystem.
  -- This is important only when compiling the base package (where GHC.Prim
  -- is a home module).
  if mod == gHC_PRIM 
        then return (Found (error "GHC.Prim ModLocation") mod)
        else 

   searchPathExts home_path mod exts


-- | Search for a module in external packages only.
findPackageModule :: HscEnv -> Module -> IO FindResult
findPackageModule hsc_env mod = do
  let
	dflags = hsc_dflags hsc_env
	pkg_id = modulePackageId mod
	pkg_map = pkgIdMap (pkgState dflags)
  --
  case lookupPackage pkg_map pkg_id of
     Nothing -> return (NoPackage pkg_id)
     Just pkg_conf -> findPackageModule_ hsc_env mod pkg_conf
      
findPackageModule_ :: HscEnv -> Module -> PackageConfig -> IO FindResult
findPackageModule_ hsc_env mod pkg_conf = 
  modLocationCache hsc_env mod $

  -- special case for GHC.Prim; we won't find it in the filesystem.
  if mod == gHC_PRIM 
        then return (Found (error "GHC.Prim ModLocation") mod)
        else 

  let
     dflags = hsc_dflags hsc_env
     tag = buildTag dflags

	   -- hi-suffix for packages depends on the build tag.
     package_hisuf | null tag  = "hi"
		   | otherwise = tag ++ "_hi"

     mk_hi_loc = mkHiOnlyModLocation dflags package_hisuf

     import_dirs = importDirs pkg_conf
      -- we never look for a .hi-boot file in an external package;
      -- .hi-boot files only make sense for the home package.
  in
  case import_dirs of
    [one] | MkDepend <- ghcMode dflags -> do
          -- there's only one place that this .hi file can be, so
          -- don't bother looking for it.
          let basename = moduleNameSlashes (moduleName mod)
          loc <- mk_hi_loc one basename
          return (Found loc mod)
    _otherwise ->
          searchPathExts import_dirs mod [(package_hisuf, mk_hi_loc)]

-- -----------------------------------------------------------------------------
-- General path searching

searchPathExts
  :: [FilePath]		-- paths to search
  -> Module		-- module name
  -> [ (
	FileExt,				-- suffix
	FilePath -> BaseName -> IO ModLocation  -- action
       )
     ] 
  -> IO FindResult

searchPathExts paths mod exts 
   = do result <- search to_search
{-
	hPutStrLn stderr (showSDoc $
		vcat [text "Search" <+> ppr mod <+> sep (map (text. fst) exts)
		    , nest 2 (vcat (map text paths))
		    , case result of
			Succeeded (loc, p) -> text "Found" <+> ppr loc
			Failed fs	   -> text "not found"])
-}	
	return result

  where
    basename = moduleNameSlashes (moduleName mod)

    to_search :: [(FilePath, IO ModLocation)]
    to_search = [ (file, fn path basename)
		| path <- paths, 
		  (ext,fn) <- exts,
		  let base | path == "." = basename
	     	           | otherwise   = path </> basename
	              file = base <.> ext
		]

    search [] = return (NotFound (map fst to_search) (Just (modulePackageId mod))
                        [] [])
    search ((file, mk_result) : rest) = do
      b <- doesFileExist file
      if b 
	then do { loc <- mk_result; return (Found loc mod) }
	else search rest

mkHomeModLocationSearched :: DynFlags -> ModuleName -> FileExt
		          -> FilePath -> BaseName -> IO ModLocation
mkHomeModLocationSearched dflags mod suff path basename = do
   mkHomeModLocation2 dflags mod (path </> basename) suff

-- -----------------------------------------------------------------------------
-- Constructing a home module location

-- This is where we construct the ModLocation for a module in the home
-- package, for which we have a source file.  It is called from three
-- places:
--
--  (a) Here in the finder, when we are searching for a module to import,
--      using the search path (-i option).
--
--  (b) The compilation manager, when constructing the ModLocation for
--      a "root" module (a source file named explicitly on the command line
--      or in a :load command in GHCi).
--
--  (c) The driver in one-shot mode, when we need to construct a
--      ModLocation for a source file named on the command-line.
--
-- Parameters are:
--
-- mod
--      The name of the module
--
-- path
--      (a): The search path component where the source file was found.
--      (b) and (c): "."
--
-- src_basename
--      (a): (moduleNameSlashes mod)
--      (b) and (c): The filename of the source file, minus its extension
--
-- ext
--	The filename extension of the source file (usually "hs" or "lhs").

mkHomeModLocation :: DynFlags -> ModuleName -> FilePath -> IO ModLocation
mkHomeModLocation dflags mod src_filename = do
   let (basename,extension) = splitExtension src_filename
   mkHomeModLocation2 dflags mod basename extension

mkHomeModLocation2 :: DynFlags
		   -> ModuleName
		   -> FilePath 	-- Of source module, without suffix
		   -> String 	-- Suffix
		   -> IO ModLocation
mkHomeModLocation2 dflags mod src_basename ext = do
   let mod_basename = moduleNameSlashes mod

   obj_fn  <- mkObjPath  dflags src_basename mod_basename
   hi_fn   <- mkHiPath   dflags src_basename mod_basename

   return (ModLocation{ ml_hs_file   = Just (src_basename <.> ext),
			ml_hi_file   = hi_fn,
			ml_obj_file  = obj_fn })

mkHiOnlyModLocation :: DynFlags -> Suffix -> FilePath -> String
		    -> IO ModLocation
mkHiOnlyModLocation dflags hisuf path basename
 = do let full_basename = path </> basename
      obj_fn  <- mkObjPath  dflags full_basename basename
      return ModLocation{    ml_hs_file   = Nothing,
 	        	     ml_hi_file   = full_basename <.> hisuf,
		 		-- Remove the .hi-boot suffix from
		 		-- hi_file, if it had one.  We always
		 		-- want the name of the real .hi file
		 		-- in the ml_hi_file field.
	   	             ml_obj_file  = obj_fn
                  }

-- | Constructs the filename of a .o file for a given source file.
-- Does /not/ check whether the .o file exists
mkObjPath
  :: DynFlags
  -> FilePath		-- the filename of the source file, minus the extension
  -> String		-- the module name with dots replaced by slashes
  -> IO FilePath
mkObjPath dflags basename mod_basename
  = do  let
		odir = objectDir dflags
		osuf = objectSuf dflags
	
		obj_basename | Just dir <- odir = dir </> mod_basename
			     | otherwise        = basename

        return (obj_basename <.> osuf)

-- | Constructs the filename of a .hi file for a given source file.
-- Does /not/ check whether the .hi file exists
mkHiPath
  :: DynFlags
  -> FilePath		-- the filename of the source file, minus the extension
  -> String		-- the module name with dots replaced by slashes
  -> IO FilePath
mkHiPath dflags basename mod_basename
  = do  let
		hidir = hiDir dflags
		hisuf = hiSuf dflags

		hi_basename | Just dir <- hidir = dir </> mod_basename
			    | otherwise         = basename

        return (hi_basename <.> hisuf)


-- -----------------------------------------------------------------------------
-- Filenames of the stub files

-- We don't have to store these in ModLocations, because they can be derived
-- from other available information, and they're only rarely needed.

mkStubPaths
  :: DynFlags
  -> ModuleName
  -> ModLocation
  -> (FilePath,FilePath,FilePath)

mkStubPaths dflags mod location
  = let
        stubdir = stubDir dflags

        mod_basename = moduleNameSlashes mod
        src_basename = dropExtension $ expectJust "mkStubPaths" 
                                                  (ml_hs_file location)

        stub_basename0
            | Just dir <- stubdir = dir </> mod_basename
            | otherwise           = src_basename

        stub_basename = stub_basename0 ++ "_stub"

        obj  = ml_obj_file location
        osuf = objectSuf dflags
        stub_obj_base = dropTail (length osuf + 1) obj ++ "_stub"
                        -- NB. not takeFileName, see #3093
     in
        (stub_basename <.> "c",
         stub_basename <.> "h",
         stub_obj_base <.> objectSuf dflags)

-- -----------------------------------------------------------------------------
-- findLinkable isn't related to the other stuff in here, 
-- but there's no other obvious place for it

findObjectLinkableMaybe :: Module -> ModLocation -> IO (Maybe Linkable)
findObjectLinkableMaybe mod locn
   = do let obj_fn = ml_obj_file locn
	maybe_obj_time <- modificationTimeIfExists obj_fn
	case maybe_obj_time of
	  Nothing -> return Nothing
	  Just obj_time -> liftM Just (findObjectLinkable mod obj_fn obj_time)

-- Make an object linkable when we know the object file exists, and we know
-- its modification time.
findObjectLinkable :: Module -> FilePath -> ClockTime -> IO Linkable
findObjectLinkable mod obj_fn obj_time = do
  let stub_fn = (dropExtension obj_fn ++ "_stub") <.> "o"
  stub_exist <- doesFileExist stub_fn
  if stub_exist
	then return (LM obj_time mod [DotO obj_fn, DotO stub_fn])
	else return (LM obj_time mod [DotO obj_fn])

-- -----------------------------------------------------------------------------
-- Error messages

cannotFindModule :: DynFlags -> ModuleName -> FindResult -> SDoc
cannotFindModule = cantFindErr (sLit "Could not find module")
                               (sLit "Ambiguous module name")

cannotFindInterface  :: DynFlags -> ModuleName -> FindResult -> SDoc
cannotFindInterface = cantFindErr (sLit "Failed to load interface for")
                                  (sLit "Ambiguous interface for")

cantFindErr :: LitString -> LitString -> DynFlags -> ModuleName -> FindResult
            -> SDoc
cantFindErr _ multiple_found _ mod_name (FoundMultiple pkgs)
  = hang (ptext multiple_found <+> quotes (ppr mod_name) <> colon) 2 (
       sep [ptext (sLit "it was found in multiple packages:"),
		hsep (map (text.packageIdString) pkgs)]
    )
cantFindErr cannot_find _ dflags mod_name find_result
  = hang (ptext cannot_find <+> quotes (ppr mod_name) <> colon)
       2 more_info
  where
    more_info
      = case find_result of
	    NoPackage pkg
		-> ptext (sLit "no package matching") <+> quotes (ppr pkg) <+>
		   ptext (sLit "was found")

	    NotFound files mb_pkg mod_hiddens pkg_hiddens
		| Just pkg <- mb_pkg, pkg /= thisPackage dflags
		-> not_found_in_package pkg files

                | null files && null mod_hiddens && null pkg_hiddens
		-> ptext (sLit "it is not a module in the current program, or in any known package.")

		| otherwise
		-> vcat (map pkg_hidden pkg_hiddens) $$
                   vcat (map mod_hidden mod_hiddens) $$ 
                   tried_these files

	    NotFoundInPackage pkg
		-> ptext (sLit "it is not in package") <+> quotes (ppr pkg)

	    _ -> panic "cantFindErr"

    build_tag = buildTag dflags

    not_found_in_package pkg files
       | build_tag /= ""
       = let
            build = if build_tag == "p" then "profiling"
                                        else "\"" ++ build_tag ++ "\""
         in
         ptext (sLit "Perhaps you haven't installed the ") <> text build <>
         ptext (sLit " libraries for package ") <> quotes (ppr pkg) <> char '?' $$
         tried_these files

       | otherwise
       = ptext (sLit "There are files missing in the ") <> quotes (ppr pkg) <>
         ptext (sLit " package,") $$
         ptext (sLit "try running 'ghc-pkg check'.") $$
         tried_these files

    tried_these files
        | null files = empty
        | verbosity dflags < 3 =
   	      ptext (sLit "Use -v to see a list of the files searched for.")
        | otherwise =
               hang (ptext (sLit "locations searched:")) 2 $ vcat (map text files)
        
    pkg_hidden pkg =
        ptext (sLit "it is a member of the hidden package") <+> quotes (ppr pkg)

    mod_hidden pkg =
        ptext (sLit "it is a hidden module in the package") <+> quotes (ppr pkg)
\end{code}
