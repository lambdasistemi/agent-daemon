module AgentDaemon.Recovery
    ( recoverSessions
    , getRepoOwner
    ) where

-- \| Module      : AgentDaemon.Recovery
-- Description : Session recovery on daemon restart
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Discovers running tmux sessions and reconstructs the
-- in-memory session registry from them.

import AgentDaemon.Types
    ( Repo (..)
    , Session (..)
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
import System.Directory (doesDirectoryExist)
import System.Process (readProcess)

{- | Recover sessions from running tmux sessions.

Scans tmux for active sessions, matches them against
worktree directories under the base dir, and populates
the session manager.
-}
recoverSessions
    :: FilePath
    -- ^ base directory for worktrees
    -> SessionManager
    -> IO ()
recoverSessions baseDir mgr = do
    names <- listTmuxSessions
    results <- mapM (recoverSession baseDir) names
    let recovered =
            Map.fromList
                [ (sessionId s, s)
                | Just s <- results
                ]
        tvar = sessions mgr
    atomically $ do
        m <- readTVar tvar
        writeTVar tvar (Map.union m recovered)
    let n = Map.size recovered
    putStrLn $
        "Recovered "
            <> show n
            <> " session(s) from tmux"

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

{- | Try to recover a session from a tmux session name.

The tmux name follows the pattern @repoName-issueNum@.
The worktree is expected at @baseDir/repoName-issue-N@.
The repo owner is read from the git remote in the
worktree.
-}
recoverSession
    :: FilePath -> Text -> IO (Maybe Session)
recoverSession baseDir tmuxName =
    case parseTmuxName tmuxName of
        Nothing -> pure Nothing
        Just (repoName, issue) -> do
            let worktree =
                    baseDir
                        <> "/"
                        <> T.unpack repoName
                        <> "-issue-"
                        <> show issue
            exists <- doesDirectoryExist worktree
            if not exists
                then pure Nothing
                else do
                    owner <- getRepoOwner worktree
                    now <- getCurrentTime
                    let repo =
                            Repo
                                { repoOwner = owner
                                , repoName = repoName
                                }
                        sid = SessionId tmuxName
                    pure $
                        Just
                            Session
                                { sessionId = sid
                                , sessionRepo = repo
                                , sessionIssue = issue
                                , sessionWorktree =
                                    worktree
                                , sessionTmuxName =
                                    tmuxName
                                , sessionState = Running
                                , sessionCreatedAt = now
                                , sessionPrompt = ""
                                , sessionLastActivity =
                                    now
                                }

{- | Parse a tmux session name into repo name and
issue number.

@"agent-daemon-99"@ becomes
@Just ("agent-daemon", 99)@.

Splits on the last @-@ so repo names with hyphens
are handled correctly.
-}
parseTmuxName :: Text -> Maybe (Text, Int)
parseTmuxName name =
    case T.breakOnEnd "-" name of
        ("", _) -> Nothing
        (prefix, suffix) -> do
            issue <- readMaybe (T.unpack suffix)
            -- prefix includes the trailing "-"
            let repoName = T.dropEnd 1 prefix
            if T.null repoName
                then Nothing
                else Just (repoName, issue)

-- | Read an integer, returning Nothing on failure.
readMaybe :: String -> Maybe Int
readMaybe s = case reads s of
    [(n, "")] -> Just n
    _ -> Nothing

{- | Get the repo owner from the git remote URL in a
worktree. Falls back to @"unknown"@ if parsing fails.
-}
getRepoOwner :: FilePath -> IO Text
getRepoOwner worktree = do
    result <-
        try
            ( readProcess
                "git"
                [ "-C"
                , worktree
                , "remote"
                , "get-url"
                , "origin"
                ]
                ""
            )
    pure $ case result of
        Left (_ :: IOException) -> "unknown"
        Right url -> parseOwner (T.strip (T.pack url))

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
