module AgentDaemon.Api.Types
    ( AgentApi
    , agentApi
    ) where

-- \|
-- Module      : AgentDaemon.Api.Types
-- Description : Servant API type definition
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Type-level description of all REST endpoints exposed
-- by agent-daemon. The 'Raw' fallback at the end serves
-- static files for the single-page application.

import AgentDaemon.Types
    ( BranchInfo (..)
    , CloseConfirmationRequest
    , CloseExecution
    , ClosePreview
    , LayoutRequest (..)
    , PaneInfo (..)
    , PaneSplitRequest (..)
    , ScrollRequest (..)
    , Session (..)
    , WindowInfo (..)
    , WindowSelectRequest (..)
    , WorktreeInfo (..)
    )
import Data.Aeson (Value)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Servant.API
    ( Capture
    , Delete
    , Get
    , JSON
    , Post
    , QueryParam
    , Raw
    , ReqBody
    , (:<|>)
    , (:>)
    )

-- | The full REST API for agent-daemon.
type AgentApi =
    "sessions"
        :> Get '[JSON] [Session]
        :<|> "sessions"
            :> Capture "sid" Text
            :> QueryParam "confirm" Text
            :> Delete '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-pane"
            :> "close"
            :> "preview"
            :> Post '[JSON] ClosePreview
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-pane"
            :> "close"
            :> ReqBody '[JSON] CloseConfirmationRequest
            :> Post '[JSON] CloseExecution
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-window"
            :> "close"
            :> "preview"
            :> Post '[JSON] ClosePreview
        :<|> "sessions"
            :> Capture "sid" Text
            :> "current-window"
            :> "close"
            :> ReqBody '[JSON] CloseConfirmationRequest
            :> Post '[JSON] CloseExecution
        :<|> "sessions"
            :> Capture "sid" Text
            :> "panes"
            :> Get '[JSON] [PaneInfo]
        :<|> "sessions"
            :> Capture "sid" Text
            :> "panes"
            :> ReqBody '[JSON] PaneSplitRequest
            :> Post '[JSON] PaneInfo
        :<|> "sessions"
            :> Capture "sid" Text
            :> "layout"
            :> ReqBody '[JSON] LayoutRequest
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> Get '[JSON] [WindowInfo]
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> "new"
            :> Post '[JSON] WindowInfo
        :<|> "sessions"
            :> Capture "sid" Text
            :> "windows"
            :> ReqBody '[JSON] WindowSelectRequest
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "scroll"
            :> ReqBody '[JSON] ScrollRequest
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "live"
            :> Post '[JSON] Value
        :<|> "worktrees"
            :> Get '[JSON] [WorktreeInfo]
        :<|> "branches"
            :> Get '[JSON] [BranchInfo]
        :<|> "branches"
            :> Capture "repo" Text
            :> Capture "branch" Text
            :> Delete '[JSON] Value
        :<|> Raw

-- | Proxy for the API type.
agentApi :: Proxy AgentApi
agentApi = Proxy
