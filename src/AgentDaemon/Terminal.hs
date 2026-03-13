{-# LANGUAGE ScopedTypeVariables #-}

module AgentDaemon.Terminal
    ( terminalApp
    ) where

{- |
Module      : AgentDaemon.Terminal
Description : WebSocket to PTY terminal bridge
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Bridges WebSocket connections from xterm.js to tmux
sessions via pseudo-terminals. Each connection spawns
a PTY running @tmux attach@ and relays I\/O
bidirectionally.
-}

import Control.Concurrent
    ( forkIO
    , killThread
    )
import Control.Exception (SomeException, catch)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Network.WebSockets qualified as WS
import System.Posix.Pty
    ( Pty
    , readPty
    , resizePty
    , spawnWithPty
    , writePty
    )

-- | WebSocket application that attaches to a tmux
-- session via a pseudo-terminal.
terminalApp
    :: Text
    -- ^ tmux session name
    -> WS.ServerApp
terminalApp sessionName pending = do
    conn <- WS.acceptRequest pending
    (pty, _pid) <-
        spawnWithPty
            Nothing
            True
            "tmux"
            ["attach", "-t", T.unpack sessionName]
            (80, 24)
    WS.withPingThread conn 30 (pure ()) $ do
        readerId <- forkIO $ ptyToWs pty conn
        wsTopty pty conn
            `catch` \(_ :: SomeException) -> pure ()
        killThread readerId

-- | Forward PTY output to WebSocket.
ptyToWs :: Pty -> WS.Connection -> IO ()
ptyToWs pty conn = go
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
                go

-- | Forward WebSocket input to PTY.
wsTopty :: Pty -> WS.Connection -> IO ()
wsTopty pty conn = go
  where
    go = do
        msg <- WS.receiveData conn
        case parseResize msg of
            Just (cols, rows) -> do
                resizePty pty (cols, rows)
                go
            Nothing -> do
                writePty pty msg
                go

-- | Parse a resize message from xterm.js.
--
-- Expected format: @\\x01COLS;ROWS@ (binary prefix
-- byte 0x01 followed by ASCII dimensions separated
-- by semicolon). Returns @Nothing@ for regular
-- terminal input.
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
