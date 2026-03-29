module AgentDaemon.Branch
    ( listBranches
    , deleteBranch
    ) where

-- \|
-- Module      : AgentDaemon.Branch
-- Description : Git branch management
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Lists and deletes local issue branches, reporting
-- sync status with the remote.

import AgentDaemon.Git qualified as Git
import AgentDaemon.Recovery (getRepoOwner)
import AgentDaemon.Types
    ( BranchInfo (..)
    , GitError (..)
    , Repo (..)
    )
import Data.List (isPrefixOf)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory
    ( doesDirectoryExist
    , listDirectory
    )

-- | List all local issue branches across all repos.
listBranches :: FilePath -> IO [BranchInfo]
listBranches baseDir = do
    entries <- listDirectory baseDir
    concat <$> mapM (repoBranches baseDir) entries

-- | Delete a branch locally and on the remote.
deleteBranch
    :: FilePath
    -- ^ base directory
    -> Text
    -- ^ repo name
    -> Text
    -- ^ branch name
    -> Bool
    -- ^ force delete even if not merged
    -> IO (Either Text ())
deleteBranch baseDir repoName branch force = do
    let repoPath =
            baseDir <> "/" <> T.unpack repoName
    exists <- doesDirectoryExist repoPath
    if not exists
        then pure (Left "repository not found")
        else do
            localResult <-
                Git.deleteBranchLocal
                    repoPath
                    (T.unpack branch)
                    force
            case mapErr localResult of
                Left e -> pure (Left e)
                Right () -> do
                    -- Best-effort remote delete
                    _ <-
                        Git.deleteBranchRemote
                            repoPath
                            (T.unpack branch)
                    pure (Right ())

-- | Find issue branches in a single repo directory.
repoBranches
    :: FilePath -> FilePath -> IO [BranchInfo]
repoBranches baseDir name = do
    let repoPath = baseDir <> "/" <> name
    isDir <- doesDirectoryExist repoPath
    isGit <-
        doesDirectoryExist (repoPath <> "/.git")
    if not (isDir && isGit)
        then pure []
        else do
            result <-
                Git.listBranchesByPattern
                    repoPath
                    "feat/issue-*"
            let branches = case result of
                    Right bs -> bs
                    Left _ -> []
            owner <- getRepoOwner repoPath
            let repo =
                    Repo
                        { repoOwner = owner
                        , repoName = T.pack name
                        }
            catMaybes
                <$> mapM
                    (toBranchInfo repoPath repo)
                    branches

-- | Build a BranchInfo from a branch name.
toBranchInfo
    :: FilePath
    -> Repo
    -> String
    -> IO (Maybe BranchInfo)
toBranchInfo repoPath repo branch =
    case parseIssueBranch branch of
        Nothing -> pure Nothing
        Just issue -> do
            sync <- Git.syncStatus repoPath branch
            pure $
                Just
                    BranchInfo
                        { branchRepo = repo
                        , branchIssue = issue
                        , branchName = T.pack branch
                        , branchSync = sync
                        }

-- | Parse issue number from @feat\/issue-N@.
parseIssueBranch :: String -> Maybe Int
parseIssueBranch branch
    | "feat/issue-" `isPrefixOf` branch =
        case reads (drop 11 branch) of
            [(n, "")] -> Just n
            _ -> Nothing
    | otherwise = Nothing

-- | Map 'GitError' to 'Text' for backward compat.
mapErr :: Either GitError a -> Either Text a
mapErr (Right a) = Right a
mapErr (Left GitError{gitCommand, gitStderr}) =
    Left $
        "git "
            <> gitCommand
            <> " failed: "
            <> gitStderr
