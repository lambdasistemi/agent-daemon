module AgentDaemon.FFI.Browser
  ( afterRender
  , apiBase
  , loadItem
  , renderIcons
  , saveItem
  , sessionTerminalWsUrl
  , setDocumentTheme
  ) where

import Prelude

import Effect (Effect)

foreign import loadItem :: String -> Effect String

foreign import saveItem :: String -> String -> Effect Unit

foreign import apiBase :: String -> Effect String

foreign import sessionTerminalWsUrl :: String -> String -> Effect String

foreign import renderIcons :: Effect Unit

foreign import afterRender :: Effect Unit -> Effect Unit

foreign import setDocumentTheme :: String -> Effect Unit
