module AgentDaemon.Worktree
    ( createWorktree
    , removeWorktree
    ) where

-- \|
-- Module      : AgentDaemon.Worktree
-- Description : Git worktree management
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Creates and removes git worktrees for agent sessions.
-- Each issue gets its own worktree branching from the
-- repository's main branch.

import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as T
import System.Process (callProcess)

-- | Create a git worktree for an issue.
createWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree destination path
    -> Text
    -- ^ branch name
    -> IO (Either Text ())
createWorktree repoPath worktreePath branch = do
    fetchResult <-
        runGit
            repoPath
            ["fetch", "origin", "main"]
    case fetchResult of
        Left e -> pure (Left e)
        Right () ->
            runGit
                repoPath
                [ "worktree"
                , "add"
                , worktreePath
                , "-b"
                , T.unpack branch
                , "origin/main"
                ]

-- | Remove a git worktree.
removeWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree path to remove
    -> IO (Either Text ())
removeWorktree repoPath worktreePath =
    runGit
        repoPath
        [ "worktree"
        , "remove"
        , "--force"
        , worktreePath
        ]

-- | Run a git command, capturing failures as 'Left'.
runGit :: FilePath -> [String] -> IO (Either Text ())
runGit repoPath args = do
    result <-
        try (callProcess "git" ("-C" : repoPath : args))
    pure $ case result of
        Left e ->
            Left $
                "git "
                    <> T.pack (unwords args)
                    <> " failed: "
                    <> T.pack (show (e :: IOException))
        Right () -> Right ()
