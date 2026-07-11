module AgentDaemon.Tmux
    ( PreparedTmuxClose
    , TmuxCloseFailure (..)
    , TmuxCloseResult (..)
    , prepareCurrentClose
    , preparedCloseConsequence
    , executeCurrentClose
    , createSession
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

import AgentDaemon.Close
    ( CloseConsequence (..)
    , CloseFailure (..)
    , CloseOutcome (..)
    , CloseScope (..)
    , CloseTopology (..)
    , CloseWindow (..)
    , PreparedClose
    , executeClose
    , prepareClose
    )
import AgentDaemon.Close qualified as Close
import AgentDaemon.Types
    ( PaneId (..)
    , PaneInfo (..)
    , PaneSplitDirection (..)
    , WindowInfo (..)
    )
import Control.Exception (IOException, try)
import Data.List (groupBy, nub)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as T
import System.Exit (ExitCode (..))
import System.Process
    ( callProcess
    , readProcess
    , readProcessWithExitCode
    )
import Text.Read (readMaybe)

-- | Opaque, internally targeted close prepared from live tmux state.
data PreparedTmuxClose
    = PreparedTmuxClose
        Text
        CloseScope
        PreparedClose
        Text
        Text
        (Maybe Text)
        Int
        Int
        CloseConsequence

-- | Reveal only the already-computed consequence of an opaque close.
preparedCloseConsequence :: PreparedTmuxClose -> CloseConsequence
preparedCloseConsequence (PreparedTmuxClose _ _ _ _ _ _ _ _ consequence) =
    consequence

-- | Failure at the live tmux close boundary.
data TmuxCloseFailure
    = TmuxCloseStaleCurrentContext
    | TmuxCloseUnavailable Text
    | TmuxCloseProcessFailure Text
    | TmuxCloseParseFailure Text
    deriving stock (Eq, Show)

-- | Truthful result of executing a prepared close.
data TmuxCloseResult = TmuxCloseResult
    { tmuxCloseConsequence :: CloseConsequence
    , tmuxCloseSessionEnded :: Bool
    }
    deriving stock (Eq, Show)

{- | Prepare a current-only close from one live topology snapshot.

The returned value is opaque so callers cannot forge a later target.
-}
prepareCurrentClose
    :: Text
    -> CloseScope
    -> IO (Either TmuxCloseFailure PreparedTmuxClose)
prepareCurrentClose sessionName scope = do
    topologyResult <- queryCloseTopology sessionName
    pure $ do
        topology <- topologyResult
        prepared <-
            either
                (const $ Left $ TmuxCloseParseFailure "invalid tmux topology")
                Right
                (prepareClose scope topology)
        consequence <-
            case snd $ executeClose prepared topology of
                Right CloseOutcome{outcomeConsequence} -> Right outcomeConsequence
                Left _ -> Left $ TmuxCloseParseFailure "invalid prepared topology"
        let currentWindow = topologyCurrentWindow topology
            currentPane = currentPaneFor currentWindow topology
            windowCount = NE.length $ topologyWindows topology
            paneCount = currentWindowPaneCount currentWindow topology
        Right $
            PreparedTmuxClose
                sessionName
                scope
                prepared
                (renderSessionId $ topologySession topology)
                (renderWindowId currentWindow)
                (renderPaneId <$> currentPane)
                windowCount
                paneCount
                consequence

{- | Execute an opaque prepared close.

Fresh tmux state must match the prepared model before a single atomic
tmux conditional is allowed to close the internally recorded target.
-}
executeCurrentClose
    :: Text
    -> PreparedTmuxClose
    -> IO (Either TmuxCloseFailure TmuxCloseResult)
executeCurrentClose
    sessionName
    prepared
        | sessionName /= preparedName prepared =
            pure $ Left TmuxCloseStaleCurrentContext
        | otherwise = do
            freshResult <- queryCloseTopology sessionName
            case freshResult of
                Left failure -> pure $ Left failure
                Right fresh ->
                    case validatePrepared prepared fresh of
                        Left failure -> pure $ Left failure
                        Right () -> runPreparedClose prepared

preparedName :: PreparedTmuxClose -> Text
preparedName (PreparedTmuxClose name _ _ _ _ _ _ _ _) = name

validatePrepared
    :: PreparedTmuxClose
    -> CloseTopology
    -> Either TmuxCloseFailure ()
validatePrepared (PreparedTmuxClose _ _ model _ _ _ _ _ _) fresh =
    case snd $ executeClose model fresh of
        Left StaleCurrentContext -> Left TmuxCloseStaleCurrentContext
        Left ConfirmationConsumed -> Left TmuxCloseStaleCurrentContext
        Left InvalidTopology ->
            Left $ TmuxCloseParseFailure "invalid fresh tmux topology"
        Right _ -> Right ()

runPreparedClose
    :: PreparedTmuxClose
    -> IO (Either TmuxCloseFailure TmuxCloseResult)
runPreparedClose
    ( PreparedTmuxClose
            _
            scope
            _
            sessionId
            windowId
            paneId
            windowCount
            paneCount
            consequence
        ) = do
        result <-
            try $
                readProcessWithExitCode
                    "tmux"
                    [ "if-shell"
                    , "-F"
                    , "-t"
                    , T.unpack sessionId
                    , T.unpack $
                        closeCondition
                            scope
                            sessionId
                            windowId
                            paneId
                            windowCount
                            paneCount
                    , T.unpack $ closeCommand scope windowId paneId
                    , "run-shell 'exit 71'"
                    ]
                    ""
        pure $ case result of
            Left exception ->
                Left $
                    TmuxCloseProcessFailure $
                        "tmux if-shell failed: "
                            <> T.pack (show (exception :: IOException))
            Right (ExitFailure 71, _, _) ->
                Left TmuxCloseStaleCurrentContext
            Right (ExitFailure code, _, stderr) ->
                Left $
                    TmuxCloseProcessFailure $
                        "tmux if-shell failed ("
                            <> T.pack (show code)
                            <> "): "
                            <> T.strip (T.pack stderr)
            Right (ExitSuccess, _, _) ->
                Right
                    TmuxCloseResult
                        { tmuxCloseConsequence = consequence
                        , tmuxCloseSessionEnded = consequence == SessionEnded
                        }

closeCondition
    :: CloseScope
    -> Text
    -> Text
    -> Maybe Text
    -> Int
    -> Int
    -> Text
closeCondition scope sessionId windowId paneId windowCount paneCount =
    formatAnd $
        [ formatEquals "#{session_id}" sessionId
        , formatEquals "#{window_id}" windowId
        , formatEquals "#{window_active}" "1"
        , formatEquals "#{session_windows}" $ T.pack $ show windowCount
        ]
            <> paneConditions
  where
    paneConditions =
        case (scope, paneId) of
            (CloseCurrentPane, Just stablePaneId) ->
                [ formatEquals "#{pane_id}" stablePaneId
                , formatEquals "#{pane_active}" "1"
                , formatEquals "#{window_panes}" $ T.pack $ show paneCount
                ]
            _ -> []

formatEquals :: Text -> Text -> Text
formatEquals actual expected =
    "#{==:" <> actual <> "," <> expected <> "}"

formatAnd :: [Text] -> Text
formatAnd [] = "1"
formatAnd [condition] = condition
formatAnd (condition : conditions) =
    "#{&&:" <> condition <> "," <> formatAnd conditions <> "}"

closeCommand :: CloseScope -> Text -> Maybe Text -> Text
closeCommand CloseCurrentPane _ (Just paneId) = "kill-pane -t " <> paneId
closeCommand CloseCurrentPane _ Nothing = "run-shell 'exit 71'"
closeCommand CloseCurrentWindow windowId _ = "kill-window -t " <> windowId

currentPaneFor
    :: Close.WindowId -> CloseTopology -> Maybe Close.PaneId
currentPaneFor windowId CloseTopology{topologyWindows} =
    closeWindowCurrentPane
        <$> listHead
            (filter ((== windowId) . closeWindowId) $ NE.toList topologyWindows)

currentWindowPaneCount :: Close.WindowId -> CloseTopology -> Int
currentWindowPaneCount windowId CloseTopology{topologyWindows} =
    maybe 0 (NE.length . closeWindowPanes) $
        listHead $
            filter ((== windowId) . closeWindowId) $
                NE.toList topologyWindows

renderSessionId :: Close.SessionId -> Text
renderSessionId (Close.SessionId identity) = "$" <> T.pack (show identity)

renderWindowId :: Close.WindowId -> Text
renderWindowId (Close.WindowId identity) = "@" <> T.pack (show identity)

renderPaneId :: Close.PaneId -> Text
renderPaneId (Close.PaneId identity) = "%" <> T.pack (show identity)

data ClosePaneRow = ClosePaneRow
    { rowSessionId :: Close.SessionId
    , rowWindowId :: Close.WindowId
    , rowWindowActive :: Bool
    , rowWindowPaneCount :: Int
    , rowPaneId :: Close.PaneId
    , rowPaneActive :: Bool
    }

queryCloseTopology
    :: Text -> IO (Either TmuxCloseFailure CloseTopology)
queryCloseTopology sessionName = do
    result <-
        try $
            readProcessWithExitCode
                "tmux"
                [ "list-panes"
                , "-s"
                , "-t"
                , T.unpack sessionName
                , "-F"
                , T.unpack closePaneFormat
                ]
                ""
    pure $ case result of
        Left exception ->
            Left $
                TmuxCloseProcessFailure $
                    "tmux list-panes failed: "
                        <> T.pack (show (exception :: IOException))
        Right (ExitFailure code, _, stderr)
            | unavailableMessage stderr ->
                Left $ TmuxCloseUnavailable $ T.strip $ T.pack stderr
            | otherwise ->
                Left $
                    TmuxCloseProcessFailure $
                        "tmux list-panes failed ("
                            <> T.pack (show code)
                            <> "): "
                            <> T.strip (T.pack stderr)
        Right (ExitSuccess, output, _) -> parseCloseTopology $ T.pack output

unavailableMessage :: String -> Bool
unavailableMessage stderr =
    any
        (`T.isInfixOf` message)
        [ "can't find session"
        , "no server running"
        , "no sessions"
        ]
  where
    message = T.toLower $ T.pack stderr

parseCloseTopology :: Text -> Either TmuxCloseFailure CloseTopology
parseCloseTopology output = do
    rows <- traverse parseClosePaneRow $ T.lines output
    firstRow <-
        maybe
            (Left $ TmuxCloseParseFailure "tmux returned an empty topology")
            Right
            (listHead rows)
    windows <- traverse rowsToWindow $ groupBy sameWindow rows
    nonEmptyWindows <-
        maybe
            (Left $ TmuxCloseParseFailure "tmux returned no windows")
            Right
            (NE.nonEmpty windows)
    currentWindow <-
        exactlyOne "active window" id $
            nub $
                rowWindowId <$> filter rowWindowActive rows
    pure
        CloseTopology
            { topologySession = rowSessionId firstRow
            , topologyWindows = nonEmptyWindows
            , topologyCurrentWindow = currentWindow
            }
  where
    sameWindow left right = rowWindowId left == rowWindowId right

rowsToWindow :: [ClosePaneRow] -> Either TmuxCloseFailure CloseWindow
rowsToWindow rows = do
    firstRow <-
        maybe
            (Left $ TmuxCloseParseFailure "tmux returned an empty window")
            Right
            (listHead rows)
    panes <-
        maybe
            (Left $ TmuxCloseParseFailure "tmux returned a window without panes")
            Right
            (NE.nonEmpty $ rowPaneId <$> rows)
    if rowWindowPaneCount firstRow /= length rows
        then Left $ TmuxCloseParseFailure "tmux window pane count mismatch"
        else do
            currentPane <-
                exactlyOne "active pane" rowPaneId $ filter rowPaneActive rows
            pure
                CloseWindow
                    { closeWindowId = rowWindowId firstRow
                    , closeWindowPanes = panes
                    , closeWindowCurrentPane = currentPane
                    }

parseClosePaneRow :: Text -> Either TmuxCloseFailure ClosePaneRow
parseClosePaneRow line =
    case T.splitOn "\t" line of
        [ sessionText
            , windowText
            , windowActiveText
            , paneCountText
            , paneText
            , paneActiveText
            ] ->
                ClosePaneRow
                    <$> parseStableId "$" Close.SessionId sessionText
                    <*> parseStableId "@" Close.WindowId windowText
                    <*> parseCloseBool "window_active" windowActiveText
                    <*> parseCloseInt "window_panes" paneCountText
                    <*> parseStableId "%" Close.PaneId paneText
                    <*> parseCloseBool "pane_active" paneActiveText
        _ ->
            Left $
                TmuxCloseParseFailure $
                    "unexpected tmux close metadata: " <> line

parseStableId
    :: Text
    -> (Int -> a)
    -> Text
    -> Either TmuxCloseFailure a
parseStableId prefix constructor raw =
    case T.stripPrefix prefix raw of
        Nothing ->
            Left $
                TmuxCloseParseFailure $
                    "invalid stable identity prefix: " <> raw
        Just numeric -> constructor <$> parseCloseInt "stable identity" numeric

parseCloseInt :: Text -> Text -> Either TmuxCloseFailure Int
parseCloseInt field raw =
    maybe
        (Left $ TmuxCloseParseFailure $ "invalid " <> field <> ": " <> raw)
        Right
        (readMaybe $ T.unpack raw)

parseCloseBool :: Text -> Text -> Either TmuxCloseFailure Bool
parseCloseBool field = \case
    "0" -> Right False
    "1" -> Right True
    raw -> Left $ TmuxCloseParseFailure $ "invalid " <> field <> ": " <> raw

exactlyOne
    :: Text
    -> (a -> b)
    -> [a]
    -> Either TmuxCloseFailure b
exactlyOne _ project [value] = Right $ project value
exactlyOne label _ _ = Left $ TmuxCloseParseFailure $ "expected exactly one " <> label

listHead :: [a] -> Maybe a
listHead [] = Nothing
listHead (value : _) = Just value

closePaneFormat :: Text
closePaneFormat =
    T.intercalate
        "\t"
        [ "#{session_id}"
        , "#{window_id}"
        , "#{window_active}"
        , "#{window_panes}"
        , "#{pane_id}"
        , "#{pane_active}"
        ]

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
