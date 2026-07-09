module AgentDaemon.FFI.Browser
  ( afterRender
  , apiBase
  , loadItem
  , loadPastes
  , renderIcons
  , saveItem
  , savePastes
  , sessionTerminalWsUrl
  , setDocumentTheme
  ) where

import Prelude

import AgentDaemon.Types (PasteSnippet)
import Effect (Effect)

foreign import loadItem :: String -> Effect String

foreign import saveItem :: String -> String -> Effect Unit

foreign import loadPastes :: String -> Effect (Array PasteSnippet)

foreign import savePastes :: String -> Array PasteSnippet -> Effect Unit

foreign import apiBase :: String -> Effect String

foreign import sessionTerminalWsUrl :: String -> String -> Effect String

foreign import renderIcons :: Effect Unit

foreign import afterRender :: Effect Unit -> Effect Unit

foreign import setDocumentTheme :: String -> Effect Unit
