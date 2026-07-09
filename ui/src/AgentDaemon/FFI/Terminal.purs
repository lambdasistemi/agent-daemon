module AgentDaemon.FFI.Terminal
  ( TerminalCallbacks
  , TerminalController
  , attachTerminal
  , createTerminal
  , disconnectTerminal
  , fitTerminal
  , mountTerminal
  , sendCtrlB
  , sendCtrlBCommand
  , sendEscape
  , setTerminalFontSize
  , setTerminalTheme
  ) where

import Prelude

import Effect (Effect)

foreign import data TerminalController :: Type

type TerminalCallbacks =
  { onOpen :: String -> Effect Unit
  , onClose :: Effect Unit
  , onError :: Effect Unit
  , onLinkOpened :: Effect Unit
  , onLinkBlocked :: Effect Unit
  , onScrollGesture :: Int -> Effect Unit
  }

foreign import createTerminal
  :: String -> Int -> TerminalCallbacks -> Effect TerminalController

foreign import mountTerminal :: TerminalController -> String -> Effect Unit

foreign import attachTerminal
  :: TerminalController -> String -> String -> Effect Unit

foreign import disconnectTerminal :: TerminalController -> Effect Unit

foreign import fitTerminal :: TerminalController -> Effect Unit

foreign import sendEscape :: TerminalController -> Effect Unit

foreign import sendCtrlB :: TerminalController -> Effect Unit

foreign import sendCtrlBCommand :: TerminalController -> Effect Unit

foreign import setTerminalTheme :: TerminalController -> String -> Effect Unit

foreign import setTerminalFontSize :: TerminalController -> Int -> Effect Unit
