{-# LANGUAGE DeriveGeneric #-}

module AgentDaemon.Types
    ( SessionId (..)
    , Repo (..)
    , SessionState (..)
    , Session (..)
    , SessionManager (..)
    , LaunchRequest (..)
    , WorktreeInfo (..)
    , newSessionManager
    , mkSessionId
    , mkTmuxName
    , mkWorktreePath
    ) where

-- \|
-- Module      : AgentDaemon.Types
-- Description : Core domain types
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Domain types for agent session management. A session maps
-- a GitHub issue to a tmux session running in a git worktree.

import Control.Concurrent.STM (TVar, newTVarIO)
import Data.Aeson
    ( FromJSON (..)
    , Options (..)
    , ToJSON (..)
    , defaultOptions
    , genericParseJSON
    , genericToJSON
    )
import Data.Aeson qualified as Aeson
import Data.Char (isAsciiUpper, toLower)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import GHC.Generics (Generic)

-- | Unique identifier for a session, derived from repo and issue.
newtype SessionId = SessionId {unSessionId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (FromJSON, ToJSON)

-- | GitHub repository reference.
data Repo = Repo
    { repoOwner :: Text
    -- ^ repository owner or organization
    , repoName :: Text
    -- ^ repository name
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON Repo where
    parseJSON = genericParseJSON stripPrefix

instance ToJSON Repo where
    toJSON = genericToJSON stripPrefix

-- | Current state of an agent session.
data SessionState
    = -- | worktree and tmux being created
      Creating
    | -- | tmux session running, no terminal attached
      Running
    | -- | terminal client connected via WebSocket
      Attached
    | -- | cleanup in progress
      Stopping
    | -- | session failed with reason
      Failed Text
    deriving stock (Eq, Show, Generic)

instance ToJSON SessionState where
    toJSON Creating = Aeson.String "creating"
    toJSON Running = Aeson.String "running"
    toJSON Attached = Aeson.String "attached"
    toJSON Stopping = Aeson.String "stopping"
    toJSON (Failed reason) =
        Aeson.String ("failed: " <> reason)

instance FromJSON SessionState where
    parseJSON = Aeson.withText "SessionState" $ \t ->
        case t of
            "creating" -> pure Creating
            "running" -> pure Running
            "attached" -> pure Attached
            "stopping" -> pure Stopping
            _ -> case T.stripPrefix "failed: " t of
                Just reason -> pure (Failed reason)
                Nothing -> fail "unknown state"

-- | An agent session binding an issue to a tmux session.
data Session = Session
    { sessionId :: SessionId
    -- ^ unique session identifier
    , sessionRepo :: Repo
    -- ^ target repository
    , sessionIssue :: Int
    -- ^ issue number
    , sessionWorktree :: FilePath
    -- ^ path to the git worktree
    , sessionTmuxName :: Text
    -- ^ tmux session name
    , sessionState :: SessionState
    -- ^ current session state
    , sessionCreatedAt :: UTCTime
    -- ^ creation timestamp
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON Session where
    toJSON = genericToJSON stripPrefix

-- | Thread-safe session registry.
newtype SessionManager = SessionManager
    { sessions :: TVar (Map SessionId Session)
    }

-- | Create an empty session manager.
newSessionManager :: IO SessionManager
newSessionManager =
    SessionManager <$> newTVarIO Map.empty

-- | Request to launch a new agent session.
data LaunchRequest = LaunchRequest
    { launchRepo :: Repo
    -- ^ target repository
    , launchIssue :: Int
    -- ^ issue number
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON LaunchRequest where
    parseJSON = genericParseJSON stripPrefix

-- | Build a session ID from repo name and issue number.
mkSessionId
    :: Repo
    -> Int
    -- ^ issue number
    -> SessionId
mkSessionId Repo{repoName} issue =
    SessionId $ repoName <> "-" <> T.pack (show issue)

-- | Build the tmux session name.
mkTmuxName
    :: Repo
    -> Int
    -- ^ issue number
    -> Text
mkTmuxName Repo{repoName} issue =
    repoName <> "-" <> T.pack (show issue)

-- | Build the worktree path under a base directory.
mkWorktreePath
    :: FilePath
    -- ^ base directory (e.g. @\/code@)
    -> Repo
    -> Int
    -- ^ issue number
    -> FilePath
mkWorktreePath baseDir Repo{repoName} issue =
    baseDir
        <> "/"
        <> T.unpack repoName
        <> "-issue-"
        <> show issue

-- | A worktree directory on disk, with repo and issue metadata.
data WorktreeInfo = WorktreeInfo
    { worktreeRepo :: Repo
    -- ^ repository reference
    , worktreeIssue :: Int
    -- ^ issue number
    , worktreePath :: FilePath
    -- ^ absolute path to the worktree directory
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON WorktreeInfo where
    toJSON = genericToJSON stripPrefix

{- | Aeson options that strip a camelCase prefix and
lowercase the first letter of the remainder.

@repoOwner@ becomes @owner@,
@sessionCreatedAt@ becomes @createdAt@.
-}
stripPrefix :: Options
stripPrefix =
    defaultOptions
        { fieldLabelModifier = dropPrefix
        }
  where
    dropPrefix s =
        case dropWhile (not . isUpper) s of
            [] -> s
            (c : cs) -> toLower c : cs
    isUpper = isAsciiUpper
