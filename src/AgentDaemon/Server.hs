module AgentDaemon.Server
    ( startServer
    ) where

{- |
Module      : AgentDaemon.Server
Description : Warp server with WebSocket support
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Combines the REST API and WebSocket terminal handler
into a single warp server using wai-websockets middleware.
-}

import AgentDaemon.Api (apiApp)
import AgentDaemon.Terminal (terminalApp)
import AgentDaemon.Types (SessionManager)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Handler.WebSockets qualified as WaiWS
import Network.WebSockets qualified as WS

-- | Start the server on the given port.
startServer
    :: Int
    -- ^ port number
    -> FilePath
    -- ^ base directory for worktrees
    -> SessionManager
    -> IO ()
startServer port baseDir mgr = do
    putStrLn $
        "agent-daemon listening on port "
            <> show port
    Warp.run port $
        WaiWS.websocketsOr
            WS.defaultConnectionOptions
            wsApp
            (apiApp baseDir mgr)

-- | WebSocket application that routes to terminal sessions.
wsApp :: WS.ServerApp
wsApp pending = do
    let path =
            T.splitOn
                "/"
                ( TE.decodeUtf8 $
                    WS.requestPath
                        (WS.pendingRequest pending)
                )
    case path of
        ["", "sessions", sid, "terminal"] ->
            terminalApp sid pending
        _ ->
            WS.rejectRequest
                pending
                "Invalid WebSocket path"
