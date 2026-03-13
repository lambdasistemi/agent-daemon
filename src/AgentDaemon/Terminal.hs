module AgentDaemon.Terminal
    ( terminalApp
    ) where

{- |
Module      : AgentDaemon.Terminal
Description : WebSocket handler for xterm.js
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Bridges WebSocket connections from xterm.js to tmux
session PTYs. Each connection attaches to a running
tmux session and relays terminal I\/O bidirectionally.
-}

import Data.Text (Text)
import Data.Text qualified as T
import Network.WebSockets qualified as WS

-- | WebSocket application that attaches to a tmux session.
--
-- Currently a stub that echoes input back. Will be replaced
-- with PTY attachment to the tmux session.
terminalApp
    :: Text
    -- ^ tmux session name
    -> WS.ServerApp
terminalApp _sessionName pending = do
    conn <- WS.acceptRequest pending
    WS.withPingThread conn 30 (pure ()) $ echoLoop conn

-- | Echo loop placeholder for terminal relay.
echoLoop :: WS.Connection -> IO ()
echoLoop conn = do
    msg <- WS.receiveData conn
    WS.sendTextData conn (msg :: T.Text)
    echoLoop conn
