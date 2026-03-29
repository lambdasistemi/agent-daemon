module AgentDaemon.Structured
    ( StructuredProcess (..)
    , spawnStructured
    , readInitEvent
    , sendPrompt
    , readEvents
    , killStructured

      -- * Internal (exported for testing)
    , encodeUserMessage
    , parseInitSessionId
    , isResultEvent
    ) where

-- \|
-- Module      : AgentDaemon.Structured
-- Description : Structured (stream-json) process management
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Manages a claude CLI process running in stream-json mode.
-- The daemon writes prompts to stdin as JSON and reads
-- NDJSON events from stdout.

import Control.Concurrent.STM
    ( TVar
    , atomically
    , newTVarIO
    , readTVarIO
    , writeTVar
    )
import Control.Exception (SomeException, try)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import System.IO (BufferMode (..), Handle, hSetBuffering)
import System.Process.Typed qualified as P

-- | Handle to a running claude process in structured mode.
data StructuredProcess = StructuredProcess
    { spProcess :: P.Process Handle Handle ()
    -- ^ the typed-process handle
    , spStdin :: Handle
    -- ^ write end for JSON messages
    , spStdout :: Handle
    -- ^ read end for NDJSON events
    , spClaudeId :: TVar (Maybe Text)
    -- ^ claude session UUID from init event
    , spBusy :: TVar Bool
    -- ^ whether a prompt is in progress
    }

{- | Spawn a claude process in stream-json mode.

Optionally resumes a previous conversation via
@--resume \<id\>@.
-}
spawnStructured
    :: FilePath
    -- ^ working directory (worktree path)
    -> Maybe Text
    -- ^ claude session ID for @--resume@
    -> IO StructuredProcess
spawnStructured workDir mResumeId = do
    let baseArgs =
            [ "-p"
            , "--output-format"
            , "stream-json"
            , "--input-format"
            , "stream-json"
            , "--verbose"
            , "--dangerously-skip-permissions"
            ]
        resumeArgs = case mResumeId of
            Nothing -> []
            Just rid ->
                ["--resume", T.unpack rid]
        allArgs = baseArgs ++ resumeArgs
        cfg =
            P.setStdin P.createPipe $
                P.setStdout P.createPipe $
                    P.setStderr P.closed $
                        P.setWorkingDir workDir $
                            P.proc "claude" allArgs
    process <- P.startProcess cfg
    let stdin = P.getStdin process
        stdout = P.getStdout process
    hSetBuffering stdin LineBuffering
    hSetBuffering stdout LineBuffering
    claudeId <- newTVarIO Nothing
    busy <- newTVarIO False
    pure
        StructuredProcess
            { spProcess = process
            , spStdin = stdin
            , spStdout = stdout
            , spClaudeId = claudeId
            , spBusy = busy
            }

{- | Read the first NDJSON line (system\/init event)
and extract the @session_id@ field.
-}
readInitEvent :: StructuredProcess -> IO ()
readInitEvent sp = do
    line <- TIO.hGetLine (spStdout sp)
    case Aeson.decode (LBS.fromStrict (TE.encodeUtf8 line)) of
        Just (Aeson.Object obj) ->
            case KM.lookup "session_id" obj of
                Just (Aeson.String sid) ->
                    atomically $
                        writeTVar (spClaudeId sp) (Just sid)
                _ -> pure ()
        _ -> pure ()

{- | Send a user prompt to the structured process.

Encodes the prompt as the stream-json user message
format and writes it to stdin.
-}
sendPrompt :: StructuredProcess -> Text -> IO ()
sendPrompt sp prompt = do
    claudeId <-
        readTVarIO (spClaudeId sp)
    let msg =
            Aeson.object
                [ ("type", Aeson.String "user")
                ,
                    ( "session_id"
                    , case claudeId of
                        Just cid -> Aeson.String cid
                        Nothing -> Aeson.String ""
                    )
                ,
                    ( "message"
                    , Aeson.object
                        [ ("role", Aeson.String "user")
                        ,
                            ( "content"
                            , Aeson.String prompt
                            )
                        ]
                    )
                ,
                    ( "parent_tool_use_id"
                    , Aeson.Null
                    )
                ]
        encoded =
            TE.decodeUtf8
                (LBS.toStrict (Aeson.encode msg))
    TIO.hPutStrLn (spStdin sp) encoded

{- | Read NDJSON events from stdout.

Calls the callback for each parsed JSON value.
The callback returns 'True' to continue reading
or 'False' to stop (typically on a @result@ event).
-}
readEvents
    :: StructuredProcess
    -> (Value -> IO Bool)
    -- ^ callback; return False to stop
    -> IO ()
readEvents sp callback = go
  where
    go = do
        result <-
            try (TIO.hGetLine (spStdout sp))
        case result of
            Left (_ :: SomeException) -> pure ()
            Right line
                | T.null line -> go
                | otherwise ->
                    case Aeson.decode
                        ( LBS.fromStrict
                            (TE.encodeUtf8 line)
                        ) of
                        Just val -> do
                            cont <- callback val
                            if cont then go else pure ()
                        Nothing -> go

-- | Terminate the structured process.
killStructured :: StructuredProcess -> IO ()
killStructured sp = do
    _ <-
        try @SomeException $
            P.stopProcess (spProcess sp)
    pure ()

-- | Build the JSON user message for a prompt.
encodeUserMessage
    :: Maybe Text
    -- ^ claude session ID
    -> Text
    -- ^ prompt text
    -> Value
encodeUserMessage claudeId prompt =
    Aeson.object
        [ ("type", Aeson.String "user")
        ,
            ( "session_id"
            , case claudeId of
                Just cid -> Aeson.String cid
                Nothing -> Aeson.String ""
            )
        ,
            ( "message"
            , Aeson.object
                [ ("role", Aeson.String "user")
                ,
                    ( "content"
                    , Aeson.String prompt
                    )
                ]
            )
        ,
            ( "parent_tool_use_id"
            , Aeson.Null
            )
        ]

-- | Extract @session_id@ from a system\/init JSON event.
parseInitSessionId :: Value -> Maybe Text
parseInitSessionId (Aeson.Object obj) =
    case KM.lookup "session_id" obj of
        Just (Aeson.String sid) -> Just sid
        _ -> Nothing
parseInitSessionId _ = Nothing

-- | Check whether a JSON event is a @result@ event.
isResultEvent :: Value -> Bool
isResultEvent (Aeson.Object obj) =
    case KM.lookup "type" obj of
        Just (Aeson.String "result") -> True
        _ -> False
isResultEvent _ = False
