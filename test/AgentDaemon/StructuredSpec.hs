module AgentDaemon.StructuredSpec (spec) where

-- \|
-- Module      : AgentDaemon.StructuredSpec
-- Description : Tests for AgentDaemon.Structured
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Structured
    ( encodeUserMessage
    , isResultEvent
    , parseInitSessionId
    )
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    )

spec :: Spec
spec = do
    describe "encodeUserMessage" encodeSpec
    describe "parseInitSessionId" parseInitSpec
    describe "isResultEvent" isResultSpec

encodeSpec :: Spec
encodeSpec = do
    it "sets type to user" $ do
        let msg = encodeUserMessage Nothing "hello"
        fieldText "type" msg `shouldBe` Just "user"

    it "sets session_id to empty when Nothing" $ do
        let msg = encodeUserMessage Nothing "hello"
        fieldText "session_id" msg
            `shouldBe` Just ""

    it "sets session_id when provided" $ do
        let msg =
                encodeUserMessage
                    (Just "abc-123")
                    "hello"
        fieldText "session_id" msg
            `shouldBe` Just "abc-123"

    it "sets message.role to user" $ do
        let msg = encodeUserMessage Nothing "hello"
        case msg of
            Aeson.Object obj ->
                case KM.lookup "message" obj of
                    Just (Aeson.Object inner) ->
                        KM.lookup "role" inner
                            `shouldBe` Just
                                (Aeson.String "user")
                    _ -> fail "expected message object"
            _ -> fail "expected object"

    it "sets message.content to the prompt" $ do
        let msg =
                encodeUserMessage Nothing "what is 2+2"
        case msg of
            Aeson.Object obj ->
                case KM.lookup "message" obj of
                    Just (Aeson.Object inner) ->
                        KM.lookup "content" inner
                            `shouldBe` Just
                                ( Aeson.String
                                    "what is 2+2"
                                )
                    _ -> fail "expected message object"
            _ -> fail "expected object"

    it "includes parent_tool_use_id as null" $ do
        let msg = encodeUserMessage Nothing "hi"
        case msg of
            Aeson.Object obj ->
                KM.lookup "parent_tool_use_id" obj
                    `shouldBe` Just Aeson.Null
            _ -> fail "expected object"

    it "round-trips through JSON" $ do
        let msg = encodeUserMessage (Just "x") "test"
            encoded = Aeson.encode msg
            decoded = Aeson.decode encoded
        decoded `shouldBe` Just msg

parseInitSpec :: Spec
parseInitSpec = do
    it "extracts session_id from init event" $ do
        let event =
                Aeson.object
                    [ ("type", Aeson.String "system")
                    ,
                        ( "subtype"
                        , Aeson.String "init"
                        )
                    ,
                        ( "session_id"
                        , Aeson.String "uuid-here"
                        )
                    ]
        parseInitSessionId event
            `shouldBe` Just "uuid-here"

    it "returns Nothing for missing session_id" $ do
        let event =
                Aeson.object
                    [("type", Aeson.String "system")]
        parseInitSessionId event
            `shouldBe` Nothing

    it "returns Nothing for non-string session_id" $ do
        let event =
                Aeson.object
                    [("session_id", Aeson.Number 42)]
        parseInitSessionId event
            `shouldBe` Nothing

    it "returns Nothing for non-object" $
        parseInitSessionId (Aeson.String "nope")
            `shouldBe` Nothing

isResultSpec :: Spec
isResultSpec = do
    it "detects result event" $ do
        let event =
                Aeson.object
                    [("type", Aeson.String "result")]
        isResultEvent event `shouldBe` True

    it "rejects assistant event" $ do
        let event =
                Aeson.object
                    [ ("type", Aeson.String "assistant")
                    ]
        isResultEvent event `shouldBe` False

    it "rejects system event" $ do
        let event =
                Aeson.object
                    [("type", Aeson.String "system")]
        isResultEvent event `shouldBe` False

    it "rejects non-object" $
        isResultEvent (Aeson.String "result")
            `shouldBe` False

    it "rejects missing type" $ do
        let event = Aeson.object [("data", Aeson.Null)]
        isResultEvent event `shouldBe` False

-- | Helper: extract a text field from a JSON object.
fieldText :: Aeson.Key -> Aeson.Value -> Maybe Aeson.Value
fieldText key (Aeson.Object obj) = KM.lookup key obj
fieldText _ _ = Nothing
