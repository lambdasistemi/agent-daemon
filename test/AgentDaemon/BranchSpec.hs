module AgentDaemon.BranchSpec (spec) where

-- \|
-- Module      : AgentDaemon.BranchSpec
-- Description : Tests for AgentDaemon.Branch
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Branch (parseIssueBranch)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "parseIssueBranch" $ do
    it "parses feat/issue-42" $
        parseIssueBranch "feat/issue-42"
            `shouldBe` Just 42

    it "parses feat/issue-1" $
        parseIssueBranch "feat/issue-1"
            `shouldBe` Just 1

    it "parses feat/issue-999" $
        parseIssueBranch "feat/issue-999"
            `shouldBe` Just 999

    it "rejects non-matching prefix" $
        parseIssueBranch "fix/issue-42"
            `shouldBe` Nothing

    it "rejects missing number" $
        parseIssueBranch "feat/issue-"
            `shouldBe` Nothing

    it "rejects trailing text" $
        parseIssueBranch "feat/issue-42-extra"
            `shouldBe` Nothing

    it "rejects plain branch name" $
        parseIssueBranch "main"
            `shouldBe` Nothing

    it "rejects empty string" $
        parseIssueBranch ""
            `shouldBe` Nothing
