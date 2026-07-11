module AgentDaemon.Api
  ( closeCurrentPane
  , closeCurrentWindow
  , fetchSessions
  , fetchWindows
  , createWindow
  , deleteSession
  , previewCloseCurrentPane
  , previewCloseCurrentWindow
  , selectWindow
  , liveSession
  , scrollSession
  ) where

import Prelude

import AgentDaemon.Types (CloseExecution, ClosePreview, Session, WindowInfo)
import Control.Promise (Promise, toAffE)
import Effect (Effect)
import Effect.Aff (Aff)

foreign import fetchSessionsImpl
  :: String -> Effect (Promise (Array Session))

foreign import fetchWindowsImpl
  :: String -> String -> Effect (Promise (Array WindowInfo))

foreign import createWindowImpl
  :: String -> String -> Effect (Promise WindowInfo)

foreign import deleteSessionImpl
  :: String -> String -> Effect (Promise Unit)

foreign import previewCloseCurrentPaneImpl
  :: String -> String -> Effect (Promise ClosePreview)

foreign import closeCurrentPaneImpl
  :: String -> String -> String -> Effect (Promise CloseExecution)

foreign import previewCloseCurrentWindowImpl
  :: String -> String -> Effect (Promise ClosePreview)

foreign import closeCurrentWindowImpl
  :: String -> String -> String -> Effect (Promise CloseExecution)

foreign import selectWindowImpl
  :: String -> String -> Int -> Effect (Promise Unit)

foreign import scrollSessionImpl
  :: String -> String -> Int -> Effect (Promise Unit)

foreign import liveSessionImpl
  :: String -> String -> Effect (Promise Unit)

fetchSessions :: String -> Aff (Array Session)
fetchSessions base =
  toAffE (fetchSessionsImpl base)

fetchWindows :: String -> String -> Aff (Array WindowInfo)
fetchWindows base sessionId =
  toAffE (fetchWindowsImpl base sessionId)

createWindow :: String -> String -> Aff WindowInfo
createWindow base sessionId =
  toAffE (createWindowImpl base sessionId)

deleteSession :: String -> String -> Aff Unit
deleteSession base sessionId =
  toAffE (deleteSessionImpl base sessionId)

previewCloseCurrentPane :: String -> String -> Aff ClosePreview
previewCloseCurrentPane base sessionId =
  toAffE (previewCloseCurrentPaneImpl base sessionId)

closeCurrentPane :: String -> String -> String -> Aff CloseExecution
closeCurrentPane base sessionId confirmation =
  toAffE (closeCurrentPaneImpl base sessionId confirmation)

previewCloseCurrentWindow :: String -> String -> Aff ClosePreview
previewCloseCurrentWindow base sessionId =
  toAffE (previewCloseCurrentWindowImpl base sessionId)

closeCurrentWindow :: String -> String -> String -> Aff CloseExecution
closeCurrentWindow base sessionId confirmation =
  toAffE (closeCurrentWindowImpl base sessionId confirmation)

selectWindow :: String -> String -> Int -> Aff Unit
selectWindow base sessionId index =
  toAffE (selectWindowImpl base sessionId index)

scrollSession :: String -> String -> Int -> Aff Unit
scrollSession base sessionId lines =
  toAffE (scrollSessionImpl base sessionId lines)

liveSession :: String -> String -> Aff Unit
liveSession base sessionId =
  toAffE (liveSessionImpl base sessionId)
