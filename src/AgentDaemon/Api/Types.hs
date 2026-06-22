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
    , LaunchRequest (..)
    , ModeRequest (..)
    , PromptRequest (..)
    , Session (..)
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
    , Raw
    , ReqBody
    , (:<|>)
    , (:>)
    )

-- | The full REST API for agent-daemon.
type AgentApi =
    "sessions"
        :> ReqBody '[JSON] LaunchRequest
        :> Post '[JSON] Value
        :<|> "sessions"
            :> Get '[JSON] [Session]
        :<|> "sessions"
            :> Capture "sid" Text
            :> Delete '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "mode"
            :> ReqBody '[JSON] ModeRequest
            :> Post '[JSON] Value
        :<|> "sessions"
            :> Capture "sid" Text
            :> "prompt"
            :> ReqBody '[JSON] PromptRequest
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
