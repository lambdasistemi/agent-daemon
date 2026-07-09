module AgentDaemon.Tmux
    ( createSession
    , killSession
    , listSessions
    , listPanes
    , listWindows
    , newWindow
    , splitPane
    , selectLayout
    , selectWindow
    , selectPane
    , sendKeys
    , cancelPaneMode
    , scrollPane
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

import AgentDaemon.Types
    ( PaneId (..)
    , PaneInfo (..)
    , PaneSplitDirection (..)
    , WindowInfo (..)
    )
import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as T
import System.Exit (ExitCode (..))
import System.Process
    ( callProcess
    , readProcess
    , readProcessWithExitCode
    )
import Text.Read (readMaybe)

{- | Create a new detached tmux session.

If a session with the same name already exists,
succeeds without doing anything.
-}
createSession
    :: Text
    -- ^ session name
    -> FilePath
    -- ^ working directory
    -> IO (Either Text ())
createSession name workDir = do
    exists <- hasSession name
    if exists
        then pure (Right ())
        else
            runProcess
                "tmux"
                [ "new-session"
                , "-d"
                , "-s"
                , T.unpack name
                , "-c"
                , workDir
                , "-n"
                , "agent"
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

-- | List panes in a tmux session.
listPanes
    :: Text
    -- ^ session name
    -> IO (Either Text [PaneInfo])
listPanes name = do
    result <-
        runReadProcess
            "tmux"
            [ "list-panes"
            , "-s"
            , "-t"
            , T.unpack name
            , "-F"
            , T.unpack paneFormat
            ]
    pure $ do
        out <- result
        traverse parsePaneLine (T.lines out)

-- | List windows in a tmux session.
listWindows
    :: Text
    -- ^ session name
    -> IO (Either Text [WindowInfo])
listWindows name = do
    result <-
        runReadProcess
            "tmux"
            [ "list-windows"
            , "-t"
            , T.unpack name
            , "-F"
            , T.unpack windowFormat
            ]
    pure $ do
        out <- result
        traverse parseWindowLine (T.lines out)

-- | Create and select a new tmux window in a session.
newWindow
    :: Text
    -- ^ session name
    -> IO (Either Text WindowInfo)
newWindow sessionName = do
    result <-
        runReadProcess
            "tmux"
            [ "new-window"
            , "-P"
            , "-F"
            , T.unpack windowFormat
            , "-t"
            , T.unpack sessionName
            ]
    pure $ do
        out <- result
        case T.lines out of
            [line] -> parseWindowLine line
            [] -> Left "tmux new-window returned no window metadata"
            _ -> Left "tmux new-window returned multiple metadata lines"

-- | Split a tmux pane and return metadata for the new pane.
splitPane
    :: Text
    -- ^ session name
    -> Maybe PaneId
    -- ^ target pane; defaults to session active pane
    -> PaneSplitDirection
    -- ^ split direction
    -> Maybe FilePath
    -- ^ optional working directory
    -> Maybe Text
    -- ^ optional command
    -> IO (Either Text PaneInfo)
splitPane sessionName target direction cwd command = do
    result <-
        runReadProcess
            "tmux"
            ( baseArgs
                <> cwdArgs
                <> commandArgs
            )
    pure $ do
        out <- result
        case T.lines out of
            [line] -> parsePaneLine line
            [] -> Left "tmux split-window returned no pane metadata"
            _ -> Left "tmux split-window returned multiple metadata lines"
  where
    baseArgs =
        [ "split-window"
        , directionFlag
        , "-P"
        , "-F"
        , T.unpack paneFormat
        , "-t"
        , T.unpack targetText
        ]
    targetText =
        maybe sessionName unPaneId target
    directionFlag =
        case direction of
            SplitHorizontal -> "-h"
            SplitVertical -> "-v"
    cwdArgs =
        maybe [] (\dir -> ["-c", dir]) cwd
    commandArgs =
        maybe [] (\cmd -> [T.unpack cmd]) command

-- | Apply a tmux layout to the session's active window.
selectLayout
    :: Text
    -- ^ session name
    -> Text
    -- ^ layout name
    -> IO (Either Text ())
selectLayout sessionName layout =
    runProcess
        "tmux"
        [ "select-layout"
        , "-t"
        , T.unpack sessionName
        , T.unpack layout
        ]

-- | Select a tmux window by index.
selectWindow
    :: Text
    -- ^ session name
    -> Int
    -- ^ window index
    -> IO (Either Text ())
selectWindow sessionName index =
    runProcess
        "tmux"
        [ "select-window"
        , "-t"
        , T.unpack sessionName <> ":" <> show index
        ]

-- | Select a tmux pane.
selectPane
    :: PaneId
    -- ^ pane id
    -> IO (Either Text ())
selectPane paneId =
    do
        let target = T.unpack (unPaneId paneId)
        windowResult <-
            runProcess
                "tmux"
                ["select-window", "-t", target]
        case windowResult of
            Left err -> pure (Left err)
            Right () ->
                runProcess
                    "tmux"
                    [ "select-pane"
                    , "-t"
                    , target
                    ]

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

-- | Scroll the active pane's tmux history.
scrollPane
    :: Text
    -- ^ session name
    -> Int
    -- ^ positive scrolls back, negative scrolls toward live output
    -> IO (Either Text ())
scrollPane _ 0 = pure (Right ())
scrollPane name amount
    | amount > 0 = do
        modeResult <-
            runProcess
                "tmux"
                [ "copy-mode"
                , "-t"
                , T.unpack name
                ]
        case modeResult of
            Left err -> pure (Left err)
            Right () -> do
                result <- scrollCopyMode name amount "scroll-up"
                cancelCopyModeAtBottom name
                pure result
    | otherwise = do
        _ <- scrollCopyMode name (abs amount) "scroll-down"
        cancelCopyModeAtBottom name
        pure (Right ())

-- | Cancel tmux copy-mode for the active pane.
cancelPaneMode
    :: Text
    -- ^ session name
    -> IO (Either Text ())
cancelPaneMode name = do
    result <-
        runProcessQuiet
            "tmux"
            [ "send-keys"
            , "-t"
            , T.unpack name
            , "-X"
            , "cancel"
            ]
    pure $ case result of
        Left err
            | "not in a mode" `T.isInfixOf` err -> Right ()
        other -> other

-- | Check if a tmux session exists.
hasSession :: Text -> IO Bool
hasSession name = do
    result <-
        runProcess
            "tmux"
            ["has-session", "-t", T.unpack name]
    pure $ case result of
        Right () -> True
        Left _ -> False

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

-- | Run a process and capture stdout, capturing failures as 'Left'.
runReadProcess :: FilePath -> [String] -> IO (Either Text Text)
runReadProcess cmd args = do
    result <- try (readProcess cmd args "")
    pure $ case result of
        Left e ->
            Left $
                T.pack cmd
                    <> " failed: "
                    <> T.pack (show (e :: IOException))
        Right out -> Right (T.pack out)

-- | Run a process without inheriting stderr, capturing failures as 'Left'.
runProcessQuiet :: FilePath -> [String] -> IO (Either Text ())
runProcessQuiet cmd args = do
    result <- try (readProcessWithExitCode cmd args "")
    pure $ case result of
        Left e ->
            Left $
                T.pack cmd
                    <> " failed: "
                    <> T.pack (show (e :: IOException))
        Right (ExitSuccess, _, _) -> Right ()
        Right (ExitFailure code, _, err) ->
            Left $
                T.pack cmd
                    <> " failed ("
                    <> T.pack (show code)
                    <> "): "
                    <> T.strip (T.pack err)

-- | Send a copy-mode scroll command.
scrollCopyMode :: Text -> Int -> String -> IO (Either Text ())
scrollCopyMode name amount direction =
    runProcess
        "tmux"
        [ "send-keys"
        , "-t"
        , T.unpack name
        , "-X"
        , "-N"
        , show amount
        , direction
        ]

-- | Leave copy-mode once the scrollback view is back at live output.
cancelCopyModeAtBottom :: Text -> IO ()
cancelCopyModeAtBottom name = do
    position <- scrollPosition name
    case position of
        Just n | n <= 0 -> do
            _ <- cancelPaneMode name
            pure ()
        _ -> pure ()

-- | Read tmux copy-mode scroll position for the active pane.
scrollPosition :: Text -> IO (Maybe Int)
scrollPosition name = do
    result <-
        runReadProcess
            "tmux"
            [ "display-message"
            , "-p"
            , "-t"
            , T.unpack name
            , "#{scroll_position}"
            ]
    pure $ case result of
        Left _ -> Nothing
        Right value -> readMaybe $ T.unpack $ T.strip value

-- | Format used for machine-readable tmux pane metadata.
paneFormat :: Text
paneFormat =
    T.intercalate
        "\t"
        [ "#{pane_id}"
        , "#{pane_index}"
        , "#{pane_active}"
        , "#{pane_current_command}"
        , "#{pane_current_path}"
        , "#{pane_width}"
        , "#{pane_height}"
        , "#{window_index}"
        , "#{window_name}"
        , "#{window_active}"
        ]

-- | Format used for machine-readable tmux window metadata.
windowFormat :: Text
windowFormat =
    T.intercalate
        "\t"
        [ "#{window_index}"
        , "#{window_name}"
        , "#{window_active}"
        ]

-- | Parse one line of 'paneFormat' output.
parsePaneLine :: Text -> Either Text PaneInfo
parsePaneLine line =
    case T.splitOn "\t" line of
        [ pid
            , indexText
            , activeText
            , command
            , path
            , widthText
            , heightText
            , windowIndexText
            , windowName
            , windowActiveText
            ] -> do
                paneIndex <- parseInt "pane_index" indexText
                paneWidth <- parseInt "pane_width" widthText
                paneHeight <- parseInt "pane_height" heightText
                paneWindowIndex <-
                    parseInt "window_index" windowIndexText
                paneActive <- parseBool "pane_active" activeText
                paneWindowActive <-
                    parseBool "window_active" windowActiveText
                pure
                    PaneInfo
                        { paneId = PaneId pid
                        , paneIndex
                        , paneActive
                        , paneCurrentCommand = command
                        , paneCurrentPath = T.unpack path
                        , paneWidth
                        , paneHeight
                        , paneWindowIndex
                        , paneWindowName = windowName
                        , paneWindowActive
                        }
        _ -> Left $ "unexpected tmux pane metadata: " <> line

-- | Parse one line of 'windowFormat' output.
parseWindowLine :: Text -> Either Text WindowInfo
parseWindowLine line =
    case T.splitOn "\t" line of
        [indexText, name, activeText] -> do
            windowIndex <- parseInt "window_index" indexText
            windowActive <- parseBool "window_active" activeText
            pure
                WindowInfo
                    { windowIndex
                    , windowName = name
                    , windowActive
                    }
        _ -> Left $ "unexpected tmux window metadata: " <> line

-- | Parse an integer field from tmux metadata.
parseInt :: Text -> Text -> Either Text Int
parseInt fieldName raw =
    case readMaybe (T.unpack raw) of
        Just value -> Right value
        Nothing ->
            Left $
                "invalid "
                    <> fieldName
                    <> ": "
                    <> raw

-- | Parse a boolean field from tmux metadata.
parseBool :: Text -> Text -> Either Text Bool
parseBool fieldName = \case
    "0" -> Right False
    "1" -> Right True
    raw ->
        Left $
            "invalid "
                <> fieldName
                <> ": "
                <> raw
