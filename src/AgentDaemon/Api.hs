module AgentDaemon.Api
    ( apiApp
    ) where

-- \|
-- Module      : AgentDaemon.Api
-- Description : REST API for session management
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- WAI application providing REST endpoints for launching,
-- listing, and stopping agent sessions.

import AgentDaemon.Recovery (getRepoOwner)
import AgentDaemon.Tmux qualified as Tmux
import AgentDaemon.Types
    ( LaunchRequest (..)
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
import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.HTTP.Types
    ( ResponseHeaders
    , status200
    , status201
    , status204
    , status400
    , status404
    , status500
    )
import Network.Wai
    ( Application
    , Middleware
    , mapResponseHeaders
    , pathInfo
    , requestMethod
    , responseFile
    , responseLBS
    , strictRequestBody
    )
import System.Directory (doesDirectoryExist, listDirectory)

-- | WAI application for the REST API and static files.
apiApp
    :: FilePath
    -- ^ base directory for worktrees
    -> FilePath
    -- ^ static files directory
    -> SessionManager
    -> Application
apiApp baseDir staticDir mgr =
    cors $ \req respond ->
        case (requestMethod req, pathInfo req) of
            ("OPTIONS", _) ->
                respond $
                    responseLBS status204 [] ""
            ("POST", ["sessions"]) ->
                handleLaunch baseDir mgr req respond
            ("GET", ["sessions"]) ->
                handleList mgr req respond
            ("GET", ["worktrees"]) ->
                handleListWorktrees baseDir req respond
            ("DELETE", ["sessions", sid]) ->
                handleStop
                    baseDir
                    mgr
                    (SessionId sid)
                    req
                    respond
            _ ->
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
    -> Application
handleLaunch baseDir mgr req respond = do
    body <- strictRequestBody req
    case Aeson.decode body of
        Nothing ->
            respondError status400 "Invalid request body"
        Just LaunchRequest{launchRepo, launchIssue} ->
            do
                let sid =
                        mkSessionId
                            launchRepo
                            launchIssue
                existing <- readTVarIO (sessions mgr)
                case Map.lookup sid existing of
                    Just session ->
                        respond $
                            responseLBS
                                status200
                                jsonHeaders
                                (Aeson.encode session)
                    Nothing ->
                        launchSession
                            baseDir
                            mgr
                            sid
                            launchRepo
                            launchIssue
  where
    respondError status msg =
        respond $
            responseLBS
                status
                jsonHeaders
                (Aeson.encode $ errorJson msg)

    launchSession baseDir' mgr' sid repo issue = do
        let tmuxName = mkTmuxName repo issue
            worktree =
                mkWorktreePath baseDir' repo issue
        now <- getCurrentTime
        let session =
                Session
                    { sessionId = sid
                    , sessionRepo = repo
                    , sessionIssue = issue
                    , sessionWorktree = worktree
                    , sessionTmuxName = tmuxName
                    , sessionState = Creating
                    , sessionCreatedAt = now
                    }
        atomically $ do
            m <- readTVar (sessions mgr')
            writeTVar (sessions mgr') $
                Map.insert sid session m
        result <- runLaunchSteps tmuxName worktree
        case result of
            Left reason -> do
                setSessionState
                    mgr'
                    sid
                    (Failed reason)
                respond $
                    responseLBS
                        status500
                        jsonHeaders
                        (Aeson.encode $ errorJson reason)
            Right () -> do
                setSessionState mgr' sid Running
                respond $
                    responseLBS
                        status201
                        jsonHeaders
                        ( Aeson.encode
                            session
                                { sessionState =
                                    Running
                                }
                        )
      where
        runLaunchSteps tmuxName' worktree' = do
            wtResult <-
                Worktree.createWorktree
                    (repoPath baseDir' repo)
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
    -> Application
handleList mgr _req respond = do
    m <- readTVarIO (sessions mgr)
    respond $
        responseLBS
            status200
            jsonHeaders
            (Aeson.encode $ Map.elems m)

-- | List all worktree directories on disk.
handleListWorktrees
    :: FilePath
    -> Application
handleListWorktrees baseDir _req respond = do
    entries <- listDirectory baseDir
    worktrees <-
        catMaybes
            <$> mapM (toWorktreeInfo baseDir) entries
    respond $
        responseLBS
            status200
            jsonHeaders
            (Aeson.encode worktrees)

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

-- | Stop a session and clean up resources.
handleStop
    :: FilePath
    -> SessionManager
    -> SessionId
    -> Application
handleStop baseDir mgr sid _req respond = do
    m <- readTVarIO (sessions mgr)
    case Map.lookup sid m of
        Nothing ->
            respond $
                responseLBS
                    status404
                    jsonHeaders
                    ( Aeson.encode $
                        errorJson
                            ( "Session "
                                <> unSessionId sid
                                <> " not found"
                            )
                    )
        Just session -> do
            _ <-
                Tmux.killSession
                    (sessionTmuxName session)
            _ <-
                Worktree.removeWorktree
                    ( repoPath
                        baseDir
                        (sessionRepo session)
                    )
                    (sessionWorktree session)
            atomically $ do
                current <- readTVar (sessions mgr)
                writeTVar (sessions mgr) $
                    Map.delete sid current
            respond $
                responseLBS
                    status200
                    jsonHeaders
                    ( Aeson.encode $
                        Aeson.object
                            [
                                ( "status"
                                , Aeson.String "stopped"
                                )
                            ]
                    )

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
    ]
