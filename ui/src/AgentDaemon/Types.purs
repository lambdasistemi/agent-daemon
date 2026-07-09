module AgentDaemon.Types
  ( PasteSnippet
  , Session
  , WindowInfo
  ) where

type PasteSnippet =
  { name :: String
  , body :: String
  }

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
