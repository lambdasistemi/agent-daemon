module AgentDaemon.Api
    ( apiApp
    ) where

-- \|
-- Module      : AgentDaemon.Api
-- Description : Servant server for the REST API
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Servant-based WAI application providing REST endpoints
-- for listing, stopping, and controlling tmux sessions.

import AgentDaemon.Api.Types (agentApi)
import AgentDaemon.Branch qualified as Branch
import AgentDaemon.Recovery qualified as Recovery
import AgentDaemon.Tmux qualified as Tmux
import AgentDaemon.Types
    ( BranchInfo (..)
    , LayoutRequest (..)
    , PaneId (..)
    , PaneInfo (..)
    , PaneSplitRequest (..)
    , Repo (..)
    , ScrollRequest (..)
    , Session (..)
    , SessionId (..)
    , SessionManager (..)
    , WindowInfo (..)
    , WindowSelectRequest (..)
    , WorktreeInfo (..)
    )
import Control.Concurrent.STM
    ( atomically
    , readTVar
    , readTVarIO
    , writeTVar
    )
import Control.Monad.IO.Class (liftIO)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.List (intercalate, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Tagged (Tagged (..))
import Data.Text (Text)
import Data.Text qualified as T
import Network.HTTP.Types
    ( ResponseHeaders
    , methodGet
    , methodHead
    , methodOptions
    , status200
    , status404
    )
import Network.Wai
    ( Application
    , Middleware
    , mapResponseHeaders
    , pathInfo
    , requestMethod
    , responseFile
    , responseLBS
    )
import Servant
    ( Handler
    , ServerError (..)
    , err400
    , err404
    , err500
    , serve
    , throwError
    , (:<|>) (..)
    )
import System.Directory
    ( doesDirectoryExist
    , doesFileExist
    , listDirectory
    )

-- | WAI application for the REST API and static files.
apiApp
    :: FilePath
    -- ^ base directory for worktrees
    -> FilePath
    -- ^ static files directory
    -> SessionManager
    -> Application
apiApp baseDir staticDir mgr =
    cors $
        serve
            agentApi
            ( handleList baseDir mgr
                :<|> handleStop mgr
                :<|> handleListPanes mgr
                :<|> handleSplitPane mgr
                :<|> handleSelectLayout mgr
                :<|> handleListWindows mgr
                :<|> handleNewWindow mgr
                :<|> handleSelectWindow mgr
                :<|> handleScrollSession mgr
                :<|> handleLiveSession mgr
                :<|> handleListWorktrees baseDir
                :<|> handleListBranches baseDir
                :<|> handleDeleteBranch baseDir
                :<|> staticFallback staticDir
            )

-- | Static file fallback — serves real assets first, then index.html for SPA.
staticFallback :: FilePath -> Tagged Handler Application
staticFallback staticDir = Tagged $ \req respond ->
    if requestMethod req `elem` [methodGet, methodHead]
        then do
            let requested = staticRequestPath staticDir (pathInfo req)
            exists <- doesFileExist requested
            let filePath =
                    if exists
                        then requested
                        else staticDir <> "/index.html"
            respond $
                responseFile
                    status200
                    (("Content-Type", contentType filePath) : noCacheHeaders)
                    filePath
                    Nothing
        else
            respond $
                responseLBS
                    status404
                    [("Content-Type", "application/json")]
                    "{\"error\":\"not found\"}"

staticRequestPath :: FilePath -> [Text] -> FilePath
staticRequestPath staticDir segments =
    case safeSegments of
        [] -> staticDir <> "/index.html"
        xs -> staticDir <> "/" <> intercalate "/" xs
  where
    safeSegments =
        [ T.unpack segment
        | segment <- segments
        , segment /= "."
        , segment /= ".."
        , not (T.any (== '/') segment)
        , not (T.any (== '\\') segment)
        ]

contentType :: FilePath -> ByteString
contentType path
    | ".html" `isSuffixOf` path = "text/html"
    | ".js" `isSuffixOf` path = "application/javascript"
    | ".css" `isSuffixOf` path = "text/css"
    | ".woff2" `isSuffixOf` path = "font/woff2"
    | otherwise = "application/octet-stream"

-- | List all active sessions.
handleList
    :: FilePath
    -> SessionManager
    -> Handler [Session]
handleList baseDir mgr = do
    liftIO $ Recovery.recoverSessions baseDir mgr
    m <- liftIO $ readTVarIO (sessions mgr)
    pure $ Map.elems m

-- | Stop a session and clean up resources.
handleStop
    :: SessionManager
    -> Text
    -> Maybe Text
    -> Handler Aeson.Value
handleStop mgr sidText confirmText = do
    let sid = SessionId sidText
    m <- liftIO $ readTVarIO (sessions mgr)
    case Map.lookup sid m of
        Nothing ->
            throwError
                err404
                    { errBody =
                        Aeson.encode $
                            errorJson
                                ( "Session "
                                    <> unSessionId sid
                                    <> " not found"
                                )
                    , errHeaders = jsonHeaders
                    }
        Just session -> do
            case confirmText of
                Just confirm
                    | confirm == sidText -> pure ()
                _ ->
                    throwError
                        err400
                            { errBody =
                                Aeson.encode $
                                    errorJson
                                        ( "Deletion requires confirm="
                                            <> sidText
                                        )
                            , errHeaders = jsonHeaders
                            }
            _ <-
                liftIO $
                    Tmux.killSession
                        (sessionTmuxName session)
            liftIO $
                atomically $ do
                    current <- readTVar (sessions mgr)
                    writeTVar (sessions mgr) $
                        Map.delete sid current
            pure $
                Aeson.object
                    [
                        ( "status"
                        , Aeson.String "stopped"
                        )
                    ]

-- | List tmux panes for a session.
handleListPanes
    :: SessionManager
    -> Text
    -> Handler [PaneInfo]
handleListPanes mgr sidText =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.listPanes
                    (sessionTmuxName session)
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right panes -> pure panes

-- | Split a pane in a session.
handleSplitPane
    :: SessionManager
    -> Text
    -> PaneSplitRequest
    -> Handler PaneInfo
handleSplitPane
    mgr
    sidText
    PaneSplitRequest
        { splitTarget
        , splitDirection
        , splitCwd
        , splitCommand
        } =
        withSession mgr sidText $ \session -> do
            ensurePaneTarget session splitTarget
            result <-
                liftIO $
                    Tmux.splitPane
                        (sessionTmuxName session)
                        splitTarget
                        splitDirection
                        splitCwd
                        splitCommand
            case result of
                Left reason ->
                    throwError
                        err500
                            { errBody =
                                Aeson.encode $
                                    errorJson reason
                            , errHeaders = jsonHeaders
                            }
                Right pane -> pure pane

-- | Select a tmux layout for a session.
handleSelectLayout
    :: SessionManager
    -> Text
    -> LayoutRequest
    -> Handler Aeson.Value
handleSelectLayout mgr sidText LayoutRequest{layout} =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.selectLayout
                    (sessionTmuxName session)
                    layout
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right () ->
                pure $
                    Aeson.object
                        [
                            ( "status"
                            , Aeson.String "layout-selected"
                            )
                        ]

-- | List tmux windows for a session.
handleListWindows
    :: SessionManager
    -> Text
    -> Handler [WindowInfo]
handleListWindows mgr sidText =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.listWindows
                    (sessionTmuxName session)
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right windows -> pure windows

-- | Create and select a new tmux window for a session.
handleNewWindow
    :: SessionManager
    -> Text
    -> Handler WindowInfo
handleNewWindow mgr sidText =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.newWindow
                    (sessionTmuxName session)
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right window -> pure window

-- | Select a tmux window for a session.
handleSelectWindow
    :: SessionManager
    -> Text
    -> WindowSelectRequest
    -> Handler Aeson.Value
handleSelectWindow mgr sidText WindowSelectRequest{selectIndex} =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.selectWindow
                    (sessionTmuxName session)
                    selectIndex
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right () ->
                pure $
                    Aeson.object
                        [
                            ( "status"
                            , Aeson.String "window-selected"
                            )
                        ]

-- | Scroll the active tmux pane for a browser touch gesture.
handleScrollSession
    :: SessionManager
    -> Text
    -> ScrollRequest
    -> Handler Aeson.Value
handleScrollSession mgr sidText ScrollRequest{scrollLines} =
    withSession mgr sidText $ \session -> do
        let amount = clampScrollAmount scrollLines
        result <-
            liftIO $
                Tmux.scrollPane
                    (sessionTmuxName session)
                    amount
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right () ->
                pure $
                    Aeson.object
                        [
                            ( "status"
                            , Aeson.String "scrolled"
                            )
                        , ("lines", Aeson.toJSON amount)
                        ]

-- | Return the active tmux pane to live output.
handleLiveSession
    :: SessionManager
    -> Text
    -> Handler Aeson.Value
handleLiveSession mgr sidText =
    withSession mgr sidText $ \session -> do
        result <-
            liftIO $
                Tmux.cancelPaneMode
                    (sessionTmuxName session)
        case result of
            Left reason ->
                throwError
                    err500
                        { errBody =
                            Aeson.encode $
                                errorJson reason
                        , errHeaders = jsonHeaders
                        }
            Right () ->
                pure $
                    Aeson.object
                        [
                            ( "status"
                            , Aeson.String "live"
                            )
                        ]

-- | List all worktree directories on disk.
handleListWorktrees
    :: FilePath
    -> Handler [WorktreeInfo]
handleListWorktrees baseDir = do
    entries <- liftIO $ listDirectory baseDir
    liftIO $
        catMaybes
            <$> mapM (toWorktreeInfo baseDir) entries

{- | Try to build a 'WorktreeInfo' from a directory name.

Matches the pattern @repoName-issue-N@ and reads the
repo owner from the git remote.
-}
toWorktreeInfo
    :: FilePath -> FilePath -> IO (Maybe WorktreeInfo)
toWorktreeInfo baseDir name =
    case parseWorktreeName (T.pack name) of
        Nothing -> pure Nothing
        Just (repoName, issue) -> do
            let path = baseDir <> "/" <> name
            isDir <- doesDirectoryExist path
            if not isDir
                then pure Nothing
                else do
                    owner <- Recovery.getRepoOwner path
                    pure $
                        Just
                            WorktreeInfo
                                { worktreeRepo =
                                    Repo
                                        { repoOwner = owner
                                        , repoName = repoName
                                        }
                                , worktreeIssue = issue
                                , worktreePath = path
                                }

{- | Parse a worktree directory name into repo name
and issue number.

@"agent-daemon-issue-32"@ becomes
@Just ("agent-daemon", 32)@.
-}
parseWorktreeName :: Text -> Maybe (Text, Int)
parseWorktreeName name =
    case T.breakOn "-issue-" name of
        (_, "") -> Nothing
        (repoName, rest) -> do
            let numText = T.drop 7 rest -- drop "-issue-"
            issue <-
                case reads (T.unpack numText) of
                    [(n, "")] -> Just n
                    _ -> Nothing
            if T.null repoName
                then Nothing
                else Just (repoName, issue)

-- | List all local issue branches.
handleListBranches
    :: FilePath
    -> Handler [BranchInfo]
handleListBranches baseDir =
    liftIO $ Branch.listBranches baseDir

-- | Delete a branch locally and on the remote.
handleDeleteBranch
    :: FilePath
    -> Text
    -> Text
    -> Handler Aeson.Value
handleDeleteBranch baseDir repo branch = do
    result <-
        liftIO $
            Branch.deleteBranch baseDir repo branch False
    case result of
        Left err ->
            throwError
                err400
                    { errBody =
                        Aeson.encode $ errorJson err
                    , errHeaders = jsonHeaders
                    }
        Right () ->
            pure $
                Aeson.object
                    [
                        ( "status"
                        , Aeson.String "deleted"
                        )
                    ]

-- | Look up a session or return a JSON 404.
withSession
    :: SessionManager
    -> Text
    -> (Session -> Handler a)
    -> Handler a
withSession mgr sidText action = do
    let sid = SessionId sidText
    m <- liftIO $ readTVarIO (sessions mgr)
    case Map.lookup sid m of
        Nothing ->
            throwError
                err404
                    { errBody =
                        Aeson.encode $
                            errorJson
                                ( "Session "
                                    <> unSessionId sid
                                    <> " not found"
                                )
                    , errHeaders = jsonHeaders
                    }
        Just session -> action session

-- | Ensure a target pane belongs to the daemon session.
ensurePaneTarget
    :: Session
    -> Maybe PaneId
    -> Handler ()
ensurePaneTarget _ Nothing = pure ()
ensurePaneTarget session (Just target) = do
    result <-
        liftIO $
            Tmux.listPanes
                (sessionTmuxName session)
    case result of
        Left reason ->
            throwError
                err500
                    { errBody =
                        Aeson.encode $
                            errorJson reason
                    , errHeaders = jsonHeaders
                    }
        Right panes
            | any ((== target) . paneId) panes -> pure ()
            | otherwise ->
                throwError
                    err404
                        { errBody =
                            Aeson.encode $
                                errorJson
                                    ( "Pane "
                                        <> unPaneId target
                                        <> " not found in session "
                                        <> sessionTmuxName session
                                    )
                        , errHeaders = jsonHeaders
                        }

-- | Build a JSON error object.
errorJson :: Text -> Aeson.Value
errorJson msg =
    Aeson.object [("error", Aeson.String msg)]

-- | Standard JSON content-type headers.
jsonHeaders :: ResponseHeaders
jsonHeaders = [("Content-Type", "application/json")]

-- | Clamp touch scroll batches to a small, bounded command.
clampScrollAmount :: Int -> Int
clampScrollAmount n = max (-80) (min 80 n)

-- | Static UI assets should always revalidate on touch devices.
noCacheHeaders :: ResponseHeaders
noCacheHeaders =
    [ ("Cache-Control", "no-store, no-cache, must-revalidate")
    , ("Pragma", "no-cache")
    , ("Expires", "0")
    ]

{- | CORS middleware — adds permissive CORS headers to
all responses and answers browser preflight requests.
-}
cors :: Middleware
cors app req respond =
    if requestMethod req == methodOptions
        then respond $ responseLBS status200 corsHeaders ""
        else app req $ \response ->
            respond $
                mapResponseHeaders (++ corsHeaders) response

-- | CORS headers allowing any origin.
corsHeaders :: ResponseHeaders
corsHeaders =
    [ ("Access-Control-Allow-Origin", "*")
    ,
        ( "Access-Control-Allow-Methods"
        , "GET, POST, DELETE, OPTIONS"
        )
    ,
        ( "Access-Control-Allow-Headers"
        , "Content-Type"
        )
    ,
        ( "Access-Control-Allow-Private-Network"
        , "true"
        )
    ]
