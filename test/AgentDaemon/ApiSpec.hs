module AgentDaemon.ApiSpec
    ( spec
    ) where

{- |
Module      : AgentDaemon.ApiSpec
Description : API-level tests for servant endpoints
Copyright   : (c) Paolo Veronelli, 2026
License     : MIT

Tests the REST API endpoints via servant-client against
a live warp test server. Validates request/response shapes
and error handling.
-}

import AgentDaemon.Api (apiApp)
import AgentDaemon.Types (newSessionManager)
import Control.Exception (bracket_)
import Data.Aeson (Value)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Network.HTTP.Client
    ( defaultManagerSettings
    , newManager
    )
import Network.HTTP.Types (status404)
import System.Directory
    ( createDirectoryIfMissing
    , removeDirectoryRecursive
    )
import Network.Wai.Handler.Warp qualified as Warp
import Servant.API
    ( Capture
    , Delete
    , Get
    , JSON
    , Post
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
        :> ReqBody '[JSON] Value
        :> Post '[JSON] Value
        :<|> "sessions"
            :> Get '[JSON] [Value]
        :<|> "sessions"
            :> Capture "sid" Text
            :> Delete '[JSON] Value
        :<|> "worktrees"
            :> Get '[JSON] [Value]
        :<|> "branches"
            :> Get '[JSON] [Value]
        :<|> "branches"
            :> Capture "repo" Text
            :> Capture "branch" Text
            :> Delete '[JSON] Value

-- | Servant client functions.
_launchSession :: Value -> ClientM Value
listSessions :: ClientM [Value]
deleteSession :: Text -> ClientM Value
listWorktrees :: ClientM [Value]
listBranches :: ClientM [Value]
_deleteBranch :: Text -> Text -> ClientM Value
( _launchSession
        :<|> listSessions
        :<|> deleteSession
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
        it "GET /sessions returns empty list"
            $ \port -> do
                result <- runClient port listSessions
                result `shouldBe` Right []

        it "GET /worktrees returns a list"
            $ \port -> do
                result <- runClient port listWorktrees
                result `shouldSatisfy` isRight

        it "GET /branches returns a list"
            $ \port -> do
                result <- runClient port listBranches
                result `shouldSatisfy` isRight

        it "DELETE /sessions/:sid returns 404 for unknown"
            $ \port -> do
                result <-
                    runClient
                        port
                        (deleteSession "nonexistent")
                case result of
                    Left (FailureResponse _ resp) ->
                        responseStatusCode resp
                            `shouldBe` status404
                    other ->
                        fail $
                            "Expected 404, got: "
                                <> show other

-- | Check if an Either is Right.
isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False
