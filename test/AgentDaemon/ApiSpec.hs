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

import AgentDaemon.Api (apiApp)
import AgentDaemon.Types
    ( Session (..)
    , SessionId (..)
    , SessionState (..)
    , newSessionManager
    , sessions
    )
import Control.Concurrent.STM
    ( atomically
    , writeTVar
    )
import Control.Exception
    ( bracket_
    )
import Data.Aeson
    ( Value (..)
    , object
    , (.=)
    )
import Data.Aeson.KeyMap qualified as KM
import Data.Map.Strict qualified as Map
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Network.HTTP.Client
    ( defaultManagerSettings
    , httpLbs
    , method
    , newManager
    , parseRequest
    , requestHeaders
    , responseHeaders
    , responseStatus
    )
import Network.HTTP.Types (status200, status400, status404)
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
import Test.Hspec
    ( Spec
    , around
    , describe
    , it
    , shouldBe
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

-- | Tmux session name for pane API tests.
testPaneSession :: Text
testPaneSession = "agent-daemon-api-pane-test"

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
withPaneTestServer :: (Int -> IO ()) -> IO ()
withPaneTestServer action =
    bracket_ setup cleanup $ do
        mgr <- newSessionManager
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
        let app = apiApp testBaseDir "static" mgr
        Warp.testWithApplication (pure app) action
  where
    setup = do
        cleanup
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
        it "DELETE /sessions/:sid requires exact confirmation" $
            \port -> do
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
            \port -> do
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
            \port -> do
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
            \port -> do
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
            \port -> do
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
            \port -> do
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
