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
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.HTTP.Types
    ( status200
    , status201
    , status404
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
            respond $
                responseLBS status404 [] "Invalid request"
        Just LaunchRequest{launchRepo, launchIssue} ->
            do
                let sid =
                        mkSessionId
                            launchRepo
                            launchIssue
                    tmuxName =
                        mkTmuxName
                            launchRepo
                            launchIssue
                    worktree =
                        mkWorktreePath
                            baseDir
                            launchRepo
                            launchIssue
                now <- getCurrentTime
                let session =
                        Session
                            { sessionId = sid
                            , sessionRepo = launchRepo
                            , sessionIssue = launchIssue
                            , sessionWorktree = worktree
                            , sessionTmuxName = tmuxName
                            , sessionState = Creating
                            , sessionCreatedAt = now
                            }
                atomically $ do
                    m <- readTVar (sessions mgr)
                    writeTVar (sessions mgr) $
                        Map.insert sid session m
                Worktree.createWorktree
                    (repoPath baseDir launchRepo)
                    worktree
                    ( "feat/issue-"
                        <> T.pack (show launchIssue)
                    )
                Tmux.createSession tmuxName worktree
                Tmux.sendKeys tmuxName "claude"
                atomically $ do
                    m <- readTVar (sessions mgr)
                    writeTVar (sessions mgr) $
                        Map.adjust
                            ( \s ->
                                s{sessionState = Running}
                            )
                            sid
                            m
                respond $
                    responseLBS
                        status201
                        [
                            ( "Content-Type"
                            , "application/json"
                            )
                        ]
                        (Aeson.encode session)

-- | List all active sessions.
handleList
    :: SessionManager
    -> Application
handleList mgr _req respond = do
    m <- readTVarIO (sessions mgr)
    respond $
        responseLBS
            status200
            [("Content-Type", "application/json")]
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
                    []
                    "Session not found"
        Just session -> do
            Tmux.killSession (sessionTmuxName session)
            Worktree.removeWorktree
                (repoPath baseDir (sessionRepo session))
                (sessionWorktree session)
            atomically $ do
                current <- readTVar (sessions mgr)
                writeTVar (sessions mgr) $
                    Map.delete sid current
            respond $
                responseLBS status200 [] "Stopped"
