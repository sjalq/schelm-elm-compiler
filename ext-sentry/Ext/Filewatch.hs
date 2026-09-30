{-# LANGUAGE OverloadedStrings #-}

module Ext.Filewatch where

import Ext.Common
import qualified System.FSNotify as FSNotify
import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import qualified Data.List as List
import qualified Control.FoldDebounce as Debounce
import qualified System.FilePath as FP
import System.FilePath ((</>))
import qualified System.Directory as Dir
import qualified Elm.Outline as Outline
import qualified Data.NonEmptyList as NE


resolveSourceDirs :: FilePath -> IO [FilePath]
resolveSourceDirs root = do
  exists <- Dir.doesFileExist (root </> "elm.json")
  if not exists
    then return [root]
    else do
      result <- Outline.read root False
      return $ case result of
        Right (Outline.App outline) ->
          map (resolveSrcDir root) (NE.toList (Outline._app_source_dirs outline))
        Right (Outline.Pkg _) ->
          [root </> "src"]
        Left _ ->
          [root]


resolveSrcDir :: FilePath -> Outline.SrcDir -> FilePath
resolveSrcDir root srcDir =
  case srcDir of
    Outline.AbsoluteSrcDir dir -> dir
    Outline.RelativeSrcDir dir -> root </> dir


watch :: FilePath -> ([FilePath] -> IO ()) -> IO ()
watch root action = do
  srcDirs <- resolveSourceDirs root

  let config = FSNotify.defaultConfig { FSNotify.confOnHandlerException = \e -> Ext.Common.debug ("fsnotify: handler threw exception: " <> show e) }

  trackedForkIO "Ext.Filewatch.watch" $ FSNotify.withManagerConf config $ \mgr -> do
    trigger <-
      Debounce.new
        Debounce.Args
          { Debounce.cb = (\events -> action events)
          , Debounce.fold = (\l v -> List.nub $ v:l)
          , Debounce.init = []
          }
        Debounce.def
          { Debounce.delay = 10000 -- 10ms
          , Debounce.alwaysResetTimer = True
          }

    Ext.Common.debug $ "👀 file watch booting for " ++ show root ++ " with source dirs: " ++ show srcDirs
    -- start a watching job (in the background)
    _ <- FSNotify.watchTree
      mgr          -- manager
      root         -- directory to watch
      (const True) -- predicate
      (\e -> do
        let
          filepath = case e of
            FSNotify.Added f _ _ -> f
            FSNotify.Modified f _ _ -> f
            FSNotify.ModifiedAttributes f _ _ -> f
            FSNotify.Removed f _ _ -> f
            FSNotify.WatchedDirectoryRemoved f _ _ -> f
            FSNotify.CloseWrite f _ _ -> f
            FSNotify.Unknown f _ _ _ -> f

          -- @TODO it would be better to not listen to these folders in the `watchTree` when available
          -- https://github.com/haskell-fswatch/hfsnotify/issues/101
          shouldRefresh = do
                not (List.isInfixOf ".git" filepath)
             && not (List.isInfixOf ".jj" filepath)
             && not (List.isInfixOf ".watchman-cookie-" filepath)
             && not (List.isInfixOf "elm-stuff" filepath)
             && not (List.isInfixOf "node_modules" filepath)
            --  This is really dumb of you because some people use `/data/...` as a folder...
            --  && not (List.isInfixOf "data" filepath)
             && not (List.isInfixOf "elm-pkg-js-includes.min.js" filepath)
             && not (List.isInfixOf "tests" filepath)
             && isBuildOrServeRelevant filepath

          isBuildOrServeRelevant path =
               isInSourceDirs srcDirs path
            || path == root </> "elm.json"
            || isUnder (root </> "elm-pkg-js") path
            || path == root </> "esbuild.config.js"
            || path == root </> "head.html"
            || isUnder (root </> "public") path

          isInSourceDirs dirs path =
            FP.takeExtension path == ".elm"
            && any (\dir -> isUnder dir path) dirs

          isUnder dir path =
            List.isPrefixOf (FP.addTrailingPathSeparator dir) path

          indicator = if shouldRefresh then "👀 file event" else "🙈 ignoring  "

        Ext.Common.debug $ indicator ++ " " ++ show e
        onlyWhen shouldRefresh $ Debounce.send trigger filepath
      )

    -- sleep forever (until interrupted)
    forever $ threadDelay 1000000


watchFile :: FilePath -> ([FilePath] -> IO ()) -> IO ()
watchFile file action =
  watch (FP.takeDirectory file) action
