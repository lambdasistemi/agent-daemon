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

import AgentDaemon.Tmux qualified as Tmux
import AgentDaemon.Types
    ( LaunchRequest (..)
    , Repo (..)
    , Session (..)
    , SessionId (..)
    , SessionManager (..)
    , SessionState (..)
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
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.HTTP.Types
    ( ResponseHeaders
    , status200
    , status201
    , status400
    , status404
    , status409
    , status500
    )
import Network.Wai
    ( Application
    , pathInfo
    , requestMethod
    , responseLBS
    , strictRequestBody
    )

-- | WAI application for the REST API.
apiApp
    :: FilePath
    -- ^ base directory for worktrees
    -> SessionManager
    -> Application
apiApp baseDir mgr req respond =
    case (requestMethod req, pathInfo req) of
        ("POST", ["sessions"]) ->
            handleLaunch baseDir mgr req respond
        ("GET", ["sessions"]) ->
            handleList mgr req respond
        ("DELETE", ["sessions", sid]) ->
            handleStop
                baseDir
                mgr
                (SessionId sid)
                req
                respond
        _ ->
            respond $
                responseLBS status404 [] "Not found"

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
                if Map.member sid existing
                    then
                        respondError
                            status409
                            ( "Session "
                                <> unSessionId sid
                                <> " already exists"
                            )
                    else launchSession
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
                                "claude"

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
                            [ ( "status"
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
