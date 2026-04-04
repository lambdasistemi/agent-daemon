module AgentDaemon.GitSpec (spec) where

-- \|
-- Module      : AgentDaemon.GitSpec
-- Description : Tests for AgentDaemon.Git
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Git qualified as Git
import AgentDaemon.Types
    ( GitError (..)
    , SyncStatus (..)
    )
import Data.Either (isLeft, isRight)
import Data.Text qualified as T
import System.Directory (doesDirectoryExist)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
    ( Spec
    , around
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec = do
    describe "parseSyncCounts" parseSyncCountsSpec
    describe "runGit" runGitSpec
    describe "readGit" readGitSpec
    describe "defaultBranch" defaultBranchSpec
    describe "worktree operations" worktreeSpec
    describe "branch operations" branchSpec
    describe "remote operations" remoteSpec

-- ----------------------------------------------------------
-- Pure unit tests
-- ----------------------------------------------------------

parseSyncCountsSpec :: Spec
parseSyncCountsSpec = do
    it "parses synced (0 0)" $
        Git.parseSyncCounts "0\t0"
            `shouldBe` Synced

    it "parses ahead" $
        Git.parseSyncCounts "3\t0"
            `shouldBe` Ahead 3

    it "parses behind" $
        Git.parseSyncCounts "0\t5"
            `shouldBe` Behind 5

    it "parses diverged" $
        Git.parseSyncCounts "2\t4"
            `shouldBe` Diverged 2 4

    it "returns LocalOnly for garbage" $
        Git.parseSyncCounts "not-a-count"
            `shouldBe` LocalOnly

    it "returns LocalOnly for empty" $
        Git.parseSyncCounts ""
            `shouldBe` LocalOnly

    it "handles trailing newline" $
        Git.parseSyncCounts "1\t0\n"
            `shouldBe` Ahead 1

-- ----------------------------------------------------------
-- Integration tests against a temp git repo
-- ----------------------------------------------------------

-- | Set up a bare + clone pair for testing.
withTestRepo :: (FilePath -> IO a) -> IO a
withTestRepo action =
    withSystemTempDirectory "git-test" $ \tmpDir -> do
        let bare = tmpDir <> "/bare.git"
            clone = tmpDir <> "/clone"
        callProcess "git" ["init", "--bare", bare]
        callProcess
            "git"
            ["clone", bare, clone]
        callProcess
            "git"
            ["-C", clone, "config", "user.name", "Test"]
        callProcess
            "git"
            [ "-C"
            , clone
            , "config"
            , "user.email"
            , "test@test.com"
            ]
        -- Create initial commit so HEAD exists
        callProcess
            "git"
            [ "-C"
            , clone
            , "commit"
            , "--allow-empty"
            , "-m"
            , "init"
            ]
        callProcess
            "git"
            ["-C", clone, "push", "origin", "main"]
        action clone

runGitSpec :: Spec
runGitSpec = around withTestRepo $ do
    it "succeeds for valid commands" $ \repo -> do
        result <- Git.runGit repo ["status"]
        result `shouldSatisfy` isRight

    it "returns GitError for invalid commands" $
        \repo -> do
            result <-
                Git.runGit repo ["checkout", "nonexistent"]
            result `shouldSatisfy` isLeft
            case result of
                Left e -> do
                    gitExitCode e
                        `shouldSatisfy` (> 0)
                    gitRepoPath e `shouldBe` repo
                Right _ -> fail "expected Left"

readGitSpec :: Spec
readGitSpec = around withTestRepo $ do
    it "returns stripped stdout on success" $ \repo ->
        do
            result <-
                Git.readGit
                    repo
                    ["rev-parse", "--abbrev-ref", "HEAD"]
            result `shouldBe` Right "main"

    it "returns GitError on failure" $ \repo -> do
        result <-
            Git.readGit
                repo
                ["rev-parse", "--verify", "bogus"]
        result `shouldSatisfy` isLeft

defaultBranchSpec :: Spec
defaultBranchSpec = around withTestRepo $ do
    it "detects default branch from origin/HEAD" $
        \repo -> do
            branch <- Git.defaultBranch repo
            branch `shouldBe` "main"

    it "falls back to main when origin/HEAD unset" $
        \_ ->
            withSystemTempDirectory "git-no-remote" $
                \tmpDir -> do
                    let repo = tmpDir <> "/lonely"
                    callProcess "git" ["init", repo]
                    branch <- Git.defaultBranch repo
                    branch `shouldBe` "main"

worktreeSpec :: Spec
worktreeSpec = around withTestRepo $ do
    it "creates and removes a worktree" $ \repo ->
        withSystemTempDirectory "wt-test" $ \tmpDir ->
            do
                let wtPath =
                        tmpDir <> "/my-worktree"
                result <-
                    Git.createWorktree
                        repo
                        wtPath
                        "feat/test-branch"
                        "origin/main"
                result `shouldSatisfy` isRight
                doesDirectoryExist wtPath
                    >>= (`shouldBe` True)

                removeResult <-
                    Git.removeWorktree repo wtPath
                removeResult `shouldSatisfy` isRight
                doesDirectoryExist wtPath
                    >>= (`shouldBe` False)

    it "reuses existing branch on second create" $
        \repo ->
            withSystemTempDirectory "wt-reuse" $
                \tmpDir -> do
                    let wt1 = tmpDir <> "/wt1"
                        wt2 = tmpDir <> "/wt2"
                    -- First create makes the branch
                    r1 <-
                        Git.createWorktree
                            repo
                            wt1
                            "feat/reuse-me"
                            "origin/main"
                    r1 `shouldSatisfy` isRight
                    -- Clean up wt1 so branch exists
                    -- but worktree is gone
                    _ <- Git.removeWorktree repo wt1

                    -- Second create should reuse
                    r2 <-
                        Git.createWorktree
                            repo
                            wt2
                            "feat/reuse-me"
                            "origin/main"
                    r2 `shouldSatisfy` isRight
                    doesDirectoryExist wt2
                        >>= (`shouldBe` True)
                    _ <- Git.removeWorktree repo wt2
                    pure ()

    it "fails for invalid base ref" $ \repo ->
        withSystemTempDirectory "wt-fail" $ \tmpDir ->
            do
                let wtPath = tmpDir <> "/bad-wt"
                result <-
                    Git.createWorktree
                        repo
                        wtPath
                        "feat/bad"
                        "origin/nonexistent"
                result `shouldSatisfy` isLeft

branchSpec :: Spec
branchSpec = around withTestRepo $ do
    it "lists branches by pattern" $ \repo -> do
        -- Create some branches
        callProcess
            "git"
            ["-C", repo, "branch", "feat/issue-1"]
        callProcess
            "git"
            ["-C", repo, "branch", "feat/issue-2"]
        callProcess
            "git"
            ["-C", repo, "branch", "unrelated"]
        result <-
            Git.listBranchesByPattern
                repo
                "feat/issue-*"
        case result of
            Right bs -> do
                length bs `shouldBe` 2
                bs
                    `shouldSatisfy` elem "feat/issue-1"
                bs
                    `shouldSatisfy` elem "feat/issue-2"
            Left e ->
                fail $
                    "expected Right, got: "
                        <> show e

    it "returns empty for no matches" $ \repo -> do
        result <-
            Git.listBranchesByPattern
                repo
                "no-match-*"
        result `shouldBe` Right []

    it "verifies existing ref" $ \repo -> do
        exists <- Git.revParseVerify repo "main"
        exists `shouldBe` True

    it "rejects missing ref" $ \repo -> do
        exists <- Git.revParseVerify repo "bogus"
        exists `shouldBe` False

    it "reports LocalOnly for branch without remote" $
        \repo -> do
            callProcess
                "git"
                [ "-C"
                , repo
                , "branch"
                , "feat/local-only"
                ]
            status <-
                Git.syncStatus repo "feat/local-only"
            status `shouldBe` LocalOnly

    it "reports Synced for pushed branch" $ \repo -> do
        callProcess
            "git"
            [ "-C"
            , repo
            , "checkout"
            , "-b"
            , "feat/synced"
            ]
        callProcess
            "git"
            [ "-C"
            , repo
            , "commit"
            , "--allow-empty"
            , "-m"
            , "sync"
            ]
        callProcess
            "git"
            [ "-C"
            , repo
            , "push"
            , "origin"
            , "feat/synced"
            ]
        status <-
            Git.syncStatus repo "feat/synced"
        status `shouldBe` Synced

    it "reports Ahead for unpushed commits" $
        \repo -> do
            callProcess
                "git"
                [ "-C"
                , repo
                , "checkout"
                , "-b"
                , "feat/ahead"
                ]
            callProcess
                "git"
                [ "-C"
                , repo
                , "push"
                , "origin"
                , "feat/ahead"
                ]
            callProcess
                "git"
                [ "-C"
                , repo
                , "commit"
                , "--allow-empty"
                , "-m"
                , "local"
                ]
            status <-
                Git.syncStatus repo "feat/ahead"
            status `shouldBe` Ahead 1

    it "deletes a local branch" $ \repo -> do
        callProcess
            "git"
            ["-C", repo, "branch", "feat/delete-me"]
        result <-
            Git.deleteBranchLocal
                repo
                "feat/delete-me"
                False
        result `shouldSatisfy` isRight
        exists <-
            Git.revParseVerify repo "feat/delete-me"
        exists `shouldBe` False

    it "fails to delete non-existent branch" $
        \repo -> do
            result <-
                Git.deleteBranchLocal
                    repo
                    "feat/ghost"
                    False
            result `shouldSatisfy` isLeft

remoteSpec :: Spec
remoteSpec = around withTestRepo $ do
    it "gets remote URL" $ \repo -> do
        result <- Git.getRemoteUrl repo "origin"
        result `shouldSatisfy` isRight
        case result of
            Right url ->
                url
                    `shouldSatisfy` T.isInfixOf
                        "bare.git"
            Left _ -> fail "expected Right"

    it "fails for non-existent remote" $ \repo -> do
        result <- Git.getRemoteUrl repo "upstream"
        result `shouldSatisfy` isLeft
