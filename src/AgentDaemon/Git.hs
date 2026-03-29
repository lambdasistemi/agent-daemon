module AgentDaemon.Git
    ( -- * Core primitives
      runGit
    , readGit

      -- * Worktree operations
    , createWorktree
    , removeWorktree
    , defaultBranch
    , fetch

      -- * Branch operations
    , listBranchesByPattern
    , revParseVerify
    , syncStatus
    , deleteBranchLocal
    , deleteBranchRemote

      -- * Remote operations
    , getRemoteUrl
    ) where

-- \|
-- Module      : AgentDaemon.Git
-- Description : Centralized git CLI wrapper
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- All git subprocess interactions go through this module.
-- Uses @typed-process@ for explicit exit-code handling
-- and returns structured 'GitError' values on failure.

import AgentDaemon.Types (GitError (..), SyncStatus (..))
import Data.ByteString.Lazy qualified as LBS
import Data.List (dropWhileEnd)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Exit (ExitCode (..))
import System.Process.Typed qualified as P

{- | Run a git command, discard stdout, capture stderr
on failure.
-}
runGit
    :: FilePath
    -- ^ repository path
    -> [String]
    -- ^ git arguments
    -> IO (Either GitError ())
runGit repoPath args = do
    (exitCode, _stdout, stderr) <-
        P.readProcess
            ( P.proc
                "git"
                ("-C" : repoPath : args)
            )
    pure $ case exitCode of
        ExitSuccess -> Right ()
        ExitFailure code ->
            Left
                GitError
                    { gitCommand =
                        T.pack (unwords args)
                    , gitExitCode = code
                    , gitStderr =
                        TE.decodeUtf8
                            (LBS.toStrict stderr)
                    , gitRepoPath = repoPath
                    }

{- | Run a git command, return stdout as 'Text',
capture stderr on failure.
-}
readGit
    :: FilePath
    -- ^ repository path
    -> [String]
    -- ^ git arguments
    -> IO (Either GitError Text)
readGit repoPath args = do
    (exitCode, stdout, stderr) <-
        P.readProcess
            ( P.proc
                "git"
                ("-C" : repoPath : args)
            )
    pure $ case exitCode of
        ExitSuccess ->
            Right $
                T.strip $
                    TE.decodeUtf8
                        (LBS.toStrict stdout)
        ExitFailure code ->
            Left
                GitError
                    { gitCommand =
                        T.pack (unwords args)
                    , gitExitCode = code
                    , gitStderr =
                        TE.decodeUtf8
                            (LBS.toStrict stderr)
                    , gitRepoPath = repoPath
                    }

{- | Detect the default branch by reading
@refs\/remotes\/origin\/HEAD@. Falls back to @"main"@.
-}
defaultBranch :: FilePath -> IO Text
defaultBranch repoPath = do
    result <-
        readGit
            repoPath
            [ "symbolic-ref"
            , "refs/remotes/origin/HEAD"
            , "--short"
            ]
    pure $ case result of
        Right out ->
            case T.breakOn "/" out of
                (_, rest)
                    | T.null rest -> "main"
                    | otherwise -> T.drop 1 rest
        Left _ -> "main"

-- | Fetch a ref from origin.
fetch
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ refspec
    -> IO (Either GitError ())
fetch repoPath ref =
    runGit repoPath ["fetch", "origin", ref]

{- | Create a git worktree for an issue.

Tries creating a new branch first; if the branch
already exists, reuses it.
-}
createWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree destination path
    -> Text
    -- ^ branch name
    -> Text
    -- ^ base ref (e.g. @"origin\/main"@)
    -> IO (Either GitError ())
createWorktree repoPath worktreePath branch baseRef =
    do
        newBranch <-
            runGit
                repoPath
                [ "worktree"
                , "add"
                , worktreePath
                , "-b"
                , T.unpack branch
                , T.unpack baseRef
                ]
        case newBranch of
            Right () -> pure (Right ())
            Left _ ->
                runGit
                    repoPath
                    [ "worktree"
                    , "add"
                    , worktreePath
                    , T.unpack branch
                    ]

-- | Remove a git worktree.
removeWorktree
    :: FilePath
    -- ^ main repo path
    -> FilePath
    -- ^ worktree path to remove
    -> IO (Either GitError ())
removeWorktree repoPath worktreePath =
    runGit
        repoPath
        [ "worktree"
        , "remove"
        , "--force"
        , worktreePath
        ]

-- | List branches matching a glob pattern.
listBranchesByPattern
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ pattern (e.g. @"feat\/issue-*"@)
    -> IO (Either GitError [String])
listBranchesByPattern repoPath pattern = do
    result <-
        readGit
            repoPath
            [ "branch"
            , "--list"
            , pattern
            , "--format=%(refname:short)"
            ]
    pure $ case result of
        Right out ->
            Right $
                filter (not . null) $
                    lines (T.unpack out)
        Left e -> Left e

-- | Check whether a ref exists.
revParseVerify
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ ref to verify
    -> IO Bool
revParseVerify repoPath ref = do
    result <-
        readGit repoPath ["rev-parse", "--verify", ref]
    pure $ case result of
        Right _ -> True
        Left _ -> False

-- | Get sync status between local and remote branch.
syncStatus
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ branch name
    -> IO SyncStatus
syncStatus repoPath branch = do
    hasRemote <-
        revParseVerify repoPath ("origin/" <> branch)
    if not hasRemote
        then pure LocalOnly
        else do
            result <-
                readGit
                    repoPath
                    [ "rev-list"
                    , "--left-right"
                    , "--count"
                    , branch
                        <> "...origin/"
                        <> branch
                    ]
            pure $ case result of
                Left _ -> LocalOnly
                Right out ->
                    parseSyncCounts
                        (T.unpack out)

-- | Parse the ahead\/behind counts from rev-list output.
parseSyncCounts :: String -> SyncStatus
parseSyncCounts out =
    case words (dropWhileEnd (== '\n') out) of
        [aStr, bStr] ->
            case (reads aStr, reads bStr) of
                ([(a, "")], [(b, "")]) ->
                    case (a :: Int, b :: Int) of
                        (0, 0) -> Synced
                        (n, 0) -> Ahead n
                        (0, n) -> Behind n
                        (a', b') -> Diverged a' b'
                _ -> LocalOnly
        _ -> LocalOnly

-- | Delete a branch locally.
deleteBranchLocal
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ branch name
    -> Bool
    -- ^ force delete
    -> IO (Either GitError ())
deleteBranchLocal repoPath branch force =
    runGit
        repoPath
        ["branch", flag, branch]
  where
    flag = if force then "-D" else "-d"

-- | Delete a branch on the remote.
deleteBranchRemote
    :: FilePath
    -- ^ repository path
    -> String
    -- ^ branch name
    -> IO (Either GitError ())
deleteBranchRemote repoPath branch =
    runGit
        repoPath
        ["push", "origin", "--delete", branch]

-- | Get the URL of a remote.
getRemoteUrl
    :: FilePath
    -- ^ repository or worktree path
    -> String
    -- ^ remote name (e.g. @"origin"@)
    -> IO (Either GitError Text)
getRemoteUrl repoPath remote =
    readGit repoPath ["remote", "get-url", remote]
