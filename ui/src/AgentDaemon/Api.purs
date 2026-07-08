module AgentDaemon.Api
  ( fetchSessions
  , fetchWindows
  , createWindow
  , deleteSession
  , selectWindow
  , liveSession
  , scrollSession
  ) where

import Prelude

import AgentDaemon.Types (Session, WindowInfo)
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

selectWindow :: String -> String -> Int -> Aff Unit
selectWindow base sessionId index =
  toAffE (selectWindowImpl base sessionId index)

scrollSession :: String -> String -> Int -> Aff Unit
scrollSession base sessionId lines =
  toAffE (scrollSessionImpl base sessionId lines)

liveSession :: String -> String -> Aff Unit
liveSession base sessionId =
  toAffE (liveSessionImpl base sessionId)
