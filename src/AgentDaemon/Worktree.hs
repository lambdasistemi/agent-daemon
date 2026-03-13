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
    -> IO ()
createWorktree repoPath worktreePath branch = do
    callProcess
        "git"
        [ "-C"
        , repoPath
        , "fetch"
        , "origin"
        , "main"
        ]
    callProcess
        "git"
        [ "-C"
        , repoPath
        , "worktree"
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
    -> IO ()
removeWorktree repoPath worktreePath =
    callProcess
        "git"
        [ "-C"
        , repoPath
        , "worktree"
        , "remove"
        , "--force"
        , worktreePath
        ]
