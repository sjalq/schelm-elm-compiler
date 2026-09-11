{-# LANGUAGE TemplateHaskell #-}

module Schelm.Version
  ( short
  , full
  , elm
  , lamdera
  , upstreamCommit
  )
  where

import GitHash

import qualified Elm.Version as Elm
import qualified Ext.Common as Ext
import qualified Lamdera.Version as Lamdera


short :: String
short = "0.1.0-dev"


elm :: String
elm = Elm.toChars Elm.compiler


lamdera :: String
lamdera = Lamdera.short


upstreamCommit :: String
upstreamCommit = "63f640f0d1ea916ba92c9440bdfd21a165247e60"


full :: String
full =
  let
    info = $$tGitInfoCwd
    dirty = if giDirty info then "-dirty" else ""
  in
  concat
    [ "schelm-", short, "-", Ext.os, "-", Ext.arch, "-", giHash info, dirty
    , " (Elm ", elm, ")"
    , " (Lamdera ", lamdera, ")"
    , " (upstream-lamdera ", upstreamCommit, ")"
    ]
