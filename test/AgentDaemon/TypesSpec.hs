module AgentDaemon.TypesSpec (spec) where

-- \|
-- Module      : AgentDaemon.TypesSpec
-- Description : Tests for new dual-mode types
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Types
    ( ModeRequest (..)
    , PromptRequest (..)
    , Repo (..)
    , Session (..)
    , SessionId (..)
    , SessionMode (..)
    , SessionState (..)
    )
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = do
    describe "SessionMode" sessionModeSpec
    describe "PromptRequest" promptRequestSpec
    describe "ModeRequest" modeRequestSpec
    describe "Session JSON" sessionJsonSpec

sessionModeSpec :: Spec
sessionModeSpec = do
    it "encodes Terminal as \"terminal\"" $
        Aeson.toJSON Terminal
            `shouldBe` Aeson.String "terminal"

    it "encodes Structured as \"structured\"" $
        Aeson.toJSON Structured
            `shouldBe` Aeson.String "structured"

    it "decodes \"terminal\"" $
        Aeson.decode "\"terminal\""
            `shouldBe` Just Terminal

    it "decodes \"structured\"" $
        Aeson.decode "\"structured\""
            `shouldBe` Just Structured

    it "rejects unknown mode" $
        (Aeson.decode "\"hybrid\"" :: Maybe SessionMode)
            `shouldBe` Nothing

    it "round-trips Terminal" $
        Aeson.decode (Aeson.encode Terminal)
            `shouldBe` Just Terminal

    it "round-trips Structured" $
        Aeson.decode (Aeson.encode Structured)
            `shouldBe` Just Structured

promptRequestSpec :: Spec
promptRequestSpec = do
    it "decodes prompt field" $
        Aeson.decode "{\"prompt\":\"hello\"}"
            `shouldBe` Just (PromptRequest "hello")

    it "rejects missing prompt" $
        (Aeson.decode "{}" :: Maybe PromptRequest)
            `shouldBe` Nothing

    it "rejects wrong type" $
        (Aeson.decode "{\"prompt\":42}" :: Maybe PromptRequest)
            `shouldBe` Nothing

modeRequestSpec :: Spec
modeRequestSpec = do
    it "decodes mode field" $
        Aeson.decode "{\"mode\":\"structured\"}"
            `shouldBe` Just (ModeRequest Structured)

    it "decodes terminal mode" $
        Aeson.decode "{\"mode\":\"terminal\"}"
            `shouldBe` Just (ModeRequest Terminal)

    it "rejects invalid mode" $
        ( Aeson.decode "{\"mode\":\"invalid\"}"
            :: Maybe ModeRequest
        )
            `shouldBe` Nothing

sessionJsonSpec :: Spec
sessionJsonSpec = do
    let epoch =
            UTCTime (fromGregorian 2026 1 1) 0
        session =
            Session
                { sessionId = SessionId "test-1"
                , sessionRepo =
                    Repo
                        { repoOwner = "org"
                        , repoName = "repo"
                        }
                , sessionIssue = 1
                , sessionWorktree = "/tmp/wt"
                , sessionTmuxName = "test-1"
                , sessionState = Running
                , sessionCreatedAt = epoch
                , sessionPrompt = "test"
                , sessionLastActivity = epoch
                , sessionMode = Terminal
                , sessionClaudeId = Nothing
                }

    it "includes mode field in JSON" $ do
        let json = Aeson.toJSON session
        case json of
            Aeson.Object obj ->
                KM.lookup "mode" obj
                    `shouldBe` Just
                        (Aeson.String "terminal")
            _ -> fail "expected object"

    it "includes claudeId as null when Nothing" $ do
        let json = Aeson.toJSON session
        case json of
            Aeson.Object obj ->
                KM.lookup "claudeId" obj
                    `shouldBe` Just Aeson.Null
            _ -> fail "expected object"

    it "includes claudeId when present" $ do
        let s =
                session
                    { sessionClaudeId =
                        Just "abc-123"
                    }
            json = Aeson.toJSON s
        case json of
            Aeson.Object obj ->
                KM.lookup "claudeId" obj
                    `shouldBe` Just
                        (Aeson.String "abc-123")
            _ -> fail "expected object"

    it "shows structured mode" $ do
        let s =
                session
                    { sessionMode = Structured
                    }
            json = Aeson.toJSON s
        case json of
            Aeson.Object obj ->
                KM.lookup "mode" obj
                    `shouldBe` Just
                        (Aeson.String "structured")
            _ -> fail "expected object"
