{-# LANGUAGE ScopedTypeVariables #-}

module AgentDaemon.TerminalSpec
    ( spec
    ) where

{- |
Module      : AgentDaemon.TerminalSpec
Description : End-to-end tests for terminal relay
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Tests the full pipeline: tmux session → PTY → WebSocket
→ client. Verifies that keystrokes sent over WebSocket
produce visible output from the tmux session.
-}

import AgentDaemon.Server (startServer)
import AgentDaemon.Types (newSessionManager)
import Control.Concurrent
    ( forkIO
    , killThread
    , threadDelay
    )
import Control.Exception
    ( SomeException
    , bracket
    , bracket_
    , catch
    )
import Data.ByteString qualified as BS
import Data.IORef
    ( IORef
    , modifyIORef'
    , newIORef
    , readIORef
    )
import Data.Text qualified as T
import Network.WebSockets qualified as WS
import System.Process (callProcess)
import Test.Hspec
    ( Spec
    , around_
    , describe
    , it
    , shouldSatisfy
    )

-- | Unique session name for tests.
testSession :: T.Text
testSession = "agent-daemon-e2e-test"

-- | Port for the test server.
testPort :: Int
testPort = 18932

-- | Set up and tear down a tmux session.
withTmuxSession :: IO () -> IO ()
withTmuxSession action = bracket_ setup cleanup action
  where
    setup =
        callProcess
            "tmux"
            [ "new-session"
            , "-d"
            , "-s"
            , T.unpack testSession
            , "-x"
            , "80"
            , "-y"
            , "24"
            ]
    cleanup =
        callProcess
            "tmux"
            [ "kill-session"
            , "-t"
            , T.unpack testSession
            ]

-- | Start the daemon server in a background thread.
withServer :: IO () -> IO ()
withServer action = do
    mgr <- newSessionManager
    bracket
        (forkIO $ startServer "*" testPort "/tmp" "static" mgr)
        killThread
        (\_ -> threadDelay 500000 >> action)

-- | Connect a WebSocket client and run an action.
withWsClient
    :: (WS.Connection -> IO a) -> IO a
withWsClient =
    WS.runClient
        "127.0.0.1"
        testPort
        ( "/sessions/"
            <> T.unpack testSession
            <> "/terminal"
        )

spec :: Spec
spec = describe "Terminal relay" $ do
    around_ (withTmuxSession . withServer) $ do
        it "relays keystrokes and receives output"
            $ do
                withWsClient $ \conn -> do
                    -- Start collecting output in background
                    ref <- newIORef BS.empty
                    readerId <- forkIO $ collector ref conn

                    -- Wait for shell to be ready
                    threadDelay 1000000

                    -- Send a command
                    WS.sendBinaryData
                        conn
                        ( "echo e2e-test-ok\n"
                            :: BS.ByteString
                        )

                    -- Wait for output
                    threadDelay 2000000

                    -- Stop collector and check
                    killThread readerId
                    output <- readIORef ref
                    output
                        `shouldSatisfy` BS.isInfixOf
                            "e2e-test-ok"

-- | Collect output in a background thread.
collector
    :: IORef BS.ByteString
    -> WS.Connection
    -> IO ()
collector ref conn = go
  where
    go = do
        chunk <-
            (WS.receiveData conn :: IO BS.ByteString)
                `catch` \(_ :: SomeException) ->
                    pure BS.empty
        if BS.null chunk
            then pure ()
            else do
                modifyIORef' ref (<> chunk)
                go
