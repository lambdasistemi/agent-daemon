{-# LANGUAGE ScopedTypeVariables #-}

module AgentDaemon.Terminal
    ( terminalApp
    ) where

-- \|
-- Module      : AgentDaemon.Terminal
-- Description : WebSocket to PTY terminal bridge
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Bridges WebSocket connections from xterm.js to tmux
-- sessions via pseudo-terminals. Each connection spawns
-- a PTY running @tmux attach@ and relays I\/O
-- bidirectionally.

import AgentDaemon.Types
    ( SessionId
    , SessionManager
    , updateSessionActivity
    )
import Control.Concurrent
    ( forkIO
    , killThread
    )
import Control.Exception (SomeException, catch)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.WebSockets qualified as WS
import System.Environment (getEnvironment)
import System.Posix.Pty
    ( Pty
    , readPty
    , resizePty
    , spawnWithPty
    , writePty
    )

{- | WebSocket application that attaches to a tmux
session via a pseudo-terminal.

Updates the session's last activity timestamp on
each I\/O event.
-}
terminalApp
    :: SessionManager
    -> SessionId
    -> Text
    -- ^ tmux session name
    -> WS.ServerApp
terminalApp mgr sid sessionName pending = do
    conn <- WS.acceptRequest pending
    env <- withTerm <$> getEnvironment
    (pty, _pid) <-
        spawnWithPty
            (Just env)
            True
            "tmux"
            ["attach", "-t", T.unpack sessionName]
            (80, 24)
    WS.withPingThread conn 30 (pure ()) $ do
        readerId <- forkIO $ ptyToWs mgr sid pty conn
        wsTopty mgr sid pty conn
            `catch` \(_ :: SomeException) -> pure ()
        killThread readerId

-- | Forward PTY output to WebSocket.
ptyToWs
    :: SessionManager
    -> SessionId
    -> Pty
    -> WS.Connection
    -> IO ()
ptyToWs mgr sid pty conn = go
  where
    go = do
        bytes <-
            readPty pty
                `catch` \(_ :: SomeException) ->
                    pure BS.empty
        if BS.null bytes
            then
                WS.sendClose
                    conn
                    ("PTY closed" :: Text)
            else do
                WS.sendBinaryData conn bytes
                touchActivity mgr sid
                go

-- | Forward WebSocket input to PTY.
wsTopty
    :: SessionManager
    -> SessionId
    -> Pty
    -> WS.Connection
    -> IO ()
wsTopty mgr sid pty conn = go
  where
    go = do
        msg <- WS.receiveData conn
        case parseResize msg of
            Just (cols, rows) -> do
                resizePty pty (cols, rows)
                go
            Nothing -> do
                writePty pty msg
                touchActivity mgr sid
                go

-- | Update the last activity timestamp for a session.
touchActivity
    :: SessionManager -> SessionId -> IO ()
touchActivity mgr sid = do
    now <- getCurrentTime
    updateSessionActivity mgr sid now

{- | Parse a resize message from xterm.js.

Expected format: @\\x01COLS;ROWS@ (binary prefix
byte 0x01 followed by ASCII dimensions separated
by semicolon). Returns @Nothing@ for regular
terminal input.
-}
parseResize
    :: BS.ByteString -> Maybe (Int, Int)
parseResize bs = do
    (prefix, rest) <- BS.uncons bs
    if prefix /= 1
        then Nothing
        else case BS.split 0x3b rest of
            [colsBS, rowsBS] -> do
                cols <- readDecimal colsBS
                rows <- readDecimal rowsBS
                Just (cols, rows)
            _ -> Nothing

-- | Ensure TERM is set in the environment.
withTerm :: [(String, String)] -> [(String, String)]
withTerm env =
    ("TERM", "xterm-256color")
        : filter ((/= "TERM") . fst) env

-- | Parse an ASCII decimal number from a ByteString.
readDecimal :: BS.ByteString -> Maybe Int
readDecimal b
    | BS.null b = Nothing
    | BS.all isDigit b =
        Just $ BS.foldl' step 0 b
    | otherwise = Nothing
  where
    isDigit w = w >= 0x30 && w <= 0x39
    step acc w = acc * 10 + fromIntegral (w - 0x30)
