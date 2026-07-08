module AgentDaemon.Recovery
    ( recoverSessions
    , getRepoOwner
    , parseOwner
    ) where

-- \| Module      : AgentDaemon.Recovery
-- Description : Session recovery on daemon restart
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Discovers running tmux sessions and reconstructs the
-- in-memory session registry from them.

import AgentDaemon.Git qualified as Git
import AgentDaemon.Types
    ( Session (..)
    , SessionId (..)
    , SessionManager (..)
    , SessionState (..)
    )
import Control.Concurrent.STM
    ( atomically
    , readTVar
    , writeTVar
    )
import Control.Exception (IOException, try)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import System.Process (readProcess)

{- | Recover sessions from running tmux sessions.

Scans tmux for active sessions and populates the session manager.
-}
recoverSessions
    :: FilePath
    -- ^ fallback directory when tmux does not report a path
    -> SessionManager
    -> IO ()
recoverSessions baseDir mgr = do
    names <- listTmuxSessions
    recoveredSessions <- mapM (recoverTmuxSession baseDir) names
    let recovered =
            Map.fromList
                [ (sessionId s, s)
                | s <- recoveredSessions
                ]
        tvar = sessions mgr
    atomically $ do
        current <- readTVar tvar
        let activeCurrent = Map.intersection current recovered
        writeTVar tvar (Map.union activeCurrent recovered)

-- | List tmux session names, returning empty on failure.
listTmuxSessions :: IO [Text]
listTmuxSessions = do
    result <-
        try
            ( readProcess
                "tmux"
                [ "list-sessions"
                , "-F"
                , "#{session_name}"
                ]
                ""
            )
    pure $ case result of
        Left (_ :: IOException) -> []
        Right out ->
            filter (not . T.null) $
                T.lines (T.pack out)

-- | Recover a tmux session as a browser-controllable session.
recoverTmuxSession
    :: FilePath -> Text -> IO Session
recoverTmuxSession baseDir tmuxName = do
    currentPath <- tmuxSessionPath baseDir tmuxName
    now <- getCurrentTime
    let sid = SessionId tmuxName
    pure
        Session
            { sessionId = sid
            , sessionTmuxName = tmuxName
            , sessionCurrentPath = currentPath
            , sessionState = Running
            , sessionCreatedAt = now
            , sessionLastActivity = now
            }

-- | Read the active pane path for a tmux session, falling back to baseDir.
tmuxSessionPath :: FilePath -> Text -> IO FilePath
tmuxSessionPath baseDir tmuxName = do
    result <-
        try
            ( readProcess
                "tmux"
                [ "display-message"
                , "-p"
                , "-t"
                , T.unpack tmuxName
                , "#{pane_current_path}"
                ]
                ""
            )
    pure $ case result of
        Left (_ :: IOException) -> baseDir
        Right out ->
            case T.unpack (T.strip (T.pack out)) of
                "" -> baseDir
                path -> path

{- | Get the repo owner from the git remote URL in a
worktree. Falls back to @"unknown"@ if parsing fails.
-}
getRepoOwner :: FilePath -> IO Text
getRepoOwner worktree = do
    result <- Git.getRemoteUrl worktree "origin"
    pure $ case result of
        Left _ -> "unknown"
        Right url -> parseOwner url

{- | Extract the owner from a git remote URL.

Handles both SSH and HTTPS formats:

* @git\@github.com:owner\/repo.git@ → @owner@
* @https:\/\/github.com\/owner\/repo.git@ → @owner@
-}
parseOwner :: Text -> Text
parseOwner url
    | "git@" `T.isPrefixOf` url =
        -- git@github.com:owner/repo.git
        case T.breakOn ":" url of
            (_, rest) ->
                case T.breakOn "/" (T.drop 1 rest) of
                    (owner, _) -> owner
    | "https://" `T.isPrefixOf` url =
        -- https://github.com/owner/repo.git
        case T.splitOn "/" url of
            (_ : _ : _ : owner : _) -> owner
            _ -> "unknown"
    | otherwise = "unknown"
