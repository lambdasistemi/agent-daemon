module AgentDaemon.RecoverySpec (spec) where

-- \|
-- Module      : AgentDaemon.RecoverySpec
-- Description : Tests for AgentDaemon.Recovery
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Recovery (parseOwner)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "parseOwner" $ do
    it "parses SSH remote URL" $
        parseOwner "git@github.com:myorg/myrepo.git"
            `shouldBe` "myorg"

    it "parses HTTPS remote URL" $
        parseOwner
            "https://github.com/myorg/myrepo.git"
            `shouldBe` "myorg"

    it "handles SSH URL without .git suffix" $
        parseOwner "git@github.com:owner/repo"
            `shouldBe` "owner"

    it "handles HTTPS URL without .git suffix" $
        parseOwner "https://github.com/owner/repo"
            `shouldBe` "owner"

    it "returns unknown for unrecognized format" $
        parseOwner "file:///local/path"
            `shouldBe` "unknown"

    it "returns unknown for empty string" $
        parseOwner "" `shouldBe` "unknown"

    it "handles org with hyphens in SSH" $
        parseOwner
            "git@github.com:my-org-name/my-repo.git"
            `shouldBe` "my-org-name"

    it "handles org with hyphens in HTTPS" $
        parseOwner
            "https://github.com/my-org-name/my-repo.git"
            `shouldBe` "my-org-name"
