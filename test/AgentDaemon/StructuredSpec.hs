module AgentDaemon.StructuredSpec (spec) where

-- \|
-- Module      : AgentDaemon.StructuredSpec
-- Description : Tests for AgentDaemon.Structured
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT

import AgentDaemon.Structured
    ( StructuredProcess (..)
    , encodeUserMessage
    , isResultEvent
    , killStructured
    , parseInitSessionId
    , readEvents
    , readInitEvent
    , sendPrompt
    , spawnStructured
    )
import Control.Concurrent.STM (readTVarIO)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text qualified as T
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)
import Test.Hspec
    ( Spec
    , describe
    , it
    , shouldBe
    , shouldSatisfy
    )

spec :: Spec
spec = do
    describe "encodeUserMessage" encodeSpec
    describe "parseInitSessionId" parseInitSpec
    describe "isResultEvent" isResultSpec
    describe "claude integration" claudeIntegrationSpec

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

-- ----------------------------------------------------------
-- Integration tests against real claude CLI
-- ----------------------------------------------------------

claudeIntegrationSpec :: Spec
claudeIntegrationSpec = do
    it "spawns and completes init handshake" $
        withTempWorktree $ \dir -> do
            sp <- spawnStructured dir Nothing
            readInitEvent sp
            -- Send a prompt to verify the process works
            sendPrompt sp "Say ok."
            events <- collectAll sp
            killStructured sp
            let types = map eventType events
            types `shouldSatisfy` elem "result"

    it "sends prompt and receives result event" $
        withTempWorktree $ \dir -> do
            sp <- spawnStructured dir Nothing
            readInitEvent sp
            sendPrompt sp "What is 2+2? Reply only the number."
            events <- collectAll sp
            killStructured sp
            let types = map eventType events
            types `shouldSatisfy` elem "result"

    it "result contains non-empty text" $
        withTempWorktree $ \dir -> do
            sp <- spawnStructured dir Nothing
            readInitEvent sp
            sendPrompt sp "Say hello in one word."
            events <- collectAll sp
            killStructured sp
            let results =
                    filter isResultEvent events
            results `shouldSatisfy` (not . null)
            case results of
                (Aeson.Object obj : _) ->
                    case KM.lookup "result" obj of
                        Just (Aeson.String t) ->
                            t `shouldSatisfy` (not . null . show)
                        _ -> fail "result field missing"
                _ -> fail "expected object"

    it "resumes conversation with --resume" $
        withTempWorktree $ \dir -> do
            -- First conversation
            sp1 <- spawnStructured dir Nothing
            readInitEvent sp1
            claudeId <- readTVarIO (spClaudeId sp1)
            sendPrompt
                sp1
                "Remember: the secret word is banana."
            _ <- collectAll sp1
            killStructured sp1
            -- Resume with session ID
            sp2 <- spawnStructured dir claudeId
            readInitEvent sp2
            sendPrompt
                sp2
                "What is the secret word? Reply only the word."
            events2 <- collectAll sp2
            killStructured sp2
            let results =
                    [ t
                    | Aeson.Object obj <- events2
                    , Just (Aeson.String t) <-
                        [KM.lookup "result" obj]
                    ]
            case results of
                (t : _) ->
                    T.unpack t
                        `shouldSatisfy` hasSubstring
                            "banana"
                [] -> fail "no result text"

-- | Create a temp directory with a git repo for worktree.
withTempWorktree :: (FilePath -> IO a) -> IO a
withTempWorktree action =
    withSystemTempDirectory "claude-test" $ \dir -> do
        callProcess "git" ["init", dir]
        callProcess
            "git"
            [ "-C"
            , dir
            , "config"
            , "user.name"
            , "Test"
            ]
        callProcess
            "git"
            [ "-C"
            , dir
            , "config"
            , "user.email"
            , "test@test.com"
            ]
        callProcess
            "git"
            [ "-C"
            , dir
            , "commit"
            , "--allow-empty"
            , "-m"
            , "init"
            ]
        action dir

-- | Collect all events until result or EOF.
collectAll :: StructuredProcess -> IO [Aeson.Value]
collectAll sp = do
    ref <- newIORef []
    readEvents sp $ \val -> do
        modifyIORef' ref (val :)
        pure (not (isResultEvent val))
    reverse <$> readIORef ref

-- | Extract the "type" field from a JSON value.
eventType :: Aeson.Value -> String
eventType (Aeson.Object obj) =
    case KM.lookup "type" obj of
        Just (Aeson.String t) -> T.unpack t
        _ -> "unknown"
eventType _ = "unknown"

-- | Check if a text contains a substring.
hasSubstring :: String -> String -> Bool
hasSubstring needle haystack =
    needle `elem` words (map toLower haystack)
  where
    toLower c
        | c >= 'A' && c <= 'Z' =
            toEnum (fromEnum c + 32)
        | otherwise = c

-- | Helper: extract a text field from a JSON object.
fieldText :: Aeson.Key -> Aeson.Value -> Maybe Aeson.Value
fieldText key (Aeson.Object obj) = KM.lookup key obj
fieldText _ _ = Nothing
