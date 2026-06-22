{-# LANGUAGE DeriveGeneric #-}

module AgentDaemon.Types
    ( SessionId (..)
    , Repo (..)
    , SessionState (..)
    , SessionMode (..)
    , Session (..)
    , SessionManager (..)
    , LaunchRequest (..)
    , PromptRequest (..)
    , ModeRequest (..)
    , WorktreeInfo (..)
    , BranchInfo (..)
    , SyncStatus (..)
    , GitError (..)
    , newSessionManager
    , mkSessionId
    , mkTmuxName
    , mkWorktreePath
    , updateSessionActivity
    ) where

-- \|
-- Module      : AgentDaemon.Types
-- Description : Core domain types
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Domain types for agent session management. A session maps
-- a GitHub issue to a tmux session running in a git worktree.

import Control.Concurrent.STM
    ( TVar
    , atomically
    , newTVarIO
    , readTVar
    , writeTVar
    )
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

-- | Structured error from a git subprocess call.
data GitError = GitError
    { gitCommand :: Text
    -- ^ the git subcommand (e.g. @"worktree add"@)
    , gitExitCode :: Int
    -- ^ process exit code
    , gitStderr :: Text
    -- ^ stderr output from git
    , gitRepoPath :: FilePath
    -- ^ repository path where the command ran
    }
    deriving stock (Eq, Show)

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

-- | How the claude process runs inside a session.
data SessionMode
    = -- | TUI mode (interactive terminal)
      Terminal
    | -- | stream-json mode (structured I/O)
      Structured
    deriving stock (Eq, Show, Generic)

instance ToJSON SessionMode where
    toJSON Terminal = Aeson.String "terminal"
    toJSON Structured = Aeson.String "structured"

instance FromJSON SessionMode where
    parseJSON = Aeson.withText "SessionMode" $ \t ->
        case t of
            "terminal" -> pure Terminal
            "structured" -> pure Structured
            _ -> fail "expected terminal or structured"

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
    , sessionPrompt :: Text
    -- ^ initial prompt sent to Claude
    , sessionLastActivity :: UTCTime
    -- ^ last terminal I/O timestamp
    , sessionMode :: SessionMode
    -- ^ current process mode
    , sessionClaudeId :: Maybe Text
    -- ^ claude conversation UUID for @--resume@
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

-- | Request to send a prompt to a structured session.
newtype PromptRequest = PromptRequest
    { promptText :: Text
    -- ^ the prompt content
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON PromptRequest where
    parseJSON =
        Aeson.withObject "PromptRequest" $ \o ->
            PromptRequest <$> o Aeson..: "prompt"

-- | Request to switch session mode.
newtype ModeRequest = ModeRequest
    { modeTarget :: SessionMode
    -- ^ the mode to switch to
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON ModeRequest where
    parseJSON =
        Aeson.withObject "ModeRequest" $ \o ->
            ModeRequest <$> o Aeson..: "mode"

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

-- | Remote sync status for a branch.
data SyncStatus
    = -- | local and remote are identical
      Synced
    | -- | local has commits not on remote
      Ahead Int
    | -- | remote has commits not on local
      Behind Int
    | -- | both have diverged
      Diverged {branchAhead :: Int, branchBehind :: Int}
    | -- | no remote tracking branch
      LocalOnly
    deriving stock (Eq, Show, Generic)

instance ToJSON SyncStatus where
    toJSON Synced = Aeson.String "synced"
    toJSON (Ahead n) =
        Aeson.object
            [ ("status", Aeson.String "ahead")
            , ("count", Aeson.toJSON n)
            ]
    toJSON (Behind n) =
        Aeson.object
            [ ("status", Aeson.String "behind")
            , ("count", Aeson.toJSON n)
            ]
    toJSON (Diverged a b) =
        Aeson.object
            [ ("status", Aeson.String "diverged")
            , ("ahead", Aeson.toJSON a)
            , ("behind", Aeson.toJSON b)
            ]
    toJSON LocalOnly = Aeson.String "local-only"

-- | A local issue branch with sync status.
data BranchInfo = BranchInfo
    { branchRepo :: Repo
    -- ^ repository reference
    , branchIssue :: Int
    -- ^ issue number
    , branchName :: Text
    -- ^ branch name (e.g. @feat\/issue-42@)
    , branchSync :: SyncStatus
    -- ^ sync status with remote
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON BranchInfo where
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

-- | Update the last activity timestamp for a session.
updateSessionActivity
    :: SessionManager -> SessionId -> UTCTime -> IO ()
updateSessionActivity mgr sid now =
    atomically $ do
        m <- readTVar (sessions mgr)
        writeTVar (sessions mgr) $
            Map.adjust
                (\s -> s{sessionLastActivity = now})
                sid
                m
