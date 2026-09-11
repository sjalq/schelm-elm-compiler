{-# LANGUAGE OverloadedStrings #-}

module Deps.Schelm
  ( Config
  , Origin(..)
  , Pin(..)
  , empty
  , read
  , readAt
  , sourceOrigins
  , hasCustomSource
  , rootOrigin
  , dependencyOrigins
  , pinFor
  , recordPin
  , setSource
  , snapshot
  , restore
  , persistResolved
  , fetchVersions
  , isGitPackage
  , prepareOfficial
  , prepareGit
  )
  where

import Prelude hiding (read)
import Control.Exception (IOException, try)
import Control.Monad (filterM, foldM, forM)
import Crypto.Hash (Digest, SHA256, hashlazy)
import qualified Data.Aeson as A
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.UTF8 as BS_UTF8
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import qualified Data.Text as Text
import qualified System.Directory as Dir
import qualified System.Exit as Exit
import qualified System.FilePath as FP
import System.FilePath ((</>))
import qualified System.IO.Temp as Temp
import qualified System.Process as Process

import qualified Elm.Outline as Outline
import qualified Elm.Package as Pkg
import qualified Elm.Version as V
import qualified Parse.Primitives as P


fileName :: FilePath
fileName = "schelm.json"


markerName :: FilePath
markerName = ".schelm-origin.json"


isGitPackage :: FilePath -> IO Bool
isGitPackage packageRoot =
  Dir.doesFileExist (packageRoot </> markerName)


data Origin
  = Official
  | Git String
  deriving (Eq, Ord, Show)


data Pin =
  Pin
    { _pinSource :: !String
    , _pinVersion :: !V.Version
    , _pinCommit :: !String
    , _pinSha256 :: !String
    }
  deriving (Eq, Show)


data RawPin =
  RawPin
    { _rawSource :: !String
    , _rawVersion :: !String
    , _rawCommit :: !(Maybe String)
    , _rawSha256 :: !(Maybe String)
    }
  deriving (Eq, Show)


data Manifest =
  Manifest
    { _format :: !Int
    , _rawSources :: !(Map Text.Text Text.Text)
    , _compatibility :: !(Maybe A.Value)
    , _rawResolved :: !(Map Text.Text RawPin)
    }
  deriving (Eq, Show)


data Config =
  Config
    { _root :: !FilePath
    , _exists :: !Bool
    , _manifest :: !Manifest
    , _sources :: !(Map Pkg.Name String)
    , _pins :: !(Map Pkg.Name Pin)
    }
  deriving (Eq, Show)


instance A.FromJSON RawPin where
  parseJSON = A.withObject "resolved package" $ \obj ->
    RawPin
      <$> obj A..: "source"
      <*> obj A..: "version"
      <*> obj A..:? "commit"
      <*> obj A..:? "sha256"


instance A.ToJSON RawPin where
  toJSON pin =
    A.object $
      [ "source" A..= _rawSource pin
      , "version" A..= _rawVersion pin
      ]
      ++ maybe [] (\commit -> ["commit" A..= commit]) (_rawCommit pin)
      ++ maybe [] (\digest -> ["sha256" A..= digest]) (_rawSha256 pin)


instance A.FromJSON Manifest where
  parseJSON = A.withObject "schelm.json" $ \obj ->
    Manifest
      <$> obj A..:? "format" A..!= 1
      <*> obj A..:? "sources" A..!= Map.empty
      <*> obj A..:? "compatibility"
      <*> obj A..:? "resolved" A..!= Map.empty


instance A.ToJSON Manifest where
  toJSON manifest =
    A.object $
      [ "format" A..= _format manifest
      , "sources" A..= _rawSources manifest
      ]
      ++ maybe [] (\compatibility -> ["compatibility" A..= compatibility]) (_compatibility manifest)
      ++ ["resolved" A..= _rawResolved manifest]


empty :: FilePath -> Config
empty root = Config root False (Manifest 1 Map.empty Nothing Map.empty) Map.empty Map.empty


read :: IO (Either String Config)
read =
  do  cwd <- Dir.getCurrentDirectory
      maybeRoot <- findRoot cwd
      case maybeRoot of
        Nothing -> return (Right (empty cwd))
        Just root -> readAt root


findRoot :: FilePath -> IO (Maybe FilePath)
findRoot dir =
  do  hasElmJson <- Dir.doesFileExist (dir </> "elm.json")
      if hasElmJson
        then return (Just dir)
        else
          let parent = FP.takeDirectory dir in
          if parent == dir then return Nothing else findRoot parent


readAt :: FilePath -> IO (Either String Config)
readAt root =
  do  let path = root </> fileName
      exists <- Dir.doesFileExist path
      if not exists
        then return (Right (empty root))
        else
          do  bytes <- BS.readFile path
              case A.eitherDecodeStrict' bytes of
                Left problem -> return (Left ("I could not decode " ++ path ++ ": " ++ problem))
                Right manifest ->
                  case decodeManifest root manifest of
                    Left problem -> return (Left problem)
                    Right config -> return (Right config { _exists = True })


decodeManifest :: FilePath -> Manifest -> Either String Config
decodeManifest root manifest =
  if _format manifest /= 1
    then Left ("Unsupported schelm.json format: " ++ show (_format manifest))
    else
      do  sources <- traverseMapWithKey decodeSource (_rawSources manifest)
          pins <- fmap Map.fromList $ fmap concat $ forM (Map.toList (_rawResolved manifest)) $ \(rawName, rawPin) ->
            do  name <- parsePackage (Text.unpack rawName)
                case decodePin rawPin of
                  Left problem -> Left ("Invalid resolution for " ++ Text.unpack rawName ++ ": " ++ problem)
                  Right Nothing -> Right []
                  Right (Just pin) -> Right [(name, pin)]
          return (Config root False manifest sources pins)


decodeSource :: Text.Text -> Text.Text -> Either String (Pkg.Name, String)
decodeSource rawName rawSource =
  do  name <- parsePackage (Text.unpack rawName)
      source <- validateRemote (Text.unpack rawSource)
      return (name, source)


decodePin :: RawPin -> Either String (Maybe Pin)
decodePin raw =
  if _rawSource raw == "elm-registry"
    then Right Nothing
    else
      do  version <- parseVersion (_rawVersion raw)
          source <- validateRemote (_rawSource raw)
          case (_rawCommit raw, _rawSha256 raw) of
            (Just commit, Just digest) -> Right (Just (Pin source version commit digest))
            _ -> Left "Git resolutions require commit and sha256 fields"


traverseMapWithKey :: (Ord k2) => (k1 -> v1 -> Either String (k2, v2)) -> Map k1 v1 -> Either String (Map k2 v2)
traverseMapWithKey func input = Map.fromList <$> mapM (uncurry func) (Map.toList input)


parsePackage :: String -> Either String Pkg.Name
parsePackage chars =
  case P.fromByteString Pkg.parser (,) (BS_UTF8.fromString chars) of
    Right name -> Right name
    Left _ -> Left ("Invalid Elm package name in schelm.json: " ++ chars)


parseVersion :: String -> Either String V.Version
parseVersion chars =
  case P.fromByteString V.parser (,) (BS_UTF8.fromString chars) of
    Right version -> Right version
    Left _ -> Left ("Invalid Elm package version in schelm.json: " ++ chars)


validateRemote :: String -> Either String String
validateRemote raw =
  let source = dropWhileEndSlash (dropWhile (== ' ') raw) in
  if null source
    then Left "Git remote cannot be empty"
    else if hasHttpCredentials source
      then Left "HTTP Git remotes in schelm.json may not contain credentials"
      else Right source


dropWhileEndSlash :: String -> String
dropWhileEndSlash source = reverse (dropWhile (== '/') (reverse source))


hasHttpCredentials :: String -> Bool
hasHttpCredentials source = any hasCredentials ["http://", "https://"]
  where
    hasCredentials prefix =
      case List.stripPrefix prefix source of
        Nothing -> False
        Just rest -> '@' `elem` takeWhile (/= '/') rest


sourceOrigins :: Config -> Map Pkg.Name Origin
sourceOrigins config = Map.map Git (_sources config)


hasCustomSource :: Config -> Pkg.Name -> Bool
hasCustomSource config name = Map.member name (_sources config)


rootOrigin :: Config -> Pkg.Name -> Origin
rootOrigin config name =
  case Map.lookup name (_sources config) of
    Just source -> Git source
    Nothing ->
      case Map.lookup name (_pins config) of
        Just pin -> Git (_pinSource pin)
        Nothing -> Official


dependencyOrigins :: FilePath -> IO (Either String (Map Pkg.Name Origin))
dependencyOrigins packageRoot = fmap (fmap sourceOrigins) (readAt packageRoot)


pinFor :: Config -> Pkg.Name -> Maybe Pin
pinFor config name = Map.lookup name (_pins config)


recordPin :: Pkg.Name -> Pin -> Config -> Config
recordPin name pin config = config { _pins = Map.insert name pin (_pins config) }


snapshot :: FilePath -> IO (Maybe BS.ByteString)
snapshot root =
  do  let path = root </> fileName
      exists <- Dir.doesFileExist path
      if exists then Just <$> BS.readFile path else return Nothing


restore :: FilePath -> Maybe BS.ByteString -> IO ()
restore root maybeBytes =
  case maybeBytes of
    Nothing ->
      do  let path = root </> fileName
          exists <- Dir.doesFileExist path
          if exists then Dir.removeFile path else return ()
    Just bytes -> BS.writeFile (root </> fileName) bytes


setSource :: FilePath -> Pkg.Name -> String -> IO (Either String ())
setSource root name rawSource =
  case validateRemote rawSource of
    Left problem -> return (Left problem)
    Right source ->
      do  result <- readAt root
          case result of
            Left problem -> return (Left problem)
            Right config ->
              let manifest = _manifest config
                  key = Text.pack (Pkg.toChars name)
                  rawSources = Map.insert key (Text.pack source) (_rawSources manifest)
                  rawResolved = Map.delete key (_rawResolved manifest)
              in do  writeManifest root (manifest { _rawSources = rawSources, _rawResolved = rawResolved })
                     return (Right ())


persistResolved :: Config -> Map Pkg.Name Origin -> Map Pkg.Name V.Version -> IO (Either String ())
persistResolved config origins solution =
  let hasGit = any isGit (Map.elems origins) in
  if not (_exists config) && not hasGit
    then return (Right ())
    else
      let manifest = _manifest config
          toRaw name version =
            case Map.findWithDefault Official name origins of
              Official -> RawPin "elm-registry" (V.toChars version) Nothing Nothing
              Git source ->
                case Map.lookup name (_pins config) of
                  Just pin -> RawPin source (V.toChars version) (Just (_pinCommit pin)) (Just (_pinSha256 pin))
                  Nothing -> RawPin source (V.toChars version) Nothing Nothing
          rawResolved = Map.fromList $
            map (\(name, version) -> (Text.pack (Pkg.toChars name), toRaw name version)) (Map.toList solution)
      in if any missingGitPin (Map.elems rawResolved)
           then return (Left "A Git dependency was resolved without an immutable commit and content hash")
           else do  writeManifest (_root config) (manifest { _rawResolved = rawResolved })
                    return (Right ())
  where
    isGit origin = case origin of Git _ -> True; Official -> False
    missingGitPin pin = _rawSource pin /= "elm-registry" && (_rawCommit pin == Nothing || _rawSha256 pin == Nothing)


writeManifest :: FilePath -> Manifest -> IO ()
writeManifest root manifest = BL.writeFile (root </> fileName) (A.encode manifest <> "\n")


fetchVersions :: String -> IO (Either String [V.Version])
fetchVersions source =
  do  result <- runGit ["ls-remote", "--tags", "--refs", source]
      return $
        case result of
          Left problem -> Left problem
          Right output ->
            let versions = List.nub $ List.sortBy (flip compare) $ foldr keepRight [] $
                  map parseVersion $ foldr (maybe id (:)) [] $
                  map (List.stripPrefix "refs/tags/") $
                  map (drop 1 . dropWhile (/= '\t')) (lines output)
            in if null versions
                 then Left ("No bare semantic-version tags were found at " ++ source)
                 else Right versions
  where
    keepRight value rest = case value of Right version -> version : rest; Left _ -> rest


prepareOfficial :: FilePath -> IO ()
prepareOfficial packageRoot =
  do  markerExists <- Dir.doesFileExist (packageRoot </> markerName)
      if markerExists then Dir.removeDirectoryRecursive packageRoot else return ()


prepareGit :: Config -> FilePath -> Pkg.Name -> V.Version -> String -> IO (Either String (Config, Pin))
prepareGit config packageRoot name version source =
  do  cached <- readMarker packageRoot
      case cached of
        Just pin | pinMatches config name version source pin ->
          do  digestResult <- digestPackage packageRoot
              case digestResult of
                Right digest | digest == _pinSha256 pin -> return (Right (recordPin name pin config, pin))
                Right _ -> return (Left ("Cached source hash changed for " ++ Pkg.toChars name ++ " " ++ V.toChars version))
                Left problem -> return (Left problem)
        _ -> fetchGit config packageRoot name version source


pinMatches :: Config -> Pkg.Name -> V.Version -> String -> Pin -> Bool
pinMatches config name version source cached =
  _pinSource cached == source
  && _pinVersion cached == version
  && case pinFor config name of
       Nothing -> True
       Just expected -> expected == cached


fetchGit :: Config -> FilePath -> Pkg.Name -> V.Version -> String -> IO (Either String (Config, Pin))
fetchGit config packageRoot name version source =
  Temp.withSystemTempDirectory "schelm-package" $ \temp ->
    do  let checkout = temp </> "checkout"
        cloneResult <- runGit ["-c", "core.autocrlf=false", "clone", "--quiet", "--depth", "1", "--single-branch", "--no-recurse-submodules", "--branch", V.toChars version, source, checkout]
        case cloneResult of
          Left problem -> return (Left problem)
          Right _ ->
            do  submodules <- Dir.doesFileExist (checkout </> ".gitmodules")
                if submodules
                  then return (Left "Git package releases may not contain submodules")
                  else verifyAndInstall config packageRoot checkout name version source


verifyAndInstall :: Config -> FilePath -> FilePath -> Pkg.Name -> V.Version -> String -> IO (Either String (Config, Pin))
verifyAndInstall config packageRoot checkout expectedName expectedVersion source =
  do  outlineResult <- Outline.read checkout True
      case outlineResult of
        Left _ -> return (Left "The Git release does not contain a valid package elm.json")
        Right (Outline.App _) -> return (Left "Applications cannot be installed as packages")
        Right (Outline.Pkg (Outline.PkgOutline actualName _ _ actualVersion _ _ _ _)) ->
          if actualName /= expectedName
            then return (Left ("Git release package name is " ++ Pkg.toChars actualName ++ ", expected " ++ Pkg.toChars expectedName))
            else if actualVersion /= expectedVersion
              then return (Left ("Git tag " ++ V.toChars expectedVersion ++ " contains elm.json version " ++ V.toChars actualVersion))
              else
                do  commitResult <- runGit ["-C", checkout, "rev-parse", "HEAD^{commit}"]
                    digestResult <- digestPackage checkout
                    case (commitResult, digestResult) of
                      (Right commitOutput, Right digest) ->
                        let pin = Pin source expectedVersion (trim commitOutput) digest in
                        case pinFor config expectedName of
                          Just expected | expected /= pin ->
                            return (Left ("Locked Git release changed for " ++ Pkg.toChars expectedName ++ " " ++ V.toChars expectedVersion))
                          _ ->
                            do  packageExists <- Dir.doesDirectoryExist packageRoot
                                if packageExists then Dir.removeDirectoryRecursive packageRoot else return ()
                                Dir.createDirectoryIfMissing True packageRoot
                                copyResult <- try (copyPackage checkout packageRoot) :: IO (Either IOException ())
                                case copyResult of
                                  Left problem ->
                                    do  Dir.removeDirectoryRecursive packageRoot
                                        return (Left (show problem))
                                  Right () ->
                                    do  BL.writeFile (packageRoot </> markerName) (A.encode (toRawPin pin) <> "\n")
                                        return (Right (recordPin expectedName pin config, pin))
                      (Left problem, _) -> return (Left problem)
                      (_, Left problem) -> return (Left problem)


toRawPin :: Pin -> RawPin
toRawPin pin = RawPin (_pinSource pin) (V.toChars (_pinVersion pin)) (Just (_pinCommit pin)) (Just (_pinSha256 pin))


readMarker :: FilePath -> IO (Maybe Pin)
readMarker packageRoot =
  do  let path = packageRoot </> markerName
      exists <- Dir.doesFileExist path
      if not exists
        then return Nothing
        else
          do  bytes <- BS.readFile path
              case A.eitherDecodeStrict' bytes >>= decodePin of
                Right (Just pin) -> return (Just pin)
                _ -> return Nothing


digestPackage :: FilePath -> IO (Either String String)
digestPackage root =
  do  filesResult <- packageFiles root
      case filesResult of
        Left problem -> return (Left problem)
        Right paths ->
          do  chunks <- forM paths $ \relative ->
                do  bytes <- BS.readFile (root </> relative)
                    return [BL.fromStrict (BS8.pack (canonicalPath relative)), "\0", BL.fromStrict bytes, "\0"]
              let digest = hashlazy (BL.concat (concat chunks)) :: Digest SHA256
              return (Right (show digest))


packageFiles :: FilePath -> IO (Either String [FilePath])
packageFiles root =
  do  let candidates = ["elm.json", "schelm.json", "src"]
      existing <- filterM (Dir.doesPathExist . (root </>)) candidates
      result <- foldM collect (Right []) existing
      return (fmap List.sort result)
  where
    collect (Left problem) _ = return (Left problem)
    collect (Right paths) relative =
      do  result <- walk relative
          return ((paths ++) <$> result)
    walk relative =
      do  let path = root </> relative
          symbolic <- Dir.pathIsSymbolicLink path
          if symbolic
            then return (Left ("Git package contains a symbolic link: " ++ relative))
            else
              do  directory <- Dir.doesDirectoryExist path
                  if directory
                    then
                      do  entries <- Dir.listDirectory path
                          foldM collect (Right []) (map (relative </>) entries)
                    else return (Right [FP.normalise relative])


copyPackage :: FilePath -> FilePath -> IO ()
copyPackage source destination =
  do  entries <- Dir.listDirectory source
      mapM_ copyEntry (filter (/= ".git") entries)
  where
    copyEntry entry =
      do  let from = source </> entry
          let to = destination </> entry
          symbolic <- Dir.pathIsSymbolicLink from
          if symbolic
            then ioError (userError ("Git package contains a symbolic link: " ++ entry))
            else
              do  directory <- Dir.doesDirectoryExist from
                  if directory
                    then
                      do  Dir.createDirectoryIfMissing True to
                          copyPackage from to
                    else Dir.copyFile from to


runGit :: [String] -> IO (Either String String)
runGit args =
  do  result <- try (Process.readProcessWithExitCode "git" args "") :: IO (Either IOException (Exit.ExitCode, String, String))
      return $
        case result of
          Left problem -> Left ("Could not run git: " ++ show problem)
          Right (Exit.ExitSuccess, output, _) -> Right output
          Right (Exit.ExitFailure code, _, message) -> Left ("git failed with exit code " ++ show code ++ ": " ++ trim message)


trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r', ' ', '\t']) . reverse . dropWhile (`elem` ['\n', '\r', ' ', '\t'])


canonicalPath :: FilePath -> FilePath
canonicalPath = map (\char -> if FP.isPathSeparator char then '/' else char)
