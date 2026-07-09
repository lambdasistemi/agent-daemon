module Main where

import Prelude

import AgentDaemon.Api as Api
import AgentDaemon.FFI.Browser as Browser
import AgentDaemon.FFI.Terminal as Terminal
import AgentDaemon.Types (PasteSnippet, Session, WindowInfo)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, attempt)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Halogen as H
import Halogen.Aff as HA
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Halogen.VDom.Driver (runUI)

main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  runUI appComponent unit body

type Slots :: forall k. Row k
type Slots = ()

type State =
  { sessions :: Array Session
  , windows :: Array WindowInfo
  , selectedSession :: String
  , attachedSession :: String
  , status :: String
  , server :: String
  , theme :: String
  , terminalFontSize :: Int
  , settingsOpen :: Boolean
  , sessionMenuOpen :: Boolean
  , windowMenuOpen :: Boolean
  , terminalMenuOpen :: Boolean
  , pasteMenuOpen :: Boolean
  , pastes :: Array PasteSnippet
  , pasteName :: String
  , pasteBody :: String
  , autoAttachAttempted :: Boolean
  , pendingStop :: Maybe Session
  , confirmInput :: String
  , terminal :: Maybe Terminal.TerminalController
  }

data TerminalEvent
  = TerminalOpened String
  | TerminalClosed
  | TerminalErrored
  | TerminalLinkOpened
  | TerminalLinkBlocked
  | TerminalScrollGesture Int

data Action
  = Initialize
  | RefreshSessions
  | SetServer String
  | SaveServer
  | ToggleTheme
  | SetTerminalFontSize String
  | AdjustTerminalFontSize Int
  | ToggleSettings
  | ToggleSessionMenu
  | ToggleWindowMenu
  | ToggleTerminalMenu
  | SendEscape
  | SendCtrlB
  | SendCtrlBCommand
  | SendLive
  | TogglePasteMenu
  | SetPasteName String
  | SetPasteBody String
  | SavePaste
  | ClearPaste
  | EditPaste String
  | DeletePaste String
  | PasteNamed String
  | PasteDraft
  | OpenStopDialog Session
  | CloseStopDialog
  | SetConfirmInput String
  | ConfirmStopSession
  | AttachSession String
  | ChooseSession String
  | CreateWindow
  | SelectWindow Int
  | Disconnect
  | HandleTerminal TerminalEvent

appComponent :: forall q i o. H.Component q i o Aff
appComponent = H.mkComponent
  { initialState: \_ ->
      { sessions: []
      , windows: []
      , selectedSession: ""
      , attachedSession: ""
      , status: "disconnected"
      , server: ""
      , theme: "dark"
      , terminalFontSize: defaultTerminalFontSize
      , settingsOpen: false
      , sessionMenuOpen: false
      , windowMenuOpen: false
      , terminalMenuOpen: false
      , pasteMenuOpen: false
      , pastes: []
      , pasteName: ""
      , pasteBody: ""
      , autoAttachAttempted: false
      , pendingStop: Nothing
      , confirmInput: ""
      , terminal: Nothing
      }
  , render
  , eval: H.mkEval H.defaultEval
      { initialize = Just Initialize
      , handleAction = handleAction
      }
  }

render :: State -> H.ComponentHTML Action Slots Aff
render state =
  HH.div
    [ cls "app-shell" ]
    [ renderHeader state
    , renderMain state
    , renderConfirm state
    ]

renderHeader :: State -> H.ComponentHTML Action Slots Aff
renderHeader state =
  HH.header_
    [ HH.h1_ [ HH.text "agent-daemon" ]
    , HH.span
        [ HP.id "status" ]
        [ HH.text state.status ]
    , HH.div
        [ cls "top-actions" ]
        [ iconOnlyButton "Refresh sessions" "refresh-cw" RefreshSessions Nothing
        , renderSessionSwitcher state
        , renderWindowSwitcher state
        , renderTerminalActions state
        , renderPasteActions state
        , HH.div
            [ cls "settings-shell" ]
            [ iconOnlyButton "Settings" "settings" ToggleSettings
                (Just (if state.settingsOpen then "true" else "false"))
            , renderSettings state
            ]
        ]
    ]

renderSessionSwitcher :: State -> H.ComponentHTML Action Slots Aff
renderSessionSwitcher state =
  HH.div
    [ cls "session-switcher" ]
    [ HH.button
        [ cls "session-button"
        , HP.title "Switch session"
        , HP.attr (HH.AttrName "aria-label") "Switch session"
        , HP.attr (HH.AttrName "aria-expanded")
            (if state.sessionMenuOpen then "true" else "false")
        , HE.onClick \_ -> ToggleSessionMenu
        ]
        [ HH.span
            [ cls "menu-prefix" ]
            [ HH.text "Session" ]
        , HH.span
            [ cls "button-label session-label" ]
            [ HH.text (activeSessionLabel state) ]
        , icon "chevron-down"
        ]
    , HH.div
        [ cls
            ( "session-menu"
                <> if state.sessionMenuOpen then "" else " hidden"
            )
        ]
        (renderSessionItems state)
    ]

renderSessionItems
  :: State
  -> Array (H.ComponentHTML Action Slots Aff)
renderSessionItems state =
  if Array.null state.sessions then
    [ HH.div
        [ cls "session-menu-empty" ]
        [ HH.text "no sessions" ]
    ]
  else
    map (renderSessionItem state) state.sessions

renderSessionItem :: State -> Session -> H.ComponentHTML Action Slots Aff
renderSessionItem state session =
  HH.button
    [ cls
        ( "session-menu-item"
            <> if session.id == state.attachedSession then " active" else ""
        )
    , HE.onClick \_ -> ChooseSession session.id
    ]
    [ HH.span
        [ cls "session-menu-main" ]
        [ HH.span
            [ cls "session-name" ]
            [ HH.text (sessionLabel session) ]
        , HH.span
            [ cls "session-meta" ]
            [ HH.text (sessionMeta session) ]
        ]
    , HH.span
        [ cls "session-state" ]
        [ HH.text session.state ]
    ]

renderWindowSwitcher :: State -> H.ComponentHTML Action Slots Aff
renderWindowSwitcher state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls "window-switcher" ]
      [ HH.button
          [ cls "window-button"
          , HP.title "Switch tmux window"
          , HP.attr (HH.AttrName "aria-label") "Switch tmux window"
          , HP.attr (HH.AttrName "aria-expanded")
              (if state.windowMenuOpen then "true" else "false")
          , HE.onClick \_ -> ToggleWindowMenu
          ]
          [ HH.span
              [ cls "menu-prefix" ]
              [ HH.text "Window" ]
          , HH.span
              [ cls "button-label window-label" ]
              [ HH.text (activeWindowLabel state) ]
          , icon "chevron-down"
          ]
      , HH.div
          [ cls
              ( "window-menu"
                  <> if state.windowMenuOpen then "" else " hidden"
              )
          ]
          (renderWindowItems state.windows)
      ]

renderWindowItems
  :: Array WindowInfo
  -> Array (H.ComponentHTML Action Slots Aff)
renderWindowItems windows =
  [ HH.button
      [ cls "window-menu-action"
      , HE.onClick \_ -> CreateWindow
      ]
      [ icon "plus"
      , HH.span
          [ cls "window-name" ]
          [ HH.text "New window" ]
      ]
  ]
    <>
      if Array.null windows then
        [ HH.div
            [ cls "window-menu-empty" ]
            [ HH.text "no windows" ]
        ]
      else
        map renderWindowItem windows

renderTerminalActions :: State -> H.ComponentHTML Action Slots Aff
renderTerminalActions state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls "terminal-actions-shell" ]
      [ iconOnlyButton "Terminal controls" "keyboard" ToggleTerminalMenu
          (Just (if state.terminalMenuOpen then "true" else "false"))
      , HH.div
          [ cls
              ( "terminal-menu"
                  <> if state.terminalMenuOpen then "" else " hidden"
              )
          ]
          [ HH.button
              [ cls "terminal-menu-item"
              , HE.onClick \_ -> SendEscape
              ]
              [ HH.text "Esc" ]
          , HH.button
              [ cls "terminal-menu-item"
              , HE.onClick \_ -> SendCtrlB
              ]
              [ HH.text "Ctrl-b" ]
          , HH.button
              [ cls "terminal-menu-item"
              , HE.onClick \_ -> SendCtrlBCommand
              ]
              [ HH.text "Ctrl-b :" ]
          , HH.button
              [ cls "terminal-menu-item"
              , HE.onClick \_ -> SendLive
              ]
              [ icon "radio"
              , HH.text "Live"
              ]
          ]
      ]

renderPasteActions :: State -> H.ComponentHTML Action Slots Aff
renderPasteActions state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls "paste-actions-shell" ]
      [ iconOnlyButton "Paste snippets" "clipboard-list" TogglePasteMenu
          (Just (if state.pasteMenuOpen then "true" else "false"))
      , HH.div
          [ cls
              ( "paste-menu"
                  <> if state.pasteMenuOpen then "" else " hidden"
              )
          ]
          (renderPasteItems state <> [ renderPasteEditor state ])
      ]

renderPasteItems
  :: State
  -> Array (H.ComponentHTML Action Slots Aff)
renderPasteItems state =
  if Array.null state.pastes then
    [ HH.div
        [ cls "paste-menu-empty" ]
        [ HH.text "no snippets" ]
    ]
  else
    map renderPasteItem state.pastes

renderPasteItem :: PasteSnippet -> H.ComponentHTML Action Slots Aff
renderPasteItem paste =
  HH.div
    [ cls "paste-menu-row" ]
    [ HH.button
        [ cls "paste-snippet-button"
        , HE.onClick \_ -> PasteNamed paste.name
        ]
        [ HH.span
            [ cls "paste-name" ]
            [ HH.text paste.name ]
        , HH.span
            [ cls "paste-preview" ]
            [ HH.text (pastePreview paste.body) ]
        ]
    , HH.button
        [ cls "paste-icon-button"
        , HP.title ("Edit " <> paste.name)
        , HP.attr (HH.AttrName "aria-label") ("Edit " <> paste.name)
        , HE.onClick \_ -> EditPaste paste.name
        ]
        [ icon "pencil" ]
    , HH.button
        [ cls "paste-icon-button danger-outline"
        , HP.title ("Delete " <> paste.name)
        , HP.attr (HH.AttrName "aria-label") ("Delete " <> paste.name)
        , HE.onClick \_ -> DeletePaste paste.name
        ]
        [ icon "trash-2" ]
    ]

renderPasteEditor :: State -> H.ComponentHTML Action Slots Aff
renderPasteEditor state =
  HH.div
    [ cls "paste-editor" ]
    [ HH.input
        [ HP.id "paste-name"
        , HP.type_ HP.InputText
        , HP.placeholder "name"
        , HP.value state.pasteName
        , HE.onValueInput SetPasteName
        ]
    , HH.textarea
        [ HP.id "paste-body"
        , cls "paste-textarea"
        , HP.placeholder "text"
        , HP.value state.pasteBody
        , HE.onValueInput SetPasteBody
        ]
    , HH.div
        [ cls "paste-editor-actions" ]
        [ HH.button
            [ HE.onClick \_ -> PasteDraft
            , HP.disabled (state.pasteBody == "")
            ]
            [ icon "send"
            , HH.text "Paste"
            ]
        , HH.button
            [ HE.onClick \_ -> SavePaste
            , HP.disabled (state.pasteName == "" || state.pasteBody == "")
            ]
            [ icon "save"
            , HH.text "Save"
            ]
        , HH.button
            [ HE.onClick \_ -> ClearPaste ]
            [ HH.text "Clear" ]
        ]
    ]

renderWindowItem :: WindowInfo -> H.ComponentHTML Action Slots Aff
renderWindowItem windowInfo =
  HH.button
    [ cls
        ( "window-menu-item"
            <> if windowInfo.active then " active" else ""
        )
    , HE.onClick \_ -> SelectWindow windowInfo.index
    ]
    [ HH.span
        [ cls "window-name" ]
        [ HH.text (windowLabel windowInfo) ]
    ]

renderSettings :: State -> H.ComponentHTML Action Slots Aff
renderSettings state =
  HH.div
    [ cls
        ( "settings-menu"
            <> if state.settingsOpen then "" else " hidden"
        )
    ]
    [ HH.label
        [ cls "field-label"
        , HP.attr (HH.AttrName "for") "server"
        ]
        [ HH.text "Agent daemon" ]
    , HH.div
        [ cls "settings-row" ]
        [ HH.input
            [ HP.id "server"
            , cls "grow"
            , HP.type_ HP.InputText
            , HP.placeholder "server (empty = local)"
            , HP.value state.server
            , HE.onValueInput SetServer
            ]
        , HH.button
            [ HE.onClick \_ -> SaveServer ]
            [ HH.text "Save" ]
        ]
    , HH.button
        [ cls "setting-button"
        , HE.onClick \_ -> ToggleTheme
        , HP.attr (HH.AttrName "aria-pressed")
            (if state.theme == "light" then "true" else "false")
        ]
        [ icon (if state.theme == "dark" then "sun" else "moon")
        , HH.span
            [ cls "button-label" ]
            [ HH.text
                (if state.theme == "dark" then "Light theme" else "Dark theme")
            ]
        ]
    , HH.label
        [ cls "field-label"
        , HP.attr (HH.AttrName "for") "font-size"
        ]
        [ HH.text "Font size" ]
    , HH.div
        [ cls "font-size-control" ]
        [ iconOnlyButton "Decrease font size" "minus"
            (AdjustTerminalFontSize (-1))
            Nothing
        , HH.input
            [ HP.id "font-size"
            , cls "number-input"
            , HP.type_ HP.InputNumber
            , HP.value (show state.terminalFontSize)
            , HP.attr (HH.AttrName "min") (show minTerminalFontSize)
            , HP.attr (HH.AttrName "max") (show maxTerminalFontSize)
            , HP.attr (HH.AttrName "step") "1"
            , HE.onValueInput SetTerminalFontSize
            ]
        , iconOnlyButton "Increase font size" "plus"
            (AdjustTerminalFontSize 1)
            Nothing
        ]
    ]

renderMain :: State -> H.ComponentHTML Action Slots Aff
renderMain _ =
  HH.main_
    [ HH.section
        [ cls "workspace" ]
        [ HH.div
            [ cls "terminal-wrap" ]
            [ HH.div
                [ HP.id "terminal" ]
                []
            ]
        ]
    ]

renderSessions :: State -> Array (H.ComponentHTML Action Slots Aff)
renderSessions state =
  if Array.null state.sessions then
    [ HH.div
        [ cls "session-row" ]
        [ HH.div
            [ cls "meta" ]
            [ HH.text "no sessions" ]
        ]
    ]
  else
    map (renderSession state) state.sessions

renderSession :: State -> Session -> H.ComponentHTML Action Slots Aff
renderSession state session =
  HH.div
    [ cls
        ( "session-row"
            <> if session.id == state.selectedSession then " active" else ""
        )
    ]
    [ HH.div
        [ cls "row-head" ]
        [ HH.div
            [ cls "name" ]
            [ HH.text (sessionLabel session) ]
        , HH.span
            [ cls "status-pill" ]
            [ HH.text session.state ]
        ]
    , HH.div
        [ cls "meta" ]
        [ HH.text (sessionMeta session) ]
    , HH.div
        [ cls "row-actions" ]
        ( ( if state.attachedSession == session.id then
              [ iconTextButton "" "Disconnect" "unlink" Disconnect ]
            else
              [ iconTextButton "primary" "Attach" "log-in"
                  (AttachSession session.id)
              ]
          )
            <>
              [ iconTextButton "danger-outline" "End" "power"
                  (OpenStopDialog session)
              ]
        )
    ]

renderConfirm :: State -> H.ComponentHTML Action Slots Aff
renderConfirm state =
  case state.pendingStop of
    Nothing ->
      HH.text ""
    Just session ->
      HH.div
        [ cls "modal-backdrop" ]
        [ HH.div
            [ cls "modal" ]
            [ HH.h2
                [ cls "modal-title" ]
                [ HH.text "End tmux session" ]
            , HH.p
                [ cls "modal-copy" ]
                [ HH.text
                    ( "Type \""
                        <> session.id
                        <> "\" to confirm. This will terminate tmux session \""
                        <> sessionLabel session
                        <> "\"."
                    )
                ]
            , HH.input
                [ HP.id "confirm-input"
                , HP.type_ HP.InputText
                , HP.attr (HH.AttrName "autocomplete") "off"
                , HP.placeholder session.id
                , HP.value state.confirmInput
                , HE.onValueInput SetConfirmInput
                ]
            , HH.div
                [ cls "row-actions" ]
                [ HH.button
                    [ HE.onClick \_ -> CloseStopDialog ]
                    [ HH.text "Cancel" ]
                , HH.button
                    [ cls "danger"
                    , HP.disabled (state.confirmInput /= session.id)
                    , HE.onClick \_ -> ConfirmStopSession
                    ]
                    [ HH.text "End session" ]
                ]
            ]
        ]

handleAction
  :: forall o
   . Action
  -> H.HalogenM State Action Slots o Aff Unit
handleAction = case _ of
  Initialize -> do
    savedServer <- liftEffect $ Browser.loadItem "agent-daemon-server"
    savedTheme <- liftEffect $ Browser.loadItem "agent-daemon-theme"
    savedFontSize <- liftEffect $ Browser.loadItem "agent-daemon-terminal-font-size"
    savedPastes <- liftEffect $ Browser.loadPastes pasteStorageKey
    let theme = if savedTheme == "light" then "light" else "dark"
    let terminalFontSize = parseTerminalFontSize savedFontSize
    liftEffect $ Browser.setDocumentTheme theme
    { emitter, listener } <- liftEffect HS.create
    terminal <- liftEffect $ Terminal.createTerminal theme terminalFontSize
      { onOpen: \label ->
          HS.notify listener (HandleTerminal (TerminalOpened label))
      , onClose:
          HS.notify listener (HandleTerminal TerminalClosed)
      , onError:
          HS.notify listener (HandleTerminal TerminalErrored)
      , onLinkOpened:
          HS.notify listener (HandleTerminal TerminalLinkOpened)
      , onLinkBlocked:
          HS.notify listener (HandleTerminal TerminalLinkBlocked)
      , onScrollGesture: \lines ->
          HS.notify listener (HandleTerminal (TerminalScrollGesture lines))
      }
    void $ H.subscribe emitter
    H.modify_ _
      { server = savedServer
      , theme = theme
      , terminalFontSize = terminalFontSize
      , pastes = savedPastes
      , terminal = Just terminal
      }
    liftEffect $ Terminal.mountTerminal terminal "terminal"
    syncUi
    handleAction RefreshSessions

  RefreshSessions -> do
    state <- H.get
    base <- liftEffect $ Browser.apiBase state.server
    result <- liftAff $ attempt (Api.fetchSessions base)
    case result of
      Left err ->
        H.modify_ _ { status = "error: " <> message err }
      Right sessions -> do
        let
          selected =
            if Array.any (\s -> s.id == state.selectedSession) sessions then
              state.selectedSession
            else
              maybeSessionId (Array.head sessions)
          attached =
            if Array.any (\s -> s.id == state.attachedSession) sessions then
              state.attachedSession
            else
              ""
          shouldAutoAttach =
            not state.autoAttachAttempted
              && attached == ""
              && selected /= ""
        H.modify_ _
          { sessions = sessions
          , selectedSession = selected
          , attachedSession = attached
          , windows = if attached == "" then [] else state.windows
          , autoAttachAttempted =
              state.autoAttachAttempted || not (Array.null sessions)
          , sessionMenuOpen =
              if Array.null sessions then false else state.sessionMenuOpen
          , windowMenuOpen =
              if attached == "" then false else state.windowMenuOpen
          , terminalMenuOpen =
              if attached == "" then false else state.terminalMenuOpen
          , pasteMenuOpen =
              if attached == "" then false else state.pasteMenuOpen
          , status = show (Array.length sessions) <> " session(s)"
          }
        if shouldAutoAttach then
          handleAction (AttachSession selected)
        else do
          when (attached /= "") do
            refreshWindows attached
          syncUi

  SetServer value ->
    H.modify_ _ { server = value }

  SaveServer -> do
    state <- H.get
    liftEffect $ Browser.saveItem "agent-daemon-server" state.server
    H.modify_ _
      { status = "server saved"
      , settingsOpen = false
      , terminalMenuOpen = false
      , pasteMenuOpen = false
      }
    syncUi

  ToggleTheme -> do
    state <- H.get
    let next = if state.theme == "dark" then "light" else "dark"
    liftEffect $ Browser.saveItem "agent-daemon-theme" next
    liftEffect $ Browser.setDocumentTheme next
    case state.terminal of
      Nothing -> pure unit
      Just terminal -> liftEffect $ Terminal.setTerminalTheme terminal next
    H.modify_ _ { theme = next }
    syncUi

  SetTerminalFontSize value -> do
    state <- H.get
    let next = fromMaybe state.terminalFontSize (Int.fromString value)
    applyTerminalFontSize next

  AdjustTerminalFontSize delta -> do
    state <- H.get
    applyTerminalFontSize (state.terminalFontSize + delta)

  ToggleSettings -> do
    state <- H.get
    H.modify_ _
      { settingsOpen = not state.settingsOpen
      , sessionMenuOpen = false
      , windowMenuOpen = false
      , terminalMenuOpen = false
      , pasteMenuOpen = false
      }
    syncUi

  ToggleSessionMenu -> do
    state <- H.get
    H.modify_ _
      { sessionMenuOpen = not state.sessionMenuOpen
      , windowMenuOpen = false
      , terminalMenuOpen = false
      , pasteMenuOpen = false
      , settingsOpen = false
      }
    syncUi

  ToggleWindowMenu -> do
    state <- H.get
    when (state.attachedSession /= "") do
      H.modify_ _
        { windowMenuOpen = not state.windowMenuOpen
        , sessionMenuOpen = false
        , terminalMenuOpen = false
        , pasteMenuOpen = false
        , settingsOpen = false
        }
      syncUi

  ToggleTerminalMenu -> do
    state <- H.get
    when (state.attachedSession /= "") do
      H.modify_ _
        { terminalMenuOpen = not state.terminalMenuOpen
        , sessionMenuOpen = false
        , windowMenuOpen = false
        , pasteMenuOpen = false
        , settingsOpen = false
        }
      syncUi

  TogglePasteMenu -> do
    state <- H.get
    when (state.attachedSession /= "") do
      H.modify_ _
        { pasteMenuOpen = not state.pasteMenuOpen
        , sessionMenuOpen = false
        , windowMenuOpen = false
        , terminalMenuOpen = false
        , settingsOpen = false
        }
      syncUi

  SendEscape ->
    sendTerminalAction Terminal.sendEscape

  SendCtrlB ->
    sendTerminalAction Terminal.sendCtrlB

  SendCtrlBCommand ->
    sendTerminalAction Terminal.sendCtrlBCommand

  SendLive ->
    returnAttachedSessionLive

  SetPasteName value ->
    H.modify_ _ { pasteName = value }

  SetPasteBody value ->
    H.modify_ _ { pasteBody = value }

  SavePaste ->
    savePasteSnippet

  ClearPaste -> do
    H.modify_ _
      { pasteName = ""
      , pasteBody = ""
      }
    syncUi

  EditPaste name -> do
    state <- H.get
    case Array.find (\paste -> paste.name == name) state.pastes of
      Nothing -> pure unit
      Just paste ->
        H.modify_ _
          { pasteName = paste.name
          , pasteBody = paste.body
          , pasteMenuOpen = true
          }
    syncUi

  DeletePaste name ->
    deletePasteSnippet name

  PasteNamed name -> do
    state <- H.get
    case Array.find (\paste -> paste.name == name) state.pastes of
      Nothing ->
        H.modify_ _ { status = "paste not found" }
      Just paste ->
        pasteTerminalText paste.name paste.body

  PasteDraft -> do
    state <- H.get
    pasteTerminalText "draft" state.pasteBody

  OpenStopDialog session -> do
    H.modify_ _
      { pendingStop = Just session
      , confirmInput = ""
      , sessionMenuOpen = false
      , windowMenuOpen = false
      , terminalMenuOpen = false
      , pasteMenuOpen = false
      , settingsOpen = false
      }
    syncUi

  CloseStopDialog -> do
    H.modify_ _
      { pendingStop = Nothing
      , confirmInput = ""
      }
    syncUi

  SetConfirmInput value ->
    H.modify_ _ { confirmInput = value }

  ConfirmStopSession -> do
    state <- H.get
    case state.pendingStop of
      Nothing ->
        pure unit
      Just session ->
        when (state.confirmInput == session.id) do
          when (state.attachedSession == session.id) do
            case state.terminal of
              Nothing -> pure unit
              Just terminal -> liftEffect $ Terminal.disconnectTerminal terminal
          base <- liftEffect $ Browser.apiBase state.server
          result <- liftAff $ attempt (Api.deleteSession base session.id)
          case result of
            Left err ->
              H.modify_ _ { status = "error: " <> message err }
            Right _ -> do
              H.modify_ _
                { pendingStop = Nothing
                , confirmInput = ""
                , selectedSession =
                    if state.selectedSession == session.id then ""
                    else state.selectedSession
                , attachedSession =
                    if state.attachedSession == session.id then ""
                    else state.attachedSession
                , windows =
                    if state.attachedSession == session.id then []
                    else state.windows
                , sessionMenuOpen = false
                , terminalMenuOpen = false
                , pasteMenuOpen = false
                , windowMenuOpen =
                    if state.attachedSession == session.id then false
                    else state.windowMenuOpen
                , status = "stopped: " <> session.id
                }
              handleAction RefreshSessions
              H.modify_ _ { status = "stopped: " <> session.id }
              syncUi

  AttachSession sessionId -> do
    state <- H.get
    case state.terminal of
      Nothing ->
        H.modify_ _ { status = "terminal not ready" }
      Just terminal -> do
        url <- liftEffect $ Browser.sessionTerminalWsUrl state.server sessionId
        let label = "session " <> sessionId
        liftEffect $ Terminal.attachTerminal terminal url label
        H.modify_ _
          { selectedSession = sessionId
          , attachedSession = sessionId
          , windows = []
          , sessionMenuOpen = false
          , windowMenuOpen = false
          , terminalMenuOpen = false
          , pasteMenuOpen = false
          , status = "connecting: " <> label
          }
        refreshWindows sessionId
        syncUi

  ChooseSession sessionId -> do
    state <- H.get
    if state.attachedSession == sessionId then do
      H.modify_ _
        { selectedSession = sessionId
        , sessionMenuOpen = false
        , terminalMenuOpen = false
        , pasteMenuOpen = false
        }
      syncUi
    else
      handleAction (AttachSession sessionId)

  CreateWindow -> do
    state <- H.get
    if state.attachedSession == "" then
      H.modify_ _
        { windowMenuOpen = false
        , terminalMenuOpen = false
        , pasteMenuOpen = false
        }
    else do
      base <- liftEffect $ Browser.apiBase state.server
      result <- liftAff $ attempt (Api.createWindow base state.attachedSession)
      case result of
        Left err ->
          H.modify_ _
            { status = "error: " <> message err
            , windowMenuOpen = false
            , terminalMenuOpen = false
            , pasteMenuOpen = false
            }
        Right windowInfo -> do
          H.modify_ _
            { status = "window: " <> windowLabel windowInfo
            , windowMenuOpen = false
            , terminalMenuOpen = false
            , pasteMenuOpen = false
            }
          refreshWindows state.attachedSession
      syncUi

  SelectWindow index -> do
    state <- H.get
    if state.attachedSession == "" then
      H.modify_ _
        { windowMenuOpen = false
        , terminalMenuOpen = false
        , pasteMenuOpen = false
        }
    else do
      base <- liftEffect $ Browser.apiBase state.server
      result <- liftAff $ attempt (Api.selectWindow base state.attachedSession index)
      case result of
        Left err ->
          H.modify_ _
            { status = "error: " <> message err
            , windowMenuOpen = false
            , terminalMenuOpen = false
            , pasteMenuOpen = false
            }
        Right _ -> do
          H.modify_ _
            { status = "window: " <> selectedWindowLabel index state.windows
            , windowMenuOpen = false
            , terminalMenuOpen = false
            , pasteMenuOpen = false
            }
          refreshWindows state.attachedSession
      syncUi

  Disconnect -> do
    state <- H.get
    case state.terminal of
      Nothing -> pure unit
      Just terminal -> liftEffect $ Terminal.disconnectTerminal terminal
    H.modify_ _
      { attachedSession = ""
      , windows = []
      , sessionMenuOpen = false
      , windowMenuOpen = false
      , terminalMenuOpen = false
      , pasteMenuOpen = false
      , status = "disconnected"
      }
    syncUi

  HandleTerminal event -> do
    case event of
      TerminalOpened label ->
        H.modify_ _ { status = "attached: " <> label }
      TerminalClosed ->
        H.modify_ _
          { attachedSession = ""
          , windows = []
          , sessionMenuOpen = false
          , windowMenuOpen = false
          , terminalMenuOpen = false
          , pasteMenuOpen = false
          , status = "disconnected"
          }
      TerminalErrored ->
        H.modify_ _
          { status = "connection error"
          , terminalMenuOpen = false
          , pasteMenuOpen = false
          }
      TerminalLinkOpened ->
        H.modify_ _ { status = "opened link" }
      TerminalLinkBlocked ->
        H.modify_ _ { status = "link blocked by browser" }
      TerminalScrollGesture lines ->
        scrollAttachedSession lines
    case event of
      TerminalScrollGesture _ -> pure unit
      _ -> syncUi

sendTerminalAction
  :: forall o
   . (Terminal.TerminalController -> Effect Unit)
  -> H.HalogenM State Action Slots o Aff Unit
sendTerminalAction send = do
  state <- H.get
  case state.terminal of
    Nothing ->
      H.modify_ _
        { status = "terminal not ready"
        , terminalMenuOpen = false
        , pasteMenuOpen = false
        }
    Just terminal -> do
      liftEffect $ send terminal
      H.modify_ _ { terminalMenuOpen = false }
  syncUi

savePasteSnippet
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
savePasteSnippet = do
  state <- H.get
  if state.pasteName == "" || state.pasteBody == "" then
    H.modify_ _ { status = "paste needs name and text" }
  else do
    let
      paste = { name: state.pasteName, body: state.pasteBody }
      pastes = upsertPaste paste state.pastes
    liftEffect $ Browser.savePastes pasteStorageKey pastes
    H.modify_ _
      { pastes = pastes
      , status = "saved paste: " <> state.pasteName
      }
  syncUi

deletePasteSnippet
  :: forall o
   . String
  -> H.HalogenM State Action Slots o Aff Unit
deletePasteSnippet name = do
  state <- H.get
  let pastes = Array.filter (\paste -> paste.name /= name) state.pastes
  liftEffect $ Browser.savePastes pasteStorageKey pastes
  H.modify_ _
    { pastes = pastes
    , pasteName = if state.pasteName == name then "" else state.pasteName
    , pasteBody = if state.pasteName == name then "" else state.pasteBody
    , status = "deleted paste: " <> name
    }
  syncUi

pasteTerminalText
  :: forall o
   . String
  -> String
  -> H.HalogenM State Action Slots o Aff Unit
pasteTerminalText label body = do
  state <- H.get
  if body == "" then
    H.modify_ _ { status = "nothing to paste" }
  else
    case state.terminal of
      Nothing ->
        H.modify_ _
          { status = "terminal not ready"
          , pasteMenuOpen = false
          }
      Just terminal -> do
        liftEffect $ Terminal.sendText terminal body
        H.modify_ _
          { status = "pasted: " <> label
          , pasteMenuOpen = false
          }
  syncUi

returnAttachedSessionLive
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
returnAttachedSessionLive = do
  state <- H.get
  if state.attachedSession == "" then
    H.modify_ _ { terminalMenuOpen = false }
  else do
    base <- liftEffect $ Browser.apiBase state.server
    result <- liftAff $ attempt (Api.liveSession base state.attachedSession)
    case result of
      Left err ->
        H.modify_ _
          { status = "error: " <> message err
          , terminalMenuOpen = false
          }
      Right _ ->
        H.modify_ _
          { status = "live"
          , terminalMenuOpen = false
          }
  syncUi

scrollAttachedSession
  :: forall o
   . Int
  -> H.HalogenM State Action Slots o Aff Unit
scrollAttachedSession lines = do
  state <- H.get
  when (lines /= 0 && state.attachedSession /= "") do
    base <- liftEffect $ Browser.apiBase state.server
    result <- liftAff $ attempt (Api.scrollSession base state.attachedSession lines)
    case result of
      Left _ -> pure unit
      Right _ -> pure unit

refreshWindows
  :: forall o
   . String
  -> H.HalogenM State Action Slots o Aff Unit
refreshWindows sessionId = do
  state <- H.get
  base <- liftEffect $ Browser.apiBase state.server
  result <- liftAff $ attempt (Api.fetchWindows base sessionId)
  case result of
    Left err ->
      H.modify_ _
        { windows = []
        , windowMenuOpen = false
        , status = "error: " <> message err
        }
    Right windows ->
      H.modify_ _
        { windows = windows
        }

syncUi
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
syncUi = do
  terminal <- H.gets _.terminal
  liftEffect $ Browser.afterRender do
    Browser.renderIcons
    case terminal of
      Nothing -> pure unit
      Just term -> Terminal.fitTerminal term

sessionLabel :: Session -> String
sessionLabel session =
  if session.tmuxName == "" then session.id else session.tmuxName

sessionMeta :: Session -> String
sessionMeta session =
  if session.currentPath == "" then session.tmuxName else session.currentPath

maybeSessionId :: Maybe Session -> String
maybeSessionId = case _ of
  Nothing -> ""
  Just session -> session.id

activeSessionLabel :: State -> String
activeSessionLabel state =
  case Array.find (\session -> session.id == target) state.sessions of
    Nothing -> "Sessions"
    Just session -> sessionLabel session
  where
  target =
    if state.attachedSession == "" then state.selectedSession
    else state.attachedSession

activeWindowLabel :: State -> String
activeWindowLabel state =
  case Array.find _.active state.windows of
    Nothing -> "Window"
    Just windowInfo -> windowLabel windowInfo

selectedWindowLabel :: Int -> Array WindowInfo -> String
selectedWindowLabel index windows =
  case Array.find (\windowInfo -> windowInfo.index == index) windows of
    Nothing -> show index
    Just windowInfo -> windowLabel windowInfo

windowLabel :: WindowInfo -> String
windowLabel windowInfo =
  if windowInfo.name == "" then "window " <> show windowInfo.index
  else windowInfo.name

pastePreview :: String -> String
pastePreview = identity

upsertPaste :: PasteSnippet -> Array PasteSnippet -> Array PasteSnippet
upsertPaste paste pastes =
  if Array.any (\candidate -> candidate.name == paste.name) pastes then
    map
      ( \candidate ->
          if candidate.name == paste.name then paste else candidate
      )
      pastes
  else
    pastes <> [ paste ]

pasteStorageKey :: String
pasteStorageKey = "agent-daemon-paste-snippets"

defaultTerminalFontSize :: Int
defaultTerminalFontSize = 12

minTerminalFontSize :: Int
minTerminalFontSize = 8

maxTerminalFontSize :: Int
maxTerminalFontSize = 24

parseTerminalFontSize :: String -> Int
parseTerminalFontSize =
  clampTerminalFontSize
    <<< fromMaybe defaultTerminalFontSize
    <<< Int.fromString

clampTerminalFontSize :: Int -> Int
clampTerminalFontSize value
  | value < minTerminalFontSize = minTerminalFontSize
  | value > maxTerminalFontSize = maxTerminalFontSize
  | otherwise = value

applyTerminalFontSize
  :: forall o
   . Int
  -> H.HalogenM State Action Slots o Aff Unit
applyTerminalFontSize value = do
  state <- H.get
  let next = clampTerminalFontSize value
  liftEffect $
    Browser.saveItem "agent-daemon-terminal-font-size" (show next)
  case state.terminal of
    Nothing -> pure unit
    Just terminal -> liftEffect $ Terminal.setTerminalFontSize terminal next
  H.modify_ _ { terminalFontSize = next }
  syncUi

iconOnlyButton
  :: String
  -> String
  -> Action
  -> Maybe String
  -> H.ComponentHTML Action Slots Aff
iconOnlyButton label iconName action expanded =
  HH.button
    ( [ cls "icon-button"
      , HP.title label
      , HP.attr (HH.AttrName "aria-label") label
      , HE.onClick \_ -> action
      ]
        <> case expanded of
          Nothing -> []
          Just value -> [ HP.attr (HH.AttrName "aria-expanded") value ]
    )
    [ icon iconName ]

iconTextButton
  :: String
  -> String
  -> String
  -> Action
  -> H.ComponentHTML Action Slots Aff
iconTextButton className label iconName action =
  HH.button
    [ cls className
    , HE.onClick \_ -> action
    ]
    [ icon iconName
    , HH.span
        [ cls "button-label" ]
        [ HH.text label ]
    ]

icon :: String -> H.ComponentHTML Action Slots Aff
icon name =
  HH.span
    [ HP.attr (HH.AttrName "data-lucide-slot") name
    , HP.attr (HH.AttrName "data-fallback") ""
    ]
    []

cls
  :: forall r i
   . String
  -> HH.IProp (class :: String | r) i
cls =
  HP.class_ <<< HH.ClassName
