module AgentDaemon.Server
    ( startServer
    ) where

-- \|
-- Module      : AgentDaemon.Server
-- Description : Warp server with WebSocket support
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Combines the REST API and WebSocket terminal handler
-- into a single warp server using wai-websockets middleware.

import AgentDaemon.Api (apiApp)
import AgentDaemon.Terminal (paneTerminalApp, terminalApp)
import AgentDaemon.Types
    ( PaneId (..)
    , SessionId (..)
    , SessionManager
    )
import Data.ByteString qualified as BS
import Data.String (fromString)
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types.URI (urlDecode)
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Handler.WebSockets qualified as WaiWS
import Network.WebSockets qualified as WS

-- | Start the server on the given host and port.
startServer
    :: String
    -- ^ host to bind to
    -> Int
    -- ^ port number
    -> FilePath
    -- ^ base directory for worktrees
    -> FilePath
    -- ^ SPA files directory
    -> SessionManager
    -> IO ()
startServer host port baseDir staticDir mgr = do
    putStrLn $
        "tmux-ws serving SPA and API on "
            <> host
            <> ":"
            <> show port
    let settings =
            Warp.setPort port $
                Warp.setHost
                    (fromString host)
                    Warp.defaultSettings
    Warp.runSettings settings $
        WaiWS.websocketsOr
            WS.defaultConnectionOptions
            (wsApp mgr)
            (apiApp baseDir staticDir mgr)

-- | WebSocket application that routes to terminal sessions.
wsApp :: SessionManager -> WS.ServerApp
wsApp mgr pending = do
    let path =
            map
                (TE.decodeUtf8 . urlDecode True)
                ( BS.split
                    47
                    ( WS.requestPath $
                        WS.pendingRequest pending
                    )
                )
    case path of
        ["", "sessions", sid, "terminal"] ->
            terminalApp
                mgr
                (SessionId sid)
                sid
                pending
        ["", "sessions", sid, "panes", pane, "terminal"] ->
            paneTerminalApp
                mgr
                (SessionId sid)
                sid
                (PaneId pane)
                pending
        _ ->
            WS.rejectRequest
                pending
                "Invalid WebSocket path"
