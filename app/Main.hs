module Main
    ( main
    ) where

{- |
Module      : Main
Description : Entry point for agent-daemon
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Parses CLI options and starts the daemon server.
-}

import AgentDaemon
    ( newSessionManager
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
    { configPort :: Int
    -- ^ server port
    , configBaseDir :: FilePath
    -- ^ base directory for worktrees
    }

-- | Parse CLI options.
configParser :: Parser Config
configParser =
    Config
        <$> option
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

-- | Entry point.
main :: IO ()
main = do
    config <-
        execParser $
            info
                (configParser <**> helper)
                ( fullDesc
                    <> progDesc
                        "Manage Claude Code agent sessions"
                    <> header
                        "agent-daemon - terminal session manager"
                )
    mgr <- newSessionManager
    startServer
        (configPort config)
        (configBaseDir config)
        mgr
