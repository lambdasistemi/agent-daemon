module AgentDaemon.Api
    ( apiApp
    ) where

-- \|
-- Module      : AgentDaemon.Api
-- Description : Servant server for the REST API
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Servant-based WAI application providing REST endpoints
-- for launching, listing, and stopping agent sessions.

import AgentDaemon.Api.Types (agentApi)
import AgentDaemon.Branch qualified as Branch
import AgentDaemon.Recovery (getRepoOwner)
import AgentDaemon.Tmux qualified as Tmux
import AgentDaemon.Types
    ( BranchInfo (..)
    , LaunchRequest (..)
    , Repo (..)
    , Session (..)
    , SessionId (..)
    , SessionManager (..)
    , SessionState (..)
    , WorktreeInfo (..)
    , mkSessionId
    , mkTmuxName
    , mkWorktreePath
    )
import AgentDaemon.Worktree qualified as Worktree
import Control.Concurrent.STM
    ( atomically
    , readTVar
    , readTVarIO
    , writeTVar
    )
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Tagged (Tagged (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.HTTP.Types
    ( ResponseHeaders
    , status200
    )
import Network.Wai
    ( Application
    , Middleware
    , mapResponseHeaders
    , responseFile
    )
import Servant
    ( Handler
    , ServerError (..)
    , err400
    , err404
    , err500
    , serve
    , throwError
    , (:<|>) (..)
    )
import System.Directory
    ( doesDirectoryExist
    , listDirectory
    )

-- | WAI application for the REST API and static files.
apiApp
    :: FilePath
    -- ^ base directory for worktrees
    -> FilePath
    -- ^ static files directory
    -> SessionManager
    -> Application
apiApp baseDir staticDir mgr =
    cors $
        serve
            agentApi
            ( handleLaunch baseDir mgr
                :<|> handleList mgr
                :<|> handleStop baseDir mgr
                :<|> handleListWorktrees baseDir
                :<|> handleListBranches baseDir
                :<|> handleDeleteBranch baseDir
                :<|> staticFallback staticDir
            )

-- | Static file fallback — serves index.html for SPA.
staticFallback :: FilePath -> Tagged Handler Application
staticFallback staticDir = Tagged $ \_req respond ->
    respond $
        responseFile
            status200
            [("Content-Type", "text/html")]
            (staticDir <> "/index.html")
            Nothing

-- | Build the main repo path from base dir and repo.
repoPath :: FilePath -> Repo -> FilePath
repoPath baseDir Repo{repoName} =
    baseDir <> "/" <> T.unpack repoName

-- | Launch a new agent session.
handleLaunch
    :: FilePath
    -> SessionManager
    -> LaunchRequest
    -> Handler Aeson.Value
handleLaunch baseDir mgr LaunchRequest{launchRepo, launchIssue} =
    do
        let sid = mkSessionId launchRepo launchIssue
        existing <- liftIO $ readTVarIO (sessions mgr)
        case Map.lookup sid existing of
            Just session ->
                pure (Aeson.toJSON session)
            Nothing ->
                launchSession
                    baseDir
                    mgr
                    sid
                    launchRepo
                    launchIssue

-- | Internal: create and launch a new session.
launchSession
    :: FilePath
    -> SessionManager
    -> SessionId
    -> Repo
    -> Int
    -> Handler Aeson.Value
launchSession baseDir mgr sid repo issue = do
    let tmuxName = mkTmuxName repo issue
        worktree = mkWorktreePath baseDir repo issue
    now <- liftIO getCurrentTime
    let prompt = claudePrompt repo issue
        session =
            Session
                { sessionId = sid
                , sessionRepo = repo
                , sessionIssue = issue
                , sessionWorktree = worktree
                , sessionTmuxName = tmuxName
                , sessionState = Creating
                , sessionCreatedAt = now
                , sessionPrompt = prompt
                , sessionLastActivity = now
                }
    liftIO $
        atomically $ do
            m <- readTVar (sessions mgr)
            writeTVar (sessions mgr) $
                Map.insert sid session m
    result <- liftIO $ runLaunchSteps tmuxName worktree
    case result of
        Left reason -> do
            liftIO $
                setSessionState mgr sid (Failed reason)
            throwError
                err500
                    { errBody =
                        Aeson.encode $ errorJson reason
                    , errHeaders = jsonHeaders
                    }
        Right () -> do
            liftIO $ setSessionState mgr sid Running
            pure $
                Aeson.toJSON
                    session{sessionState = Running}
  where
    runLaunchSteps tmuxName' worktree' = do
        wtResult <-
            Worktree.createWorktree
                (repoPath baseDir repo)
                worktree'
                ( "feat/issue-"
                    <> T.pack (show issue)
                )
        case wtResult of
            Left e -> pure (Left e)
            Right () -> do
                tmResult <-
                    Tmux.createSession
                        tmuxName'
                        worktree'
                case tmResult of
                    Left e -> pure (Left e)
                    Right () ->
                        Tmux.sendKeys
                            tmuxName'
                            ( "claude --dangerously-skip-permissions "
                                <> claudePrompt
                                    repo
                                    issue
                            )

-- | List all active sessions.
handleList
    :: SessionManager
    -> Handler [Session]
handleList mgr = do
    m <- liftIO $ readTVarIO (sessions mgr)
    pure $ Map.elems m

-- | Stop a session and clean up resources.
handleStop
    :: FilePath
    -> SessionManager
    -> Text
    -> Handler Aeson.Value
handleStop baseDir mgr sidText = do
    let sid = SessionId sidText
    m <- liftIO $ readTVarIO (sessions mgr)
    case Map.lookup sid m of
        Nothing ->
            throwError
                err404
                    { errBody =
                        Aeson.encode $
                            errorJson
                                ( "Session "
                                    <> unSessionId sid
                                    <> " not found"
                                )
                    , errHeaders = jsonHeaders
                    }
        Just session -> do
            _ <-
                liftIO $
                    Tmux.killSession
                        (sessionTmuxName session)
            _ <-
                liftIO $
                    Worktree.removeWorktree
                        ( repoPath
                            baseDir
                            (sessionRepo session)
                        )
                        (sessionWorktree session)
            liftIO $
                atomically $ do
                    current <- readTVar (sessions mgr)
                    writeTVar (sessions mgr) $
                        Map.delete sid current
            pure $
                Aeson.object
                    [
                        ( "status"
                        , Aeson.String "stopped"
                        )
                    ]

-- | List all worktree directories on disk.
handleListWorktrees
    :: FilePath
    -> Handler [WorktreeInfo]
handleListWorktrees baseDir = do
    entries <- liftIO $ listDirectory baseDir
    liftIO $
        catMaybes
            <$> mapM (toWorktreeInfo baseDir) entries

{- | Try to build a 'WorktreeInfo' from a directory name.

Matches the pattern @repoName-issue-N@ and reads the
repo owner from the git remote.
-}
toWorktreeInfo
    :: FilePath -> FilePath -> IO (Maybe WorktreeInfo)
toWorktreeInfo baseDir name =
    case parseWorktreeName (T.pack name) of
        Nothing -> pure Nothing
        Just (repoName, issue) -> do
            let path = baseDir <> "/" <> name
            isDir <- doesDirectoryExist path
            if not isDir
                then pure Nothing
                else do
                    owner <- getRepoOwner path
                    pure $
                        Just
                            WorktreeInfo
                                { worktreeRepo =
                                    Repo
                                        { repoOwner = owner
                                        , repoName = repoName
                                        }
                                , worktreeIssue = issue
                                , worktreePath = path
                                }

{- | Parse a worktree directory name into repo name
and issue number.

@"agent-daemon-issue-32"@ becomes
@Just ("agent-daemon", 32)@.
-}
parseWorktreeName :: Text -> Maybe (Text, Int)
parseWorktreeName name =
    case T.breakOn "-issue-" name of
        (_, "") -> Nothing
        (repoName, rest) -> do
            let numText = T.drop 7 rest -- drop "-issue-"
            issue <-
                case reads (T.unpack numText) of
                    [(n, "")] -> Just n
                    _ -> Nothing
            if T.null repoName
                then Nothing
                else Just (repoName, issue)

-- | List all local issue branches.
handleListBranches
    :: FilePath
    -> Handler [BranchInfo]
handleListBranches baseDir =
    liftIO $ Branch.listBranches baseDir

-- | Delete a branch locally and on the remote.
handleDeleteBranch
    :: FilePath
    -> Text
    -> Text
    -> Handler Aeson.Value
handleDeleteBranch baseDir repo branch = do
    result <-
        liftIO $
            Branch.deleteBranch baseDir repo branch False
    case result of
        Left err ->
            throwError
                err400
                    { errBody =
                        Aeson.encode $ errorJson err
                    , errHeaders = jsonHeaders
                    }
        Right () ->
            pure $
                Aeson.object
                    [
                        ( "status"
                        , Aeson.String "deleted"
                        )
                    ]

-- | Update session state in the registry.
setSessionState
    :: SessionManager -> SessionId -> SessionState -> IO ()
setSessionState mgr sid state =
    atomically $ do
        m <- readTVar (sessions mgr)
        writeTVar (sessions mgr) $
            Map.adjust
                (\s -> s{sessionState = state})
                sid
                m

-- | Build a JSON error object.
errorJson :: Text -> Aeson.Value
errorJson msg =
    Aeson.object [("error", Aeson.String msg)]

-- | Standard JSON content-type headers.
jsonHeaders :: ResponseHeaders
jsonHeaders = [("Content-Type", "application/json")]

{- | Build the initial prompt for Claude.

Tells Claude which issue to work on and how to load it.
The prompt is shell-quoted to survive send-keys.
-}
claudePrompt :: Repo -> Int -> Text
claudePrompt Repo{repoOwner, repoName} issue =
    "'"
        <> "Work on "
        <> repoOwner
        <> "/"
        <> repoName
        <> "#"
        <> T.pack (show issue)
        <> ". "
        <> "Start by running: "
        <> "gh issue view "
        <> T.pack (show issue)
        <> " -R "
        <> repoOwner
        <> "/"
        <> repoName
        <> "'"

{- | CORS middleware — adds permissive CORS headers to
all responses.
-}
cors :: Middleware
cors app req respond =
    app req $ \response ->
        respond $
            mapResponseHeaders (++ corsHeaders) response

-- | CORS headers allowing any origin.
corsHeaders :: ResponseHeaders
corsHeaders =
    [ ("Access-Control-Allow-Origin", "*")
    ,
        ( "Access-Control-Allow-Methods"
        , "GET, POST, DELETE, OPTIONS"
        )
    ,
        ( "Access-Control-Allow-Headers"
        , "Content-Type"
        )
    ,
        ( "Access-Control-Allow-Private-Network"
        , "true"
        )
    ]
