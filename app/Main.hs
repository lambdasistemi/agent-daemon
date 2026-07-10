module Main
    ( main
    ) where

-- \|
-- Module      : Main
-- Description : Entry point for tmux-ws
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Parses CLI options and starts the daemon server.

import AgentDaemon
    ( newSessionManager
    , recoverSessions
    , startServer
    )
import Options.Applicative
    ( Parser
    , auto
    , execParser
    , fullDesc
    , header
    , help
    , helper
    , info
    , long
    , option
    , progDesc
    , showDefault
    , strOption
    , value
    , (<**>)
    )

-- | CLI configuration.
data Config = Config
    { configHost :: String
    -- ^ host to bind to
    , configPort :: Int
    -- ^ server port
    , configBaseDir :: FilePath
    -- ^ base directory for worktrees
    , configStaticDir :: FilePath
    -- ^ SPA files directory
    }

-- | Parse CLI options.
configParser :: Parser Config
configParser =
    Config
        <$> strOption
            ( long "host"
                <> help
                    "Host to bind to"
                <> showDefault
                <> value "*"
            )
        <*> option
            auto
            ( long "port"
                <> help "Port to listen on"
                <> showDefault
                <> value 8080
            )
        <*> strOption
            ( long "base-dir"
                <> help
                    "Base directory for git worktrees"
                <> showDefault
                <> value "/code"
            )
        <*> strOption
            ( long "static-dir"
                <> help
                    "Directory for the SPA files served by the daemon"
                <> showDefault
                <> value "static"
            )

-- | Entry point.
main :: IO ()
main = do
    config <-
        execParser $
            info
                (configParser <**> helper)
                ( fullDesc
                    <> progDesc
                        "Serve the tmux-ws SPA and manage local tmux sessions"
                    <> header
                        "tmux-ws - browser SPA plus tmux session daemon"
                )
    mgr <- newSessionManager
    recoverSessions (configBaseDir config) mgr
    startServer
        (configHost config)
        (configPort config)
        (configBaseDir config)
        (configStaticDir config)
        mgr
