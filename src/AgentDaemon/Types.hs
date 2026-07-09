{-# LANGUAGE DeriveGeneric #-}

module AgentDaemon.Types
    ( SessionId (..)
    , PaneId (..)
    , Repo (..)
    , SessionState (..)
    , Session (..)
    , SessionManager (..)
    , PaneInfo (..)
    , WindowInfo (..)
    , WindowSelectRequest (..)
    , ScrollRequest (..)
    , PaneSplitDirection (..)
    , PaneSplitRequest (..)
    , LayoutRequest (..)
    , WorktreeInfo (..)
    , BranchInfo (..)
    , SyncStatus (..)
    , GitError (..)
    , newSessionManager
    , updateSessionActivity
    ) where

-- \|
-- Module      : AgentDaemon.Types
-- Description : Core domain types
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Domain types for tmux-backed session management.

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

-- | Unique identifier for a session, matching the tmux session name.
newtype SessionId = SessionId {unSessionId :: Text}
    deriving stock (Eq, Ord, Show, Generic)
    deriving newtype (FromJSON, ToJSON)

-- | Tmux pane identifier, for example @%42@.
newtype PaneId = PaneId {unPaneId :: Text}
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
    = -- | tmux session being created
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

-- | A browser-controllable tmux session.
data Session = Session
    { sessionId :: SessionId
    -- ^ unique session identifier
    , sessionTmuxName :: Text
    -- ^ tmux session name
    , sessionCurrentPath :: FilePath
    -- ^ current path of the active pane at recovery time
    , sessionState :: SessionState
    -- ^ current session state
    , sessionCreatedAt :: UTCTime
    -- ^ creation timestamp
    , sessionLastActivity :: UTCTime
    -- ^ last terminal I/O timestamp
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

-- | Metadata for a tmux pane inside a session.
data PaneInfo = PaneInfo
    { paneId :: PaneId
    -- ^ stable tmux pane identifier
    , paneIndex :: Int
    -- ^ pane index within the window
    , paneActive :: Bool
    -- ^ whether tmux currently marks this pane active
    , paneCurrentCommand :: Text
    -- ^ foreground command name reported by tmux
    , paneCurrentPath :: FilePath
    -- ^ current working directory reported by tmux
    , paneWidth :: Int
    -- ^ pane width in terminal columns
    , paneHeight :: Int
    -- ^ pane height in terminal rows
    , paneWindowIndex :: Int
    -- ^ tmux window index containing the pane
    , paneWindowName :: Text
    -- ^ tmux window name containing the pane
    , paneWindowActive :: Bool
    -- ^ whether the containing tmux window is active
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON PaneInfo where
    toJSON = genericToJSON stripPrefix

-- | Metadata for a tmux window inside a session.
data WindowInfo = WindowInfo
    { windowIndex :: Int
    -- ^ tmux window index
    , windowName :: Text
    -- ^ tmux window name
    , windowActive :: Bool
    -- ^ whether tmux currently marks this window active
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON WindowInfo where
    toJSON = genericToJSON stripPrefix

-- | Request body for selecting a tmux window.
newtype WindowSelectRequest = WindowSelectRequest
    { selectIndex :: Int
    -- ^ tmux window index to select
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON WindowSelectRequest where
    parseJSON = genericParseJSON stripPrefix

-- | Request body for scrolling a tmux pane from touch gestures.
newtype ScrollRequest = ScrollRequest
    { scrollLines :: Int
    -- ^ Positive values scroll back; negative values scroll toward live output.
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON ScrollRequest where
    parseJSON = genericParseJSON stripPrefix

-- | Direction to split a pane.
data PaneSplitDirection
    = -- | left/right split, corresponding to @tmux split-window -h@
      SplitHorizontal
    | -- | top/bottom split, corresponding to @tmux split-window -v@
      SplitVertical
    deriving stock (Eq, Show, Generic)

instance ToJSON PaneSplitDirection where
    toJSON SplitHorizontal = Aeson.String "horizontal"
    toJSON SplitVertical = Aeson.String "vertical"

instance FromJSON PaneSplitDirection where
    parseJSON = Aeson.withText "PaneSplitDirection" $ \case
        "horizontal" -> pure SplitHorizontal
        "vertical" -> pure SplitVertical
        _ -> fail "expected horizontal or vertical"

-- | Request body for splitting a pane.
data PaneSplitRequest = PaneSplitRequest
    { splitTarget :: Maybe PaneId
    -- ^ pane to split; defaults to the session's active pane
    , splitDirection :: PaneSplitDirection
    -- ^ horizontal or vertical split
    , splitCwd :: Maybe FilePath
    -- ^ optional working directory for the new pane
    , splitCommand :: Maybe Text
    -- ^ optional shell command for the new pane
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON PaneSplitRequest where
    parseJSON = genericParseJSON stripPrefix

-- | Request body for selecting a tmux layout.
newtype LayoutRequest = LayoutRequest
    { layout :: Text
    -- ^ tmux layout name, for example @tiled@
    }
    deriving stock (Eq, Show, Generic)

instance FromJSON LayoutRequest where
    parseJSON = genericParseJSON stripPrefix

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
