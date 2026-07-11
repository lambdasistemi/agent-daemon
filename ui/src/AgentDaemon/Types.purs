module AgentDaemon.Types
  ( CloseExecution
  , ClosePreview
  , PasteSnippet
  , Session
  , WindowInfo
  ) where

type ClosePreview =
  { consequence :: String
  , confirmation :: String
  }

type CloseExecution =
  { consequence :: String
  , sessionEnded :: Boolean
  }

type PasteSnippet =
  { name :: String
  , body :: String
  , enter :: Boolean
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
