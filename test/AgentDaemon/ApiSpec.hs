{-# LANGUAGE LambdaCase #-}

module AgentDaemon.ApiSpec
    ( spec
    ) where

-- \|
-- Module      : AgentDaemon.ApiSpec
-- Description : API-level tests for servant endpoints
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Tests the REST API endpoints via servant-client against
-- a live warp test server. Validates request/response shapes
-- and error handling.

import AgentDaemon.Api
    ( CloseActionFailure (..)
    , CloseBoundary (..)
    , apiApp
    , apiAppWithCloseBoundary
    )
import AgentDaemon.Types
    ( Session (..)
    , SessionId (..)
    , SessionManager
    , SessionState (..)
    , newSessionManager
    , sessions
    )
import Control.Concurrent
    ( MVar
    , forkIO
    , newEmptyMVar
    , putMVar
    , takeMVar
    )
import Control.Concurrent.STM
    ( atomically
    , readTVarIO
    , writeTVar
    )
import Control.Exception
    ( bracket_
    )
import Data.Aeson
    ( Value (..)
    , decode
    , object
    , (.=)
    )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Char (isAsciiLower, isDigit)
import Data.IORef
    ( IORef
    , atomicModifyIORef'
    , atomicWriteIORef
    , newIORef
    , readIORef
    )
import Data.Map.Strict qualified as Map
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Unique (hashUnique, newUnique)
import Network.HTTP.Client
    ( RequestBody (RequestBodyLBS)
    , defaultManagerSettings
    , httpLbs
    , method
    , newManager
    , parseRequest
    , requestBody
    , requestHeaders
    , responseHeaders
    , responseStatus
    )
import Network.HTTP.Types
    ( status200
    , status400
    , status404
    , status409
    , status500
    )
import Network.Wai.Handler.Warp qualified as Warp
import Servant.API
    ( Capture
    , Delete
    , Get
    , JSON
    , Post
    , QueryParam
    , ReqBody
    , (:<|>) (..)
    , (:>)
    )
import Servant.Client
    ( BaseUrl (..)
    , ClientError (..)
    , ClientM
    , Scheme (..)
    , client
    , mkClientEnv
    , responseBody
    , responseStatusCode
    , runClientM
    )
import System.Directory
    ( createDirectoryIfMissing
    , removeDirectoryRecursive
    )
import System.Process
    ( callProcess
    , readProcess
    , readProcessWithExitCode
    )
import System.Timeout (timeout)
import Test.Hspec
    ( Spec
    , around
    , describe
    , it
    , shouldBe
    , shouldReturn
    , shouldSatisfy
    )

-- | API type without the Raw fallback, for client generation.
type RestApi =
    "sessions"
        :> Get '[JSON] [Value]
        :<|> "sessions"
            :> Capture "sid" Text
            :> QueryParam "confirm" Text
            :> Delete '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-pane"
            :> "close"
            :> "preview"
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-pane"
            :> "close"
            :> ReqBody '[JSON] Value
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-window"
            :> "close"
            :> "preview"
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-window"
            :> "close"
            :> ReqBody '[JSON] Value
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "panes"
            :> Get '[JSON] [Value]
        :<|> "sessions"
            :> Capture "sid" Text
            :> "panes"
            :> ReqBody '[JSON] Value
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "layout"
            :> ReqBody '[JSON] Value
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> Get '[JSON] [Value]
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> "new"
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> ReqBody '[JSON] Value
            :> Post '[JSON] Value
        :<|> "worktrees"
            :> Get '[JSON] [Value]
        :<|> "branches"
            :> Get '[JSON] [Value]
        :<|> "branches"
            :> Capture "repo" Text
            :> Capture "branch" Text
            :> Delete '[JSON] Value

-- | Servant client functions.
listSessions :: ClientM [Value]
deleteSession :: Text -> Maybe Text -> ClientM Value
previewPaneClose :: Text -> ClientM Value
executePaneClose :: Text -> Value -> ClientM Value
previewWindowClose :: Text -> ClientM Value
executeWindowClose :: Text -> Value -> ClientM Value
listPanes :: Text -> ClientM [Value]
splitPane :: Text -> Value -> ClientM Value
_selectLayout :: Text -> Value -> ClientM Value
listWindows :: Text -> ClientM [Value]
newWindow :: Text -> ClientM Value
selectWindow :: Text -> Value -> ClientM Value
listWorktrees :: ClientM [Value]
listBranches :: ClientM [Value]
_deleteBranch :: Text -> Text -> ClientM Value
( listSessions
        :<|> deleteSession
        :<|> previewPaneClose
        :<|> executePaneClose
        :<|> previewWindowClose
        :<|> executeWindowClose
        :<|> listPanes
        :<|> splitPane
        :<|> _selectLayout
        :<|> listWindows
        :<|> newWindow
        :<|> selectWindow
        :<|> listWorktrees
        :<|> listBranches
        :<|> _deleteBranch
    ) = client (Proxy :: Proxy RestApi)

-- | Base directory for test worktrees.
testBaseDir :: FilePath
testBaseDir = "/tmp/agent-daemon-test"

-- | Run a test against a temporary warp server.
withTestServer :: (Int -> IO ()) -> IO ()
withTestServer action =
    bracket_
        (createDirectoryIfMissing True testBaseDir)
        (removeDirectoryRecursive testBaseDir)
        $ do
            mgr <- newSessionManager
            let app = apiApp testBaseDir "static" mgr
            Warp.testWithApplication (pure app) action

-- | Run a test server with one registered tmux session.
data TestBoundary = TestBoundary
    { testBoundary :: CloseBoundary
    , testBoundaryAttempts :: IORef Int
    , testBoundaryGate :: IORef (Maybe (MVar (), MVar ()))
    , testBoundaryFailure :: IORef (Maybe CloseActionFailure)
    , testSessionManager :: SessionManager
    }

newTestBoundary :: SessionManager -> IO TestBoundary
newTestBoundary testSessionManager = do
    testBoundaryAttempts <- newIORef 0
    testBoundaryGate <- newIORef Nothing
    testBoundaryFailure <- newIORef Nothing
    let testBoundary = CloseBoundary $ \realAction -> do
            atomicModifyIORef' testBoundaryAttempts $ \count -> (count + 1, ())
            gate <- readIORef testBoundaryGate
            gateResult <- case gate of
                Nothing -> pure $ Just ()
                Just (entered, release) ->
                    timeout 3000000 $ do
                        putMVar entered ()
                        takeMVar release
            case gateResult of
                Nothing ->
                    pure $
                        Left $
                            CloseActionProcessFailure "test boundary timed out"
                Just () -> do
                    injected <- readIORef testBoundaryFailure
                    atomicWriteIORef testBoundaryFailure Nothing
                    maybe realAction (pure . Left) injected
    pure
        TestBoundary
            { testBoundary
            , testBoundaryAttempts
            , testBoundaryGate
            , testBoundaryFailure
            , testSessionManager
            }

-- | Run a test server with one registered tmux session.
withPaneTestServer :: ((Int, Text, TestBoundary) -> IO ()) -> IO ()
withPaneTestServer action =
    do
        unique <- newUnique
        epoch <- round . (* 1000000) <$> getPOSIXTime
        let testPaneSession =
                "agent-daemon-api-"
                    <> T.pack (show (epoch :: Integer))
                    <> "-"
                    <> T.pack (show $ hashUnique unique)
            setup =
                callProcess
                    "tmux"
                    [ "new-session"
                    , "-d"
                    , "-s"
                    , T.unpack testPaneSession
                    , "-n"
                    , "first"
                    , "-x"
                    , "100"
                    , "-y"
                    , "40"
                    , "-c"
                    , "/tmp"
                    ]
            cleanup =
                ()
                    <$ readProcessWithExitCode
                        "tmux"
                        ["kill-session", "-t", T.unpack testPaneSession]
                        ""
        bracket_ setup cleanup $ do
            mgr <- newSessionManager
            boundary <- newTestBoundary mgr
            now <- getCurrentTime
            let sid = SessionId testPaneSession
                session =
                    Session
                        { sessionId = sid
                        , sessionTmuxName = testPaneSession
                        , sessionCurrentPath = "/tmp"
                        , sessionState = Running
                        , sessionCreatedAt = now
                        , sessionLastActivity = now
                        }
            atomically $
                writeTVar
                    (sessions mgr)
                    (Map.singleton sid session)
            let app =
                    apiAppWithCloseBoundary
                        (testBoundary boundary)
                        testBaseDir
                        "static"
                        mgr
            Warp.testWithApplication (pure app) $ \port ->
                action (port, testPaneSession, boundary)

-- | Run a client request against a test server.
runClient
    :: Int -> ClientM a -> IO (Either ClientError a)
runClient port req = do
    manager <- newManager defaultManagerSettings
    let env =
            mkClientEnv
                manager
                (BaseUrl Http "127.0.0.1" port "")
    runClientM req env

spec :: Spec
spec = describe "REST API" $ do
    around (\action -> withTestServer action) $ do
        it "GET /sessions returns a list" $
            \port -> do
                result <- runClient port listSessions
                result `shouldSatisfy` isRight

        it "GET /worktrees returns a list" $
            \port -> do
                result <- runClient port listWorktrees
                result `shouldSatisfy` isRight

        it "GET /branches returns a list" $
            \port -> do
                result <- runClient port listBranches
                result `shouldSatisfy` isRight

        it "DELETE /sessions/:sid returns 404 for unknown" $
            \port -> do
                result <-
                    runClient
                        port
                        (deleteSession "nonexistent" Nothing)
                case result of
                    Left (FailureResponse _ resp) ->
                        responseStatusCode resp
                            `shouldBe` status404
                    other ->
                        fail $
                            "Expected 404, got: "
                                <> show other

        it "OPTIONS /sessions/:sid/windows answers CORS preflight" $
            \port -> do
                manager <- newManager defaultManagerSettings
                request <-
                    parseRequest $
                        "http://127.0.0.1:"
                            <> show port
                            <> "/sessions/demo/windows"
                response <-
                    httpLbs
                        request
                            { method = "OPTIONS"
                            , requestHeaders =
                                [
                                    ( "Origin"
                                    , "https://lambdasistemi.github.io"
                                    )
                                ,
                                    ( "Access-Control-Request-Method"
                                    , "POST"
                                    )
                                ,
                                    ( "Access-Control-Request-Headers"
                                    , "content-type"
                                    )
                                ]
                            }
                        manager

                responseStatus response `shouldBe` status200
                lookup
                    "Access-Control-Allow-Origin"
                    (responseHeaders response)
                    `shouldBe` Just "*"
                lookup
                    "Access-Control-Allow-Methods"
                    (responseHeaders response)
                    `shouldBe` Just "GET, POST, DELETE, OPTIONS"
                lookup
                    "Access-Control-Allow-Headers"
                    (responseHeaders response)
                    `shouldBe` Just "Content-Type"

    around (\action -> withPaneTestServer action) $ do
        it "previews and closes only the current pane" $
            \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    [ "split-window"
                    , "-v"
                    , "-t"
                    , T.unpack testPaneSession
                    , "-c"
                    , "/tmp"
                    ]
                before <- tmuxIdentities "list-panes" testPaneSession
                active <- tmuxActive "pane" testPaneSession
                preview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                secrets <- tmuxTokenSecrets testPaneSession
                tokenText preview
                    `shouldSatisfy` opaqueToken testPaneSession secrets
                preview `shouldSatisfy` hasExactPreviewSchema
                field "consequence" preview `shouldBe` Just (String "pane-removed")
                result <-
                    requireRight
                        =<< runClient
                            port
                            (executePaneClose testPaneSession $ confirmationBody preview)
                field "consequence" result `shouldBe` Just (String "pane-removed")
                field "sessionEnded" result `shouldBe` Just (Bool False)
                after <- tmuxIdentities "list-panes" testPaneSession
                after `shouldBe` filter (/= active) before
                sessionsResult <- requireRight =<< runClient port listSessions
                sessionsResult `shouldSatisfy` any (hasSessionId testPaneSession)
                result `shouldSatisfy` hasExactExecutionSchema

        it
            "classifies a last pane as removing its window but preserves another window"
            $ \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    ["new-window", "-t", T.unpack testPaneSession, "-n", "survivor"]
                callProcess
                    "tmux"
                    ["select-window", "-t", T.unpack testPaneSession <> ":first"]
                before <- tmuxIdentities "list-windows" testPaneSession
                active <- tmuxActive "window" testPaneSession
                preview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                field "consequence" preview
                    `shouldBe` Just (String "pane-and-window-removed")
                result <-
                    requireRight
                        =<< runClient
                            port
                            (executePaneClose testPaneSession $ confirmationBody preview)
                field "sessionEnded" result `shouldBe` Just (Bool False)
                field "consequence" result
                    `shouldBe` Just (String "pane-and-window-removed")
                after <- tmuxIdentities "list-windows" testPaneSession
                after `shouldBe` filter (/= active) before
                sessionsResult <- requireRight =<< runClient port listSessions
                sessionsResult `shouldSatisfy` any (hasSessionId testPaneSession)
                result `shouldSatisfy` hasExactExecutionSchema

        it "truthfully ends and unregisters the last pane of the last window" $
            \(port, testPaneSession, _) -> do
                preview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                field "consequence" preview `shouldBe` Just (String "session-ended")
                result <-
                    requireRight
                        =<< runClient
                            port
                            (executePaneClose testPaneSession $ confirmationBody preview)
                field "sessionEnded" result `shouldBe` Just (Bool True)
                field "consequence" result
                    `shouldBe` Just (String "session-ended")
                sessionsResult <- requireRight =<< runClient port listSessions
                sessionsResult
                    `shouldSatisfy` all (not . hasSessionId testPaneSession)
                result `shouldSatisfy` containsNoTmuxIdentity
                result `shouldSatisfy` hasExactExecutionSchema

        it
            "closes only the current window and reports last-window session end"
            $ \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    ["new-window", "-t", T.unpack testPaneSession, "-n", "current"]
                before <- tmuxIdentities "list-windows" testPaneSession
                active <- tmuxActive "window" testPaneSession
                preview <-
                    requireRight =<< runClient port (previewWindowClose testPaneSession)
                secrets <- tmuxTokenSecrets testPaneSession
                tokenText preview
                    `shouldSatisfy` opaqueToken testPaneSession secrets
                field "consequence" preview `shouldBe` Just (String "window-removed")
                result <-
                    requireRight
                        =<< runClient
                            port
                            (executeWindowClose testPaneSession $ confirmationBody preview)
                field "sessionEnded" result `shouldBe` Just (Bool False)
                after <- tmuxIdentities "list-windows" testPaneSession
                after `shouldBe` filter (/= active) before
                survivorRegistry <- requireRight =<< runClient port listSessions
                survivorRegistry `shouldSatisfy` any (hasSessionId testPaneSession)
                result `shouldSatisfy` hasExactExecutionSchema
                lastPreview <-
                    requireRight =<< runClient port (previewWindowClose testPaneSession)
                ended <-
                    requireRight
                        =<< runClient
                            port
                            (executeWindowClose testPaneSession $ confirmationBody lastPreview)
                field "sessionEnded" ended `shouldBe` Just (Bool True)
                field "consequence" ended
                    `shouldBe` Just (String "session-ended")
                endedRegistry <- requireRight =<< runClient port listSessions
                endedRegistry
                    `shouldSatisfy` all (not . hasSessionId testPaneSession)
                ended `shouldSatisfy` hasExactExecutionSchema

        it
            "fails closed for invalid, reused, superseded, wrong-session, and wrong-scope tokens"
            $ \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    ["split-window", "-v", "-t", T.unpack testPaneSession]
                initial <- tmuxIdentities "list-panes" testPaneSession
                expectConflict
                    =<< runClient
                        port
                        ( executePaneClose testPaneSession $
                            object ["confirmation" .= ("unknown" :: Text)]
                        )
                tmuxIdentities "list-panes" testPaneSession
                    `shouldReturn` initial
                first <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                newest <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                tokenText first `shouldSatisfy` (/= tokenText newest)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody first)
                tmuxIdentities "list-panes" testPaneSession
                    `shouldReturn` initial
                _ <-
                    requireRight
                        =<< runClient
                            port
                            (executePaneClose testPaneSession $ confirmationBody newest)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody newest)
                afterSuccess <- tmuxIdentities "list-panes" testPaneSession
                length afterSuccess `shouldBe` 1

        it
            "consumes recognized tokens used through the wrong session or scope"
            $ \(port, testPaneSession, boundary) -> do
                initial <- tmuxIdentities "list-panes" testPaneSession
                wrongSession <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose "another-session" $ confirmationBody wrongSession)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody wrongSession)
                tmuxIdentities "list-panes" testPaneSession
                    `shouldReturn` initial
                wrongScope <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                expectConflict
                    =<< runClient
                        port
                        (executeWindowClose testPaneSession $ confirmationBody wrongScope)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody wrongScope)
                tmuxIdentities "list-panes" testPaneSession
                    `shouldReturn` initial
                registry <- readTVarIO $ sessions $ testSessionManager boundary
                Map.member (SessionId testPaneSession) registry `shouldBe` True

        it "keeps confirmations independent across close scopes" $
            \(port, testPaneSession, boundary) -> do
                callProcess
                    "tmux"
                    ["split-window", "-v", "-t", T.unpack testPaneSession]
                panePreview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                windowPreview <-
                    requireRight =<< runClient port (previewWindowClose testPaneSession)
                tokenText panePreview `shouldSatisfy` (/= tokenText windowPreview)
                paneResult <-
                    requireRight
                        =<< runClient
                            port
                            (executePaneClose testPaneSession $ confirmationBody panePreview)
                field "consequence" paneResult
                    `shouldBe` Just (String "pane-removed")
                expectConflict
                    =<< runClient
                        port
                        ( executeWindowClose testPaneSession $
                            confirmationBody windowPreview
                        )
                attempts <- readIORef $ testBoundaryAttempts boundary
                attempts `shouldBe` 2

        it "consumes a token when tmux becomes unavailable" $
            \(port, testPaneSession, boundary) -> do
                preview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                callProcess
                    "tmux"
                    ["kill-session", "-t", T.unpack testPaneSession]
                failure <-
                    runClient port $
                        executePaneClose testPaneSession $
                            confirmationBody preview
                expectTmuxFailure failure
                registry <- readTVarIO $ sessions $ testSessionManager boundary
                Map.member (SessionId testPaneSession) registry `shouldBe` True
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody preview)

        it "maps and consumes tmux process and parse failures" $
            \(port, testPaneSession, boundary) -> do
                mapM_
                    ( \(injected, expectedError) -> do
                        preview <-
                            requireRight
                                =<< runClient
                                    port
                                    (previewPaneClose testPaneSession)
                        atomicWriteIORef
                            (testBoundaryFailure boundary)
                            (Just injected)
                        failure <-
                            runClient port $
                                executePaneClose testPaneSession $
                                    confirmationBody preview
                        expectTmuxFailureWith expectedError failure
                        registry <- requireRight =<< runClient port listSessions
                        registry
                            `shouldSatisfy` any (hasSessionId testPaneSession)
                        expectConflict
                            =<< runClient
                                port
                                ( executePaneClose testPaneSession $
                                    confirmationBody preview
                                )
                    )
                    [
                        ( CloseActionProcessFailure "injected process failure"
                        , "tmux-process-failure"
                        )
                    ,
                        ( CloseActionParseFailure "injected parse failure"
                        , "tmux-parse-failure"
                        )
                    ]

        it
            "rejects raced current panes and windows without closing any context"
            $ \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    ["split-window", "-v", "-t", T.unpack testPaneSession]
                panePreview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                inactivePane <- tmuxInactivePane testPaneSession
                callProcess
                    "tmux"
                    [ "select-pane"
                    , "-t"
                    , T.unpack inactivePane
                    ]
                paneBefore <- tmuxTopology testPaneSession
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody panePreview)
                expectConflict
                    =<< runClient
                        port
                        (executePaneClose testPaneSession $ confirmationBody panePreview)
                tmuxTopology testPaneSession
                    `shouldReturn` paneBefore
                callProcess
                    "tmux"
                    ["new-window", "-t", T.unpack testPaneSession, "-n", "race"]
                windowPreview <-
                    requireRight =<< runClient port (previewWindowClose testPaneSession)
                callProcess
                    "tmux"
                    ["select-window", "-t", T.unpack testPaneSession <> ":first"]
                windowBefore <- tmuxTopology testPaneSession
                expectConflict
                    =<< runClient
                        port
                        (executeWindowClose testPaneSession $ confirmationBody windowPreview)
                expectConflict
                    =<< runClient
                        port
                        (executeWindowClose testPaneSession $ confirmationBody windowPreview)
                tmuxTopology testPaneSession
                    `shouldReturn` windowBefore
                registry <- requireRight =<< runClient port listSessions
                registry `shouldSatisfy` any (hasSessionId testPaneSession)

        it "permits at most one concurrent replay boundary attempt" $
            \(port, testPaneSession, boundary) -> do
                callProcess
                    "tmux"
                    ["split-window", "-v", "-t", T.unpack testPaneSession]
                preview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                let request =
                        runClient port $
                            executePaneClose testPaneSession $
                                confirmationBody preview
                entered <- newEmptyMVar
                release <- newEmptyMVar
                atomicWriteIORef
                    (testBoundaryGate boundary)
                    (Just (entered, release))
                firstResult <- newEmptyMVar
                _ <- forkIO $ request >>= putMVar firstResult
                requireWithin "boundary entry" $ takeMVar entered
                second <- requireWithin "losing replay" request
                expectConflict second
                attempts <- readIORef $ testBoundaryAttempts boundary
                attempts `shouldBe` 1
                requireWithin "boundary release" $ putMVar release ()
                first <- requireWithin "winning replay" $ takeMVar firstResult
                first `shouldSatisfy` isRight
                tmuxCount "list-panes" testPaneSession `shouldReturnCount` 1

        it "accepts only an opaque confirmation field on execute routes" $
            \(port, testPaneSession, _) -> do
                panePreview <-
                    requireRight =<< runClient port (previewPaneClose testPaneSession)
                paneSecrets <- tmuxTokenSecrets testPaneSession
                tokenText panePreview
                    `shouldSatisfy` opaqueToken testPaneSession paneSecrets
                paneResult <-
                    runClient port $
                        executePaneClose testPaneSession $
                            object
                                [ "confirmation" .= tokenText panePreview
                                , "paneId" .= ("%1" :: Text)
                                ]
                expectBadRequest paneResult
                windowPreview <-
                    requireRight =<< runClient port (previewWindowClose testPaneSession)
                windowSecrets <- tmuxTokenSecrets testPaneSession
                tokenText windowPreview
                    `shouldSatisfy` opaqueToken testPaneSession windowSecrets
                windowResult <-
                    runClient port $
                        executeWindowClose testPaneSession $
                            object
                                [ "confirmation" .= tokenText windowPreview
                                , "windowIndex" .= (1 :: Int)
                                ]
                expectBadRequest windowResult
                expectPreviewTargetRejected
                    port
                    testPaneSession
                    "current-pane"
                expectPreviewBodyRejected
                    port
                    testPaneSession
                    "current-pane"
                expectPreviewTargetRejected
                    port
                    testPaneSession
                    "current-window"
                expectPreviewBodyRejected
                    port
                    testPaneSession
                    "current-window"

        it "DELETE /sessions/:sid requires exact confirmation" $
            \(port, testPaneSession, _) -> do
                result <-
                    runClient
                        port
                        (deleteSession testPaneSession Nothing)
                case result of
                    Left (FailureResponse _ resp) ->
                        responseStatusCode resp
                            `shouldBe` status400
                    other ->
                        fail $
                            "Expected 400, got: "
                                <> show other

        it "GET /sessions/:sid/panes returns tmux pane metadata" $
            \(port, testPaneSession, _) -> do
                result <-
                    runClient
                        port
                        (listPanes testPaneSession)
                case result of
                    Right panes -> do
                        length panes `shouldBe` 1
                        panes
                            `shouldSatisfy` all hasPaneFields
                    Left err ->
                        fail $ "Expected pane list, got: " <> show err

        it "POST /sessions/:sid/panes creates a new pane" $
            \(port, testPaneSession, _) -> do
                result <-
                    runClient
                        port
                        ( splitPane
                            testPaneSession
                            ( object
                                [ "direction" .= ("vertical" :: Text)
                                ]
                            )
                        )
                case result of
                    Right pane ->
                        pane `shouldSatisfy` hasPaneFields
                    Left err ->
                        fail $ "Expected split pane, got: " <> show err

                panesResult <-
                    runClient
                        port
                        (listPanes testPaneSession)
                panesResult
                    `shouldSatisfy` \case
                        Right panes -> length panes == 2
                        Left _ -> False

        it "GET /sessions/:sid/windows returns tmux window metadata" $
            \(port, testPaneSession, _) -> do
                result <-
                    runClient
                        port
                        (listWindows testPaneSession)
                case result of
                    Right windows -> do
                        length windows `shouldBe` 1
                        windows
                            `shouldSatisfy` all hasWindowFields
                    Left err ->
                        fail $ "Expected window list, got: " <> show err

        it "POST /sessions/:sid/windows/new creates a selected tmux window" $
            \(port, testPaneSession, _) -> do
                result <-
                    runClient
                        port
                        (newWindow testPaneSession)
                case result of
                    Right window ->
                        window `shouldSatisfy` isActiveWindowValue
                    Left err ->
                        fail $ "Expected new window, got: " <> show err

                windowsResult <-
                    runClient
                        port
                        (listWindows testPaneSession)
                windowsResult
                    `shouldSatisfy` \case
                        Right windows ->
                            length windows == 2
                                && any isActiveWindowValue windows
                        Left _ -> False

        it "POST /sessions/:sid/windows selects a tmux window" $
            \(port, testPaneSession, _) -> do
                callProcess
                    "tmux"
                    [ "new-window"
                    , "-t"
                    , T.unpack testPaneSession
                    , "-n"
                    , "second"
                    , "-c"
                    , "/tmp"
                    ]
                callProcess
                    "tmux"
                    [ "select-window"
                    , "-t"
                    , T.unpack testPaneSession <> ":first"
                    ]

                secondIndex <-
                    read
                        . T.unpack
                        . T.strip
                        . T.pack
                        <$> readProcess
                            "tmux"
                            [ "display-message"
                            , "-p"
                            , "-t"
                            , T.unpack testPaneSession <> ":second"
                            , "#{window_index}"
                            ]
                            ""

                result <-
                    runClient
                        port
                        ( selectWindow
                            testPaneSession
                            ( object
                                [ "index" .= (secondIndex :: Int)
                                ]
                            )
                        )
                case result of
                    Right _ -> pure ()
                    Left err ->
                        fail $ "Expected window selection, got: " <> show err

                windowsResult <-
                    runClient
                        port
                        (listWindows testPaneSession)
                windowsResult
                    `shouldSatisfy` \case
                        Right windows ->
                            any (isActiveWindow "second") windows
                        Left _ -> False

-- | Check if an Either is Right.
isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False

requireRight :: (Show a) => Either a b -> IO b
requireRight (Right value) = pure value
requireRight (Left err) = fail $ "Expected success, got: " <> show err

field :: Text -> Value -> Maybe Value
field key (Object value) = KM.lookup (Key.fromText key) value
field _ _ = Nothing

tokenText :: Value -> Text
tokenText value =
    case field "confirmation" value of
        Just (String token) -> token
        other -> error $ "missing confirmation: " <> show other

confirmationBody :: Value -> Value
confirmationBody value = object ["confirmation" .= tokenText value]

expectConflict :: (Show a) => Either ClientError a -> IO ()
expectConflict (Left (FailureResponse _ response)) = do
    responseStatusCode response `shouldBe` status409
    let body = decode (responseBody response) :: Maybe Value
    (body >>= field "error")
        `shouldBe` Just (String "stale-current-context")
    (body >>= field "status")
        `shouldBe` Just (String "stale-current-context")
expectConflict other = fail $ "Expected 409, got: " <> show other

expectTmuxFailure :: (Show a) => Either ClientError a -> IO ()
expectTmuxFailure (Left (FailureResponse _ response)) = do
    responseStatusCode response `shouldBe` status500
    let body = decode (responseBody response) :: Maybe Value
    (body >>= field "status") `shouldBe` Just (String "tmux-failure")
    (body >>= field "error") `shouldSatisfy` \case
        Just (String message) -> not $ T.null message
        _ -> False
expectTmuxFailure other = fail $ "Expected tmux failure, got: " <> show other

expectTmuxFailureWith
    :: (Show a) => Text -> Either ClientError a -> IO ()
expectTmuxFailureWith expected (Left (FailureResponse _ response)) = do
    responseStatusCode response `shouldBe` status500
    let body = decode (responseBody response) :: Maybe Value
    (body >>= field "status") `shouldBe` Just (String "tmux-failure")
    (body >>= field "error") `shouldBe` Just (String expected)
expectTmuxFailureWith _ other =
    fail $ "Expected injected tmux failure, got: " <> show other

requireWithin :: String -> IO a -> IO a
requireWithin label action = do
    result <- timeout 3000000 action
    maybe (fail $ label <> " timed out") pure result

expectBadRequest :: (Show a) => Either ClientError a -> IO ()
expectBadRequest (Left (FailureResponse _ response)) =
    responseStatusCode response `shouldBe` status400
expectBadRequest other = fail $ "Expected 400, got: " <> show other

expectPreviewTargetRejected :: Int -> Text -> Text -> IO ()
expectPreviewTargetRejected port sessionName scope = do
    manager <- newManager defaultManagerSettings
    request <-
        parseRequest $
            "http://127.0.0.1:"
                <> show port
                <> "/sessions/"
                <> T.unpack sessionName
                <> "/"
                <> T.unpack scope
                <> "/close/preview?target=%251"
    response <-
        httpLbs
            request
                { method = "POST"
                }
            manager
    responseStatus response `shouldBe` status400

expectPreviewBodyRejected :: Int -> Text -> Text -> IO ()
expectPreviewBodyRejected port sessionName scope = do
    manager <- newManager defaultManagerSettings
    request <-
        parseRequest $
            "http://127.0.0.1:"
                <> show port
                <> "/sessions/"
                <> T.unpack sessionName
                <> "/"
                <> T.unpack scope
                <> "/close/preview"
    response <-
        httpLbs
            request
                { method = "POST"
                , requestHeaders = [("Content-Type", "application/json")]
                , requestBody = RequestBodyLBS "{\"paneId\":\"%1\"}"
                }
            manager
    responseStatus response `shouldBe` status400

tmuxCount :: String -> Text -> IO Int
tmuxCount command sessionName =
    length . lines
        <$> readProcess
            "tmux"
            [ command
            , "-t"
            , T.unpack sessionName
            , "-F"
            , if command == "list-panes" then "#{pane_id}" else "#{window_id}"
            ]
            ""

shouldReturnCount :: IO Int -> Int -> IO ()
shouldReturnCount action expected = action >>= (`shouldBe` expected)

tmuxIdentities :: String -> Text -> IO [Text]
tmuxIdentities command sessionName =
    T.lines . T.pack
        <$> readProcess
            "tmux"
            [ command
            , "-t"
            , T.unpack sessionName
            , "-F"
            , if command == "list-panes" then "#{pane_id}" else "#{window_id}"
            ]
            ""

tmuxActive :: Text -> Text -> IO Text
tmuxActive kind sessionName =
    T.strip . T.pack
        <$> readProcess
            "tmux"
            [ "display-message"
            , "-p"
            , "-t"
            , T.unpack sessionName
            , if kind == "pane" then "#{pane_id}" else "#{window_id}"
            ]
            ""

tmuxInactivePane :: Text -> IO Text
tmuxInactivePane sessionName = do
    rows <-
        T.lines . T.pack
            <$> readProcess
                "tmux"
                [ "list-panes"
                , "-t"
                , T.unpack sessionName
                , "-F"
                , "#{pane_id} #{pane_active}"
                ]
                ""
    case [pane | row <- rows, [pane, "0"] <- [T.words row]] of
        pane : _ -> pure pane
        [] -> fail "expected an inactive pane"

tmuxTopology :: Text -> IO [Text]
tmuxTopology sessionName =
    T.lines . T.pack
        <$> readProcess
            "tmux"
            [ "list-panes"
            , "-s"
            , "-t"
            , T.unpack sessionName
            , "-F"
            , "#{window_id}:#{window_index}:#{window_name}:#{pane_id}:#{pane_index}"
            ]
            ""

tmuxTokenSecrets :: Text -> IO [Text]
tmuxTokenSecrets sessionName =
    filter (not . T.all isDigit) . concatMap (T.splitOn ":")
        <$> tmuxTopology sessionName

opaqueToken :: Text -> [Text] -> Text -> Bool
opaqueToken sessionName identities token =
    not (T.null token)
        && T.all (\character -> isAsciiLower character || character == '-') token
        && all
            (\revealed -> T.null revealed || not (revealed `T.isInfixOf` token))
            ( sessionName
                : identities
                    <> [ "pane"
                       , "window"
                       , "current"
                       , "target"
                       , "first"
                       , "survivor"
                       , "race"
                       ]
            )

hasExactPreviewSchema :: Value -> Bool
hasExactPreviewSchema (Object value) =
    KM.size value == 2
        && all (`KM.member` value) ["consequence", "confirmation"]
hasExactPreviewSchema _ = False

hasExactExecutionSchema :: Value -> Bool
hasExactExecutionSchema (Object value) =
    KM.size value == 2
        && all (`KM.member` value) ["consequence", "sessionEnded"]
hasExactExecutionSchema _ = False

hasSessionId :: Text -> Value -> Bool
hasSessionId sid value = field "id" value == Just (String sid)

containsNoTmuxIdentity :: Value -> Bool
containsNoTmuxIdentity value =
    not $ any (`T.isInfixOf` encoded) ["%", "@", "paneId", "windowId"]
  where
    encoded = T.pack $ show value

-- | Check that a JSON value looks like a pane object.
hasPaneFields :: Value -> Bool
hasPaneFields (Object obj) =
    all
        (`KM.member` obj)
        ["id", "index", "active", "width", "height"]
hasPaneFields _ = False

-- | Check that a JSON value looks like a window object.
hasWindowFields :: Value -> Bool
hasWindowFields (Object obj) =
    all
        (`KM.member` obj)
        ["index", "name", "active"]
hasWindowFields _ = False

-- | Check if a JSON value is the active window with the given name.
isActiveWindow :: Text -> Value -> Bool
isActiveWindow name (Object obj) =
    KM.lookup "name" obj == Just (String name)
        && KM.lookup "active" obj == Just (Bool True)
isActiveWindow _ _ = False

-- | Check if a JSON value is marked as the active window.
isActiveWindowValue :: Value -> Bool
isActiveWindowValue (Object obj) =
    KM.lookup "active" obj == Just (Bool True)
isActiveWindowValue _ = False
