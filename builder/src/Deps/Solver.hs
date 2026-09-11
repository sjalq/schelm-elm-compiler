{-# LANGUAGE OverloadedStrings, Rank2Types #-}
module Deps.Solver
  ( Solver
  , Result(..)
  , Connection(..)
  --
  , Details(..)
  , verify
  , verifyPlan
  --
  , AppSolution(..)
  , addToApp
  --
  , Env(..)
  , initEnv
  )
  where


import Control.Monad (foldM)
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, readMVar)
import qualified Data.Map as Map
import Data.Map ((!))
import qualified System.Directory as Dir
import System.FilePath ((</>))

import qualified Deps.Registry as Registry
import qualified Deps.Schelm as Schelm
import qualified Deps.Website as Website
import qualified Elm.Constraint as C
import qualified Elm.Package as Pkg
import qualified Elm.Outline as Outline
import qualified Elm.Version as V
import qualified File
import qualified Http
import qualified Json.Decode as D
import qualified Reporting.Exit as Exit
import qualified Stuff


import qualified Lamdera
import Lamdera ((&))
import qualified Lamdera.Extensions

-- SOLVER


newtype Solver a =
  Solver
  (
    forall b.
      State
      -> (State -> a -> (State -> IO b) -> IO b)
      -> (State -> IO b)
      -> (Exit.Solver -> IO b)
      -> IO b
  )


data State =
  State
    { _cache :: Stuff.PackageCache
    , _connection :: Connection
    , _registry :: Registry.Registry
    , _constraints :: Map.Map (Pkg.Name, V.Version) Constraints
    , _schelm :: Schelm.Config
    , _origins :: Map.Map Pkg.Name Schelm.Origin
    }


data Constraints =
  Constraints
    { _elm :: C.Constraint
    , _deps :: Map.Map Pkg.Name C.Constraint
    , _depOrigins :: Map.Map Pkg.Name Schelm.Origin
    }


data Connection
  = Online Http.Manager
  | Offline



-- RESULT


data Result a
  = Ok a
  | NoSolution
  | NoOfflineSolution
  | Err Exit.Solver



-- VERIFY -- used by Elm.Details


data Details =
  Details V.Version (Map.Map Pkg.Name C.Constraint)


verify :: Stuff.PackageCache -> Connection -> Registry.Registry -> Map.Map Pkg.Name C.Constraint -> IO (Result (Map.Map Pkg.Name Details))
verify = verifyHelp True


verifyPlan :: Stuff.PackageCache -> Connection -> Registry.Registry -> Map.Map Pkg.Name C.Constraint -> IO (Result (Map.Map Pkg.Name Details))
verifyPlan = verifyHelp True


verifyHelp :: Bool -> Stuff.PackageCache -> Connection -> Registry.Registry -> Map.Map Pkg.Name C.Constraint -> IO (Result (Map.Map Pkg.Name Details))
verifyHelp shouldPersist cache connection registry constraints =
  Stuff.withRegistryLock cache $
  do  schelmResult <- Schelm.read
      case schelmResult of
        Left problem -> return (Err (Exit.SolverSchelmProblem problem))
        Right schelm ->
          case try constraints of
            Solver solver ->
              let origins = Map.mapWithKey (\name _ -> Schelm.rootOrigin schelm name) constraints in
              solver (State cache connection registry Map.empty schelm origins)
                (\s a _ ->
                  do  saved <- if shouldPersist then Schelm.persistResolved (_schelm s) (_origins s) a else return (Right ())
                      case saved of
                        Left problem -> return (Err (Exit.SolverSchelmProblem problem))
                        Right () -> return $ Ok (Map.mapWithKey (addDeps s) a)
                )
                (\_ -> return $ noSolution connection)
                (\e -> return $ Err e)


addDeps :: State -> Pkg.Name -> V.Version -> Details
addDeps (State _ _ _ constraints _ _) name vsn =
  case Map.lookup (name, vsn) constraints of
    Just (Constraints _ deps _) -> Details vsn deps
    Nothing                   -> error "compiler bug manifesting in Deps.Solver.addDeps"


noSolution :: Connection -> Result a
noSolution connection =
  case connection of
    Online _ -> NoSolution
    Offline -> NoOfflineSolution



-- ADD TO APP - used in Install


data AppSolution =
  AppSolution
    { _old :: Map.Map Pkg.Name V.Version
    , _new :: Map.Map Pkg.Name V.Version
    , _app :: Outline.AppOutline
    }


addToApp :: Stuff.PackageCache -> Connection -> Registry.Registry -> Pkg.Name -> Outline.AppOutline -> IO (Result AppSolution)
addToApp cache connection registry pkg outline@(Outline.AppOutline _ _ direct indirect testDirect testIndirect) =
  Stuff.withRegistryLock cache $
  do  schelmResult <- Schelm.read
      case schelmResult of
        Left problem -> return (Err (Exit.SolverSchelmProblem problem))
        Right schelm ->
          let
            allIndirects = Map.union indirect testIndirect
            allDirects = Map.union direct testDirect
            allDeps = Map.union allDirects allIndirects
            attempt toConstraint deps = try (Map.insert pkg C.anything (Map.map toConstraint deps))
            requested = Map.insert pkg V.one allDeps
            origins = Map.mapWithKey (\name _ -> Schelm.rootOrigin schelm name) requested
          in
          case
            oneOf
              ( attempt C.exactly allDeps )
              [ attempt C.exactly allDirects
              , attempt C.untilNextMinor allDirects
              , attempt C.untilNextMajor allDirects
              , attempt (\_ -> C.anything) allDirects
              ]
          of
            Solver solver ->
              solver (State cache connection registry Map.empty schelm origins)
                (\s a _ ->
                  do  saved <- Schelm.persistResolved (_schelm s) (_origins s) a
                      case saved of
                        Left problem -> return (Err (Exit.SolverSchelmProblem problem))
                        Right () -> return $ Ok (toApp s pkg outline allDeps a)
                )
                (\_ -> return $ noSolution connection)
                (\e -> return $ Err e)


toApp :: State -> Pkg.Name -> Outline.AppOutline -> Map.Map Pkg.Name V.Version -> Map.Map Pkg.Name V.Version -> AppSolution
toApp (State _ _ _ constraints _ _) pkg (Outline.AppOutline elm srcDirs direct _ testDirect _) old new =
  let
    d   = Map.intersection new (Map.insert pkg V.one direct)
    i   = Map.difference (getTransitive constraints new (Map.toList d) Map.empty) d
    td  = Map.intersection new (Map.delete pkg testDirect)
    ti  = Map.difference new (Map.unions [d,i,td])
  in
  AppSolution old new (Outline.AppOutline elm srcDirs d i td ti)


getTransitive :: Map.Map (Pkg.Name, V.Version) Constraints -> Map.Map Pkg.Name V.Version -> [(Pkg.Name,V.Version)] -> Map.Map Pkg.Name V.Version -> Map.Map Pkg.Name V.Version
getTransitive constraints solution unvisited visited =
  case unvisited of
    [] ->
      visited

    info@(pkg,vsn) : infos ->
      if Map.member pkg visited
      then getTransitive constraints solution infos visited
      else
        let
          newDeps = _deps (constraints ! info)
          newUnvisited = Map.toList (Map.intersection solution (Map.difference newDeps visited))
          newVisited = Map.insert pkg vsn visited
        in
        getTransitive constraints solution infos $
          getTransitive constraints solution newUnvisited newVisited



-- TRY


try :: Map.Map Pkg.Name C.Constraint -> Solver (Map.Map Pkg.Name V.Version)
try constraints =
  exploreGoals (Goals constraints Map.empty)



-- EXPLORE GOALS


data Goals =
  Goals
    { _pending :: Map.Map Pkg.Name C.Constraint
    , _solved :: Map.Map Pkg.Name V.Version
    }


exploreGoals :: Goals -> Solver (Map.Map Pkg.Name V.Version)
exploreGoals (Goals pending solved) =
  case Map.minViewWithKey pending of
    Nothing ->
      return solved

    Just ((name, constraint), otherPending) ->
      do  let goals1 = Goals otherPending solved
          let addVsn = addVersion goals1 name
          (v,vs) <- getRelevantVersions name constraint
          goals2 <- oneOf (addVsn v) (map addVsn vs)
          exploreGoals goals2


addVersion :: Goals -> Pkg.Name -> V.Version -> Solver Goals
addVersion (Goals pending solved) name version =
  do  (Constraints elm deps depOrigins) <- getConstraints name version
      if C.goodElm elm
        then
          do  newPending <- foldM (addConstraint solved depOrigins) pending (Map.toList deps)
              return (Goals newPending (Map.insert name version solved))
        else
          backtrack


addConstraint :: Map.Map Pkg.Name V.Version -> Map.Map Pkg.Name Schelm.Origin -> Map.Map Pkg.Name C.Constraint -> (Pkg.Name, C.Constraint) -> Solver (Map.Map Pkg.Name C.Constraint)
addConstraint solved origins unsolved (name, newConstraint) =
  do  demandOrigin name (Map.findWithDefault Schelm.Official name origins)
      case Map.lookup name solved of
        Just version ->
          if C.satisfies newConstraint version
          then return unsolved
          else backtrack

        Nothing ->
          case Map.lookup name unsolved of
            Nothing ->
              return $ Map.insert name newConstraint unsolved

            Just oldConstraint ->
              case C.intersect oldConstraint newConstraint of
                Nothing ->
                  backtrack

                Just mergedConstraint ->
                  if oldConstraint == mergedConstraint
                  then return unsolved
                  else return (Map.insert name mergedConstraint unsolved)


demandOrigin :: Pkg.Name -> Schelm.Origin -> Solver ()
demandOrigin name origin =
  Solver $ \state ok back _ ->
    case Map.lookup name (_origins state) of
      Nothing -> ok (state { _origins = Map.insert name origin (_origins state) }) () back
      Just existing ->
        if existing == origin then ok state () back else back state



-- GET RELEVANT VERSIONS


getRelevantVersions :: Pkg.Name -> C.Constraint -> Solver (V.Version, [V.Version])
getRelevantVersions name constraint =
  Solver $ \state@(State _ _ registry _ schelm origins) ok back err ->
    case Map.findWithDefault Schelm.Official name origins of
      Schelm.Official ->
        case Registry.getVersions name registry of
          Just (Registry.KnownVersions newest previous) -> choose state (newest:previous) ok back
          Nothing -> back state

      Schelm.Git source ->
        do  versionsResult <- Schelm.fetchVersions source
            case versionsResult of
              Right versions -> choose state versions ok back
              Left problem ->
                case Schelm.pinFor schelm name of
                  Just pin -> choose state [Schelm._pinVersion pin] ok back
                  Nothing -> err (Exit.SolverSchelmProblem problem)
  where
    choose state versions ok back =
      case filter (C.satisfies constraint) versions of
        [] -> back state
        v:vs -> ok state (v,vs) back



-- GET CONSTRAINTS


getConstraints :: Pkg.Name -> V.Version -> Solver Constraints
getConstraints pkg vsn =
  Solver $ \state@(State cache connection registry cDict schelm origins) ok back err ->
    do  let key = (pkg, vsn)
        let home = Stuff.package cache pkg vsn
        let path = home </> "elm.json"
        let withOrigins depOrigins (Constraints elm deps _) = Constraints elm deps depOrigins
        let finish preparedSchelm depOrigins bare =
              let cs = withOrigins depOrigins bare
                  newState = State cache connection registry (Map.insert key cs cDict) preparedSchelm origins
              in ok newState cs back
        let load preparedSchelm =
              do  depOriginsResult <- Schelm.dependencyOrigins home
                  case depOriginsResult of
                    Left problem -> err (Exit.SolverSchelmProblem problem)
                    Right depOrigins ->
                      do  outlineExists <- File.exists path
                          if outlineExists
                            then
                              do  bytes <- File.readUtf8 path
                                  case D.fromByteString constraintsDecoder bytes of
                                    Right bare ->
                                      case connection of
                                        Online _ -> finish preparedSchelm depOrigins bare
                                        Offline ->
                                          do  srcExists <- Dir.doesDirectoryExist (home </> "src")
                                              if srcExists then finish preparedSchelm depOrigins bare else back state
                                    Left _ ->
                                      do  File.remove path
                                          err (Exit.SolverBadCacheData pkg vsn)
                            else
                              case connection of
                                Offline -> back state
                                Online manager ->
                                  do  let url = Website.metadata pkg vsn "elm.json"
                                      result <- Http.get manager url [] id (return . Right)
                                                  & Lamdera.alternativeImplementationPassthrough (Lamdera.Extensions.elmJsonOverride pkg vsn)
                                      case result of
                                        Left httpProblem -> err (Exit.SolverBadHttp pkg vsn httpProblem)
                                        Right body ->
                                          case D.fromByteString constraintsDecoder body of
                                            Right bare ->
                                              do  Dir.createDirectoryIfMissing True home
                                                  File.writeUtf8 path body
                                                  finish preparedSchelm depOrigins bare
                                            Left _ -> err (Exit.SolverBadHttpData pkg vsn url)
        case Map.lookup key cDict of
          Just cs ->
            ok state cs back

          Nothing ->
            do  prepared <-
                  case Map.findWithDefault Schelm.Official pkg origins of
                    Schelm.Official -> Schelm.prepareOfficial home >> return (Right schelm)
                    Schelm.Git source -> fmap (fmap fst) (Schelm.prepareGit schelm home pkg vsn source)
                case prepared of
                  Left problem -> err (Exit.SolverSchelmProblem problem)
                  Right preparedSchelm -> load preparedSchelm


constraintsDecoder :: D.Decoder () Constraints
constraintsDecoder =
  do  outline <- D.mapError (const ()) Outline.decoder
      case outline of
        Outline.Pkg (Outline.PkgOutline _ _ _ _ _ deps _ elmConstraint) ->
          return (Constraints elmConstraint deps Map.empty)

        Outline.App _ ->
          D.failure ()



-- ENVIRONMENT


data Env =
  Env Stuff.PackageCache Http.Manager Connection Registry.Registry


initEnv :: IO (Either Exit.RegistryProblem Env)
initEnv =
  do  mvar  <- newEmptyMVar
      _     <- forkIO $ putMVar mvar =<< Http.getManager
      cache <- Stuff.getPackageCache
      Stuff.withRegistryLock cache $
        do  maybeRegistry <- Registry.read cache
            manager       <- readMVar mvar

            case maybeRegistry of
              Nothing ->
                do  eitherRegistry <- Registry.fetch manager cache
                    case eitherRegistry of
                      Right latestRegistry ->
                        return $ Right $ Env cache manager (Online manager) latestRegistry

                      Left problem ->
                        return $ Left $ problem

              Just cachedRegistry ->
                do  eitherRegistry <- Registry.update manager cache cachedRegistry
                    case eitherRegistry of
                      Right latestRegistry ->
                        return $ Right $ Env cache manager (Online manager) latestRegistry

                      Left _ ->
                        return $ Right $ Env cache manager Offline cachedRegistry



-- INSTANCES


instance Functor Solver where
  fmap func (Solver solver) =
    Solver $ \state ok back err ->
      let
        okA stateA arg backA = ok stateA (func arg) backA
      in
      solver state okA back err


instance Applicative Solver where
  pure a =
    Solver $ \state ok back _ -> ok state a back

  (<*>) (Solver solverFunc) (Solver solverArg) =
    Solver $ \state ok back err ->
      let
        okF stateF func backF =
          let
            okA stateA arg backA = ok stateA (func arg) backA
          in
          solverArg stateF okA backF err
      in
      solverFunc state okF back err


instance Monad Solver where
  return a =
    Solver $ \state ok back _ -> ok state a back

  (>>=) (Solver solverA) callback =
    Solver $ \state ok back err ->
      let
        okA stateA a backA =
          case callback a of
            Solver solverB -> solverB stateA ok backA err
      in
      solverA state okA back err


oneOf :: Solver a -> [Solver a] -> Solver a
oneOf solver@(Solver solverHead) solvers =
  case solvers of
    [] ->
      solver

    s:ss ->
      Solver $ \state0 ok back err ->
        let
          tryTail state1 =
            let
              (Solver solverTail) = oneOf s ss
            in
            solverTail state1 ok back err
        in
        solverHead state0 ok tryTail err


backtrack :: Solver a
backtrack =
  Solver $ \state _ back _ -> back state
