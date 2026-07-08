module AgentDaemon.Types
  ( Session
  , WindowInfo
  ) where

type Session =
  { id :: String
  , state :: String
  , tmuxName :: String
  , currentPath :: String
  }

type WindowInfo =
  { index :: Int
  , name :: String
  , active :: Boolean
  }
