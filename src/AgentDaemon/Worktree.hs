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

import AgentDaemon.Git qualified as Git
import AgentDaemon.Types (GitError (..))
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory (doesDirectoryExist)

{- | Create a git worktree for an issue.

If the worktree directory already exists, succeeds
without doing anything. If the branch already exists,
reuses it instead of creating a new one.
-}
createWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree destination path
    -> Text
    -- ^ branch name
    -> IO (Either Text ())
createWorktree repoPath worktreePath branch = do
    exists <- doesDirectoryExist worktreePath
    if exists
        then pure (Right ())
        else do
            defBranch <- Git.defaultBranch repoPath
            fetchResult <-
                Git.fetch
                    repoPath
                    (T.unpack defBranch)
            case mapErr fetchResult of
                Left e -> pure (Left e)
                Right () -> do
                    let baseRef =
                            "origin/" <> defBranch
                    mapErr
                        <$> Git.createWorktree
                            repoPath
                            worktreePath
                            branch
                            baseRef

-- | Remove a git worktree.
removeWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree path to remove
    -> IO (Either Text ())
removeWorktree repoPath worktreePath =
    mapErr <$> Git.removeWorktree repoPath worktreePath

-- | Map 'GitError' to 'Text' for backward compat.
mapErr :: Either GitError a -> Either Text a
mapErr (Right a) = Right a
mapErr (Left GitError{gitCommand, gitStderr}) =
    Left $
        "git "
            <> gitCommand
            <> " failed: "
            <> gitStderr
