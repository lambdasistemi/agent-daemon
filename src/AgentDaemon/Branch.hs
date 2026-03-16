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

import AgentDaemon.Recovery (getRepoOwner)
import AgentDaemon.Types
    ( BranchInfo (..)
    , Repo (..)
    , SyncStatus (..)
    )
import Control.Exception (IOException, try)
import Data.List (dropWhileEnd, isPrefixOf)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import System.Directory (doesDirectoryExist, listDirectory)
import System.Process (readProcess)

-- | List all local issue branches across all repos.
listBranches :: FilePath -> IO [BranchInfo]
listBranches baseDir = do
    entries <- listDirectory baseDir
    fmap concat $ mapM (repoBranches baseDir) entries

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
    let repoPath = baseDir <> "/" <> T.unpack repoName
    exists <- doesDirectoryExist repoPath
    if not exists
        then pure (Left "repository not found")
        else do
            let flag = if force then "-D" else "-d"
            localResult <-
                runGit
                    repoPath
                    ["branch", flag, T.unpack branch]
            case localResult of
                Left e -> pure (Left e)
                Right () -> do
                    -- Best-effort remote delete
                    _ <-
                        runGit
                            repoPath
                            [ "push"
                            , "origin"
                            , "--delete"
                            , T.unpack branch
                            ]
                    pure (Right ())

-- | Find issue branches in a single repo directory.
repoBranches :: FilePath -> FilePath -> IO [BranchInfo]
repoBranches baseDir name = do
    let repoPath = baseDir <> "/" <> name
    isDir <- doesDirectoryExist repoPath
    isGit <- doesDirectoryExist (repoPath <> "/.git")
    if not (isDir && isGit)
        then pure []
        else do
            branches <- listIssueBranches repoPath
            owner <- getRepoOwner repoPath
            let repo =
                    Repo
                        { repoOwner = owner
                        , repoName = T.pack name
                        }
            catMaybes <$> mapM (toBranchInfo repoPath repo) branches

-- | List local branches matching @feat/issue-*@.
listIssueBranches :: FilePath -> IO [String]
listIssueBranches repoPath = do
    result <-
        try
            ( readProcess
                "git"
                [ "-C"
                , repoPath
                , "branch"
                , "--list"
                , "feat/issue-*"
                , "--format=%(refname:short)"
                ]
                ""
            )
    pure $ case result of
        Right out -> filter (not . null) $ lines out
        Left (_ :: IOException) -> []

-- | Build a BranchInfo from a branch name.
toBranchInfo
    :: FilePath -> Repo -> String -> IO (Maybe BranchInfo)
toBranchInfo repoPath repo branch =
    case parseIssueBranch branch of
        Nothing -> pure Nothing
        Just issue -> do
            sync <- getSyncStatus repoPath branch
            pure $
                Just
                    BranchInfo
                        { branchRepo = repo
                        , branchIssue = issue
                        , branchName = T.pack branch
                        , branchSync = sync
                        }

-- | Parse issue number from @feat/issue-N@.
parseIssueBranch :: String -> Maybe Int
parseIssueBranch branch
    | "feat/issue-" `isPrefixOf` branch =
        case reads (drop 12 branch) of
            [(n, "")] -> Just n
            _ -> Nothing
    | otherwise = Nothing

-- | Get sync status between local and remote branch.
getSyncStatus :: FilePath -> String -> IO SyncStatus
getSyncStatus repoPath branch = do
    -- First check if remote tracking branch exists
    hasRemote <-
        try
            ( readProcess
                "git"
                [ "-C"
                , repoPath
                , "rev-parse"
                , "--verify"
                , "origin/" <> branch
                ]
                ""
            )
    case hasRemote of
        Left (_ :: IOException) -> pure LocalOnly
        Right _ -> do
            result <-
                try
                    ( readProcess
                        "git"
                        [ "-C"
                        , repoPath
                        , "rev-list"
                        , "--left-right"
                        , "--count"
                        , branch <> "...origin/" <> branch
                        ]
                        ""
                    )
            pure $ case result of
                Left (_ :: IOException) -> LocalOnly
                Right out ->
                    case words (dropWhileEnd (== '\n') out) of
                        [aStr, bStr] ->
                            case (reads aStr, reads bStr) of
                                ([(a, "")], [(b, "")]) ->
                                    case (a :: Int, b :: Int) of
                                        (0, 0) -> Synced
                                        (n, 0) -> Ahead n
                                        (0, n) -> Behind n
                                        (a', b') ->
                                            Diverged a' b'
                                _ -> LocalOnly
                        _ -> LocalOnly

-- | Run a git command, capturing failures as 'Left'.
runGit :: FilePath -> [String] -> IO (Either Text ())
runGit repoPath args = do
    result <-
        try
            ( readProcess
                "git"
                ("-C" : repoPath : args)
                ""
            )
    pure $ case result of
        Left e ->
            Left $
                "git "
                    <> T.pack (unwords args)
                    <> " failed: "
                    <> T.pack (show (e :: IOException))
        Right _ -> Right ()
