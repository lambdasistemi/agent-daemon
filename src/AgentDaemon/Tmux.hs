module AgentDaemon.Tmux
    ( createSession
    , killSession
    , listSessions
    , sendKeys
    ) where

-- \|
-- Module      : AgentDaemon.Tmux
-- Description : Tmux subprocess management
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Manages tmux sessions for agent processes. Each agent runs
-- inside a named tmux session that persists across terminal
-- disconnects.

import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as T
import System.Process
    ( callProcess
    , readProcess
    )

-- | Create a new detached tmux session.
createSession
    :: Text
    -- ^ session name
    -> FilePath
    -- ^ working directory
    -> IO (Either Text ())
createSession name workDir =
    runProcess
        "tmux"
        [ "new-session"
        , "-d"
        , "-s"
        , T.unpack name
        , "-c"
        , workDir
        ]

-- | Kill a tmux session by name.
killSession
    :: Text
    -- ^ session name
    -> IO (Either Text ())
killSession name =
    runProcess
        "tmux"
        ["kill-session", "-t", T.unpack name]

-- | List active tmux session names.
listSessions :: IO [Text]
listSessions = do
    out <-
        readProcess
            "tmux"
            ["list-sessions", "-F", "#{session_name}"]
            ""
    pure $ T.lines (T.pack out)

-- | Send keystrokes to a tmux session.
sendKeys
    :: Text
    -- ^ session name
    -> Text
    -- ^ keys to send
    -> IO (Either Text ())
sendKeys name keys =
    runProcess
        "tmux"
        [ "send-keys"
        , "-t"
        , T.unpack name
        , T.unpack keys
        , "Enter"
        ]

-- | Run a process, capturing failures as 'Left'.
runProcess :: FilePath -> [String] -> IO (Either Text ())
runProcess cmd args = do
    result <- try (callProcess cmd args)
    pure $ case result of
        Left e ->
            Left $
                T.pack cmd
                    <> " failed: "
                    <> T.pack (show (e :: IOException))
        Right () -> Right ()
