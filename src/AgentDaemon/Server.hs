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
import AgentDaemon.Terminal (terminalApp)
import AgentDaemon.Types (SessionId (..), SessionManager)
import Data.String (fromString)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
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
    -- ^ static files directory
    -> SessionManager
    -> IO ()
startServer host port baseDir staticDir mgr = do
    putStrLn $
        "agent-daemon listening on "
            <> host
            <> ":"
            <> show port
    let settings =
            Warp.setPort port $
                Warp.setHost
                    (fromString host)
                    Warp.defaultSettings
    app <- apiApp baseDir staticDir mgr
    Warp.runSettings settings $
        WaiWS.websocketsOr
            WS.defaultConnectionOptions
            (wsApp mgr)
            app

-- | WebSocket application that routes to terminal sessions.
wsApp :: SessionManager -> WS.ServerApp
wsApp mgr pending = do
    let path =
            T.splitOn
                "/"
                ( TE.decodeUtf8 $
                    WS.requestPath
                        (WS.pendingRequest pending)
                )
    case path of
        ["", "sessions", sid, "terminal"] ->
            terminalApp
                mgr
                (SessionId sid)
                sid
                pending
        _ ->
            WS.rejectRequest
                pending
                "Invalid WebSocket path"
