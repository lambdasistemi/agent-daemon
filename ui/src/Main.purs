module Main where

import Prelude

import AgentDaemon.Api as Api
import AgentDaemon.FFI.Browser as Browser
import AgentDaemon.FFI.Terminal as Terminal
import AgentDaemon.Types (CloseExecution, ClosePreview, PasteSnippet, Session, WindowInfo)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, isNothing)
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

data CloseScope
  = ClosePane
  | CloseWindow

type CloseDialog =
  { scope :: CloseScope
  , sessionId :: String
  , consequence :: String
  , confirmation :: String
  }

type ReconnectNotice =
  { sessionId :: String
  , status :: String
  }

type CommandDeckLatches =
  { ctrl :: Boolean
  , alt :: Boolean
  , shift :: Boolean
  , tmux :: Boolean
  }

emptyCommandDeckLatches :: CommandDeckLatches
emptyCommandDeckLatches =
  { ctrl: false
  , alt: false
  , shift: false
  , tmux: false
  }

toggleCommandDeckLatch
  :: CommandDeckLatches -> String -> CommandDeckLatches
toggleCommandDeckLatch latches latch =
  case latch of
    "ctrl" -> latches { ctrl = not latches.ctrl }
    "alt" -> latches { alt = not latches.alt }
    "shift" -> latches { shift = not latches.shift }
    "tmux" -> latches { tmux = not latches.tmux }
    _ -> latches

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
  , terminalSelectionMode :: Boolean
  , pasteMenuOpen :: Boolean
  , pastes :: Array PasteSnippet
  , pasteName :: String
  , pasteBody :: String
  , pasteEnter :: Boolean
  , pasteEditorOpen :: Boolean
  , autoAttachAttempted :: Boolean
  , pendingStop :: Maybe Session
  , confirmInput :: String
  , pendingClose :: Maybe CloseDialog
  , closePreviewLoading :: Boolean
  , closeExecuting :: Boolean
  , endedNotice :: Maybe String
  , reconnectNotice :: Maybe ReconnectNotice
  , terminal :: Maybe Terminal.TerminalController
  , commandDeckLatches :: CommandDeckLatches
  }

data TerminalEvent
  = TerminalOpened String
  | TerminalClosed
  | TerminalErrored
  | TerminalLinkOpened
  | TerminalLinkBlocked
  | TerminalScrollGesture Int
  | TerminalCommandDeckConsumed

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
  | ToggleCommandDeckLatch String
  | CopyTerminalText
  | ToggleTerminalSelectionMode
  | TogglePasteMenu
  | SetPasteName String
  | SetPasteBody String
  | TogglePasteEnter
  | InsertPasteNewline
  | NewPaste
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
  | OpenCloseCurrent CloseScope
  | CancelCloseCurrent
  | ConfirmCloseCurrent
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
      , terminalSelectionMode: false
      , pasteMenuOpen: false
      , pastes: []
      , pasteName: ""
      , pasteBody: ""
      , pasteEnter: false
      , pasteEditorOpen: false
      , autoAttachAttempted: false
      , pendingStop: Nothing
      , confirmInput: ""
      , pendingClose: Nothing
      , closePreviewLoading: false
      , closeExecuting: false
      , endedNotice: Nothing
      , reconnectNotice: Nothing
      , terminal: Nothing
      , commandDeckLatches: emptyCommandDeckLatches
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
    , renderActionDock state
    , renderConfirm state
    , renderCloseConfirm state
    ]

renderHeader :: State -> H.ComponentHTML Action Slots Aff
renderHeader state =
  HH.header
    [ cls "app-header" ]
    [ HH.div
        [ cls "identity-bar" ]
        [ HH.h1_ [ HH.text "tmux-ws" ]
        , HH.span
            [ HP.id "status"
            , cls
                ( "connection-badge "
                    <> if state.attachedSession == "" then "offline" else "online"
                )
            ]
            [ HH.span
                [ cls "connection-dot" ]
                []
            , HH.span
                [ cls "status-label" ]
                [ HH.text state.status ]
            ]
        ]
    , HH.div
        [ cls "context-bar" ]
        [ renderSessionSwitcher state
        , renderWindowSwitcher state
        ]
    , HH.nav
        [ cls "utility-links"
        , HP.attr (HH.AttrName "aria-label") "Project links"
        ]
        [ iconTextLink "Repository" "github" "https://github.com/lambdasistemi/tmux-ws"
        , iconTextLink "Documentation" "book-open" "https://lambdasistemi.github.io/tmux-ws/docs/"
        ]
    ]

renderActionDock :: State -> H.ComponentHTML Action Slots Aff
renderActionDock state =
  HH.footer
    [ cls "action-dock"
    , HP.attr (HH.AttrName "aria-label") "Workspace actions"
    ]
    [ dockButton "Refresh" "refresh-cw" RefreshSessions Nothing false false
    , HH.div
        [ cls "terminal-actions-shell" ]
        [ dockButton "Terminal" "keyboard" ToggleTerminalMenu
            (Just (if state.terminalMenuOpen then "true" else "false"))
            (state.terminalMenuOpen || state.terminalSelectionMode)
            (state.attachedSession == "")
        , renderTerminalMenu state
        ]
    , HH.div
        [ cls "paste-actions-shell" ]
        [ dockButton "Paste" "clipboard-list" TogglePasteMenu
            (Just (if state.pasteMenuOpen then "true" else "false"))
            state.pasteMenuOpen
            (state.attachedSession == "")
        , renderPasteMenu state
        ]
    , HH.div
        [ cls "settings-shell" ]
        [ dockButton "Settings" "settings" ToggleSettings
            (Just (if state.settingsOpen then "true" else "false"))
            state.settingsOpen
            false
        , renderSettings state
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
  HH.div
    [ cls "window-switcher" ]
    [ HH.button
        [ cls "window-button"
        , HP.title "Switch tmux window"
        , HP.attr (HH.AttrName "aria-label") "Switch tmux window"
        , HP.attr (HH.AttrName "aria-expanded")
            (if state.windowMenuOpen then "true" else "false")
        , HP.disabled (state.attachedSession == "")
        , HE.onClick \_ -> ToggleWindowMenu
        ]
        [ HH.span
            [ cls "menu-prefix" ]
            [ HH.text "Window" ]
        , HH.span
            [ cls "button-label window-label" ]
            [ HH.text
                ( if state.attachedSession == "" then "No window"
                  else activeWindowLabel state
                )
            ]
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

renderTerminalMenu :: State -> H.ComponentHTML Action Slots Aff
renderTerminalMenu state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls
          ( "terminal-menu"
              <> if state.terminalMenuOpen then "" else " hidden"
          )
      ]
      [ HH.button
          [ cls "terminal-menu-item"
          , HE.onClick \_ -> CopyTerminalText
          ]
          [ icon "copy"
          , HH.text "Copy"
          ]
      , HH.button
          [ cls
              ( "terminal-menu-item"
                  <> if state.terminalSelectionMode then " active" else ""
              )
          , HP.attr (HH.AttrName "aria-pressed")
              (if state.terminalSelectionMode then "true" else "false")
          , HE.onClick \_ -> ToggleTerminalSelectionMode
          ]
          [ icon "scan-text"
          , HH.text "Select"
          ]
      , HH.button
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

renderPasteMenu :: State -> H.ComponentHTML Action Slots Aff
renderPasteMenu state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls
          ( "paste-menu"
              <> if state.pasteMenuOpen then "" else " hidden"
          )
      ]
      ( renderPasteItems state
          <>
            if state.pasteEditorOpen then
              [ renderPasteEditor state ]
            else
              [ renderPasteNewButton ]
      )

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
        , if paste.enter then
            HH.span
              [ cls "paste-badge" ]
              [ HH.text "Enter" ]
          else
            HH.text ""
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

renderPasteNewButton :: H.ComponentHTML Action Slots Aff
renderPasteNewButton =
  HH.button
    [ cls "paste-new-button"
    , HE.onClick \_ -> NewPaste
    ]
    [ icon "plus"
    , HH.text "New"
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
        [ cls "paste-options" ]
        [ HH.button
            [ cls "paste-option-button"
            , HE.onClick \_ -> InsertPasteNewline
            ]
            [ icon "corner-down-left"
            , HH.text "New line"
            ]
        , HH.button
            [ cls
                ( "paste-option-button"
                    <> if state.pasteEnter then " active" else ""
                )
            , HP.attr (HH.AttrName "aria-pressed")
                (if state.pasteEnter then "true" else "false")
            , HE.onClick \_ -> TogglePasteEnter
            ]
            [ icon "send-horizontal"
            , HH.text "Enter"
            ]
        ]
    , HH.div
        [ cls "paste-editor-actions" ]
        [ HH.button
            [ HE.onClick \_ -> PasteDraft
            , HP.disabled (state.pasteBody == "" && not state.pasteEnter)
            ]
            [ icon "send"
            , HH.text "Paste"
            ]
        , HH.button
            [ HE.onClick \_ -> SavePaste
            , HP.disabled
                ( state.pasteName == ""
                    || (state.pasteBody == "" && not state.pasteEnter)
                )
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
    , if state.attachedSession == "" then
        HH.text ""
      else
        HH.div
          [ cls "destructive-settings-group" ]
          [ HH.div
              [ cls "section-title" ]
              [ HH.text "Current tmux context" ]
          , HH.p
              [ cls "destructive-settings-copy" ]
              [ HH.text "The server confirms what will close before either action runs." ]
          , HH.button
              [ cls "close-current-action danger-outline"
              , HP.disabled state.closePreviewLoading
              , HE.onClick \_ -> OpenCloseCurrent ClosePane
              ]
              [ icon "trash-2"
              , HH.text "Close this pane"
              ]
          , HH.button
              [ cls "close-current-action danger-outline"
              , HP.disabled state.closePreviewLoading
              , HE.onClick \_ -> OpenCloseCurrent CloseWindow
              ]
              [ icon "trash-2"
              , HH.text "Close this window"
              ]
          , if state.closePreviewLoading then
              HH.p
                [ cls "close-preview-status"
                , HP.attr (HH.AttrName "role") "status"
                ]
                [ HH.text "Loading close consequence…" ]
            else
              HH.text ""
          ]
    ]

renderMain :: State -> H.ComponentHTML Action Slots Aff
renderMain state =
  HH.main_
    [ HH.section
        [ cls "workspace" ]
        [ HH.div
            [ cls "terminal-wrap" ]
            [ HH.div
                [ HP.id "terminal" ]
                []
            , renderCommandDeck state
            ]
        ]
    ]

renderCommandDeck :: State -> H.ComponentHTML Action Slots Aff
renderCommandDeck state =
  if state.attachedSession == "" then
    HH.text ""
  else
    HH.div
      [ cls "command-deck"
      , HP.attr (HH.AttrName "aria-label") "Terminal command deck"
      ]
      [ commandDeckKey "Esc" "Esc"
      , commandDeckKey "Tab" "Tab"
      , commandDeckLatch state "ctrl" "Ctrl"
      , commandDeckLatch state "alt" "Alt"
      , commandDeckLatch state "shift" "Shift"
      , commandDeckLatch state "tmux" "Tmux"
      , commandDeckKey "ArrowLeft" "Left"
      , commandDeckKey "ArrowUp" "Up"
      , commandDeckKey "ArrowDown" "Down"
      , commandDeckKey "ArrowRight" "Right"
      , commandDeckKey "Enter" "Enter"
      ]

commandDeckKey :: String -> String -> H.ComponentHTML Action Slots Aff
commandDeckKey key label =
  HH.button
    [ cls "command-deck-control command-deck-key"
    , HP.attr (HH.AttrName "data-command-deck-control") ""
    , HP.attr (HH.AttrName "data-command-deck-key") key
    , HP.attr (HH.AttrName "aria-label") label
    ]
    [ HH.text label ]

commandDeckLatch :: State -> String -> String -> H.ComponentHTML Action Slots Aff
commandDeckLatch state latch label =
  let
    armed = case latch of
      "ctrl" -> state.commandDeckLatches.ctrl
      "alt" -> state.commandDeckLatches.alt
      "shift" -> state.commandDeckLatches.shift
      "tmux" -> state.commandDeckLatches.tmux
      _ -> false
  in
    HH.button
      [ cls
          ( "command-deck-control command-deck-latch"
              <> if armed then " armed" else ""
          )
      , HP.attr (HH.AttrName "data-command-deck-control") ""
      , HP.attr (HH.AttrName "aria-label") label
      , HP.attr (HH.AttrName "aria-pressed") (if armed then "true" else "false")
      , HE.onClick \_ -> ToggleCommandDeckLatch latch
      ]
      [ HH.text label ]

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

renderCloseConfirm :: State -> H.ComponentHTML Action Slots Aff
renderCloseConfirm state =
  case state.pendingClose of
    Nothing ->
      HH.text ""
    Just pending ->
      HH.div
        [ cls "close-sheet-backdrop" ]
        [ HH.div
            [ cls "close-sheet"
            , HP.attr (HH.AttrName "role") "dialog"
            , HP.attr (HH.AttrName "aria-modal") "true"
            , HP.attr (HH.AttrName "aria-labelledby") "close-sheet-title"
            , HP.attr (HH.AttrName "aria-describedby") "close-sheet-copy"
            ]
            [ HH.h2
                [ cls "close-sheet-title"
                , HP.id "close-sheet-title"
                ]
                [ HH.text (closeActionLabel pending.scope) ]
            , HH.p
                [ cls "close-sheet-copy"
                , HP.id "close-sheet-copy"
                ]
                [ HH.text (closeConsequenceCopy pending.scope pending.consequence) ]
            , HH.div
                [ cls "close-sheet-actions" ]
                [ HH.button
                    [ cls "close-sheet-cancel"
                    , HP.disabled state.closeExecuting
                    , HE.onClick \_ -> CancelCloseCurrent
                    ]
                    [ HH.text "Cancel" ]
                , HH.button
                    [ cls "close-sheet-submit danger"
                    , HP.disabled state.closeExecuting
                    , HE.onClick \_ -> ConfirmCloseCurrent
                    ]
                    [ HH.text (closeActionLabel pending.scope) ]
                ]
            , if state.closeExecuting then
                HH.p
                  [ cls "close-execute-status"
                  , HP.attr (HH.AttrName "role") "status"
                  ]
                  [ HH.text "Closing the server-confirmed current context…" ]
              else
                HH.text ""
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
      , onCommandDeckConsumed:
          HS.notify listener (HandleTerminal TerminalCommandDeckConsumed)
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
          , terminalSelectionMode =
              if attached == "" then false else state.terminalSelectionMode
          , pasteMenuOpen =
              if attached == "" then false else state.pasteMenuOpen
          , status = fromMaybe
              (show (Array.length sessions) <> " session(s)")
              state.endedNotice
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

  ToggleCommandDeckLatch latch -> do
    state <- H.get
    let latches = toggleCommandDeckLatch state.commandDeckLatches latch
    case state.terminal of
      Nothing -> pure unit
      Just terminal -> liftEffect $
        Terminal.setCommandDeckLatches terminal latches.ctrl latches.alt latches.shift latches.tmux
    H.modify_ _ { commandDeckLatches = latches }
    syncUi

  CopyTerminalText ->
    copyTerminalText

  ToggleTerminalSelectionMode ->
    toggleTerminalSelectionMode

  SetPasteName value ->
    H.modify_ _ { pasteName = value }

  SetPasteBody value ->
    H.modify_ _ { pasteBody = value }

  TogglePasteEnter -> do
    state <- H.get
    H.modify_ _ { pasteEnter = not state.pasteEnter }
    syncUi

  InsertPasteNewline -> do
    state <- H.get
    H.modify_ _ { pasteBody = state.pasteBody <> "\n" }
    syncUi

  NewPaste -> do
    H.modify_ _
      { pasteName = ""
      , pasteBody = ""
      , pasteEnter = false
      , pasteEditorOpen = true
      }
    syncUi

  SavePaste ->
    savePasteSnippet

  ClearPaste -> do
    H.modify_ _
      { pasteName = ""
      , pasteBody = ""
      , pasteEnter = false
      , pasteEditorOpen = true
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
          , pasteEnter = paste.enter
          , pasteMenuOpen = true
          , pasteEditorOpen = true
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
        pasteTerminalText paste.name paste.body paste.enter

  PasteDraft -> do
    state <- H.get
    pasteTerminalText "draft" state.pasteBody state.pasteEnter

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
              Just terminal -> liftEffect do
                Terminal.setSelectionMode terminal false
                Terminal.disconnectTerminal terminal
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
                , terminalSelectionMode =
                    if state.attachedSession == session.id then false
                    else state.terminalSelectionMode
                , pasteMenuOpen = false
                , windowMenuOpen =
                    if state.attachedSession == session.id then false
                    else state.windowMenuOpen
                , status = "stopped: " <> session.id
                }
              handleAction RefreshSessions
              H.modify_ _ { status = "stopped: " <> session.id }
              syncUi

  OpenCloseCurrent scope ->
    openCloseCurrent scope

  CancelCloseCurrent -> do
    state <- H.get
    when (not state.closeExecuting) do
      H.modify_ _ { pendingClose = Nothing }
      syncUi

  ConfirmCloseCurrent ->
    confirmCloseCurrent

  AttachSession sessionId -> do
    state <- H.get
    case state.terminal of
      Nothing ->
        H.modify_ _ { status = "terminal not ready" }
      Just terminal -> do
        url <- liftEffect $ Browser.sessionTerminalWsUrl state.server sessionId
        let label = "session " <> sessionId
        liftEffect $ Terminal.setSelectionMode terminal false
        liftEffect $ Terminal.setCommandDeckLatches terminal false false false false
        liftEffect $ Terminal.attachTerminal terminal url label
        H.modify_ _
          { selectedSession = sessionId
          , attachedSession = sessionId
          , windows = []
          , pendingClose = Nothing
          , closePreviewLoading = false
          , closeExecuting = false
          , endedNotice = Nothing
          , reconnectNotice = Nothing
          , sessionMenuOpen = false
          , windowMenuOpen = false
          , terminalMenuOpen = false
          , terminalSelectionMode = false
          , pasteMenuOpen = false
          , status = "connecting: " <> label
          , commandDeckLatches = emptyCommandDeckLatches
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
        , terminalSelectionMode = false
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
      Just terminal -> liftEffect do
        Terminal.setSelectionMode terminal false
        Terminal.setCommandDeckLatches terminal false false false false
        Terminal.disconnectTerminal terminal
    H.modify_ _
      { attachedSession = ""
      , windows = []
      , pendingClose = Nothing
      , closePreviewLoading = false
      , closeExecuting = false
      , endedNotice = Nothing
      , reconnectNotice = Nothing
      , sessionMenuOpen = false
      , windowMenuOpen = false
      , terminalMenuOpen = false
      , terminalSelectionMode = false
      , pasteMenuOpen = false
      , status = "disconnected"
      , commandDeckLatches = emptyCommandDeckLatches
      }
    syncUi

  HandleTerminal event -> do
    case event of
      TerminalOpened label -> do
        state <- H.get
        case state.reconnectNotice of
          Just reconnect -> do
            H.modify_ _
              { attachedSession = reconnect.sessionId
              , selectedSession = reconnect.sessionId
              , reconnectNotice = Nothing
              , status = reconnect.status
              }
            refreshWindows reconnect.sessionId
          Nothing ->
            H.modify_ _
              { status = fromMaybe ("attached: " <> label) state.endedNotice }
      TerminalClosed -> do
        state <- H.get
        H.modify_ _
          { attachedSession = ""
          , windows = []
          , sessionMenuOpen = false
          , windowMenuOpen = false
          , terminalMenuOpen = false
          , terminalSelectionMode = false
          , pasteMenuOpen = false
          , status = fromMaybe "disconnected" state.endedNotice
          }
      TerminalErrored ->
        H.modify_ _
          { status = "connection error"
          , reconnectNotice = Nothing
          , terminalMenuOpen = false
          , terminalSelectionMode = false
          , pasteMenuOpen = false
          }
      TerminalLinkOpened ->
        H.modify_ _ { status = "opened link" }
      TerminalLinkBlocked ->
        H.modify_ _ { status = "link blocked by browser" }
      TerminalScrollGesture lines ->
        scrollAttachedSession lines
      TerminalCommandDeckConsumed -> do
        state <- H.get
        case state.terminal of
          Nothing -> pure unit
          Just terminal -> liftEffect $
            Terminal.setCommandDeckLatches terminal false false false false
        H.modify_ _ { commandDeckLatches = emptyCommandDeckLatches }
    case event of
      TerminalScrollGesture _ -> pure unit
      _ -> syncUi

openCloseCurrent
  :: forall o
   . CloseScope
  -> H.HalogenM State Action Slots o Aff Unit
openCloseCurrent scope = do
  state <- H.get
  when
    ( state.attachedSession /= ""
        && not state.closePreviewLoading
        && isNothing state.pendingClose
    )
    do
      let sessionId = state.attachedSession
      H.modify_ _
        { closePreviewLoading = true
        , status = "Loading consequence for " <> closeActionLabel scope <> "…"
        }
      syncUi
      base <- liftEffect $ Browser.apiBase state.server
      result <- liftAff $ attempt (previewCloseCurrent scope base sessionId)
      latest <- H.get
      when
        ( latest.attachedSession == sessionId
            && latest.closePreviewLoading
        )
        do
          case result of
            Left err -> do
              let notice = closeActionLabel scope <> " preview failed: " <> message err
              H.modify_ _
                { pendingClose = Nothing
                , closePreviewLoading = false
                , closeExecuting = false
                , settingsOpen = false
                , status = notice
                }
              void $ refreshSurvivingClose sessionId notice
            Right preview ->
              H.modify_ _
                { pendingClose = Just
                    { scope: scope
                    , sessionId: sessionId
                    , consequence: preview.consequence
                    , confirmation: preview.confirmation
                    }
                , closePreviewLoading = false
                , closeExecuting = false
                , settingsOpen = false
                , status = "Review " <> closeActionLabel scope
                }
          syncUi

confirmCloseCurrent
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
confirmCloseCurrent = do
  state <- H.get
  case state.pendingClose of
    Nothing -> pure unit
    Just pending ->
      when (not state.closeExecuting) do
        H.modify_ _
          { closeExecuting = true
          , status = "Closing the server-confirmed current context…"
          }
        syncUi
        base <- liftEffect $ Browser.apiBase state.server
        result <- liftAff $ attempt
          (executeCloseCurrent pending.scope base pending.sessionId pending.confirmation)
        case result of
          Left err -> do
            let notice = closeActionLabel pending.scope <> " failed: " <> message err
            H.modify_ _
              { pendingClose = Nothing
              , closePreviewLoading = false
              , closeExecuting = false
              , status = notice
              }
            void $ refreshSurvivingClose pending.sessionId notice
          Right execution ->
            if execution.sessionEnded then
              finishEndedClose pending execution
            else
              finishSurvivingClose pending execution
        syncUi

previewCloseCurrent :: CloseScope -> String -> String -> Aff ClosePreview
previewCloseCurrent scope base sessionId =
  case scope of
    ClosePane -> Api.previewCloseCurrentPane base sessionId
    CloseWindow -> Api.previewCloseCurrentWindow base sessionId

executeCloseCurrent
  :: CloseScope
  -> String
  -> String
  -> String
  -> Aff CloseExecution
executeCloseCurrent scope base sessionId confirmation =
  case scope of
    ClosePane -> Api.closeCurrentPane base sessionId confirmation
    CloseWindow -> Api.closeCurrentWindow base sessionId confirmation

finishSurvivingClose
  :: forall o
   . CloseDialog
  -> CloseExecution
  -> H.HalogenM State Action Slots o Aff Unit
finishSurvivingClose pending execution = do
  let notice = closeSuccessStatus pending.scope execution.consequence false
  H.modify_ _
    { pendingClose = Nothing
    , closePreviewLoading = false
    , closeExecuting = false
    , status = notice
    }
  sessionExists <- refreshSurvivingClose pending.sessionId notice
  when sessionExists do
    state <- H.get
    case state.terminal of
      Nothing -> H.modify_ _ { status = notice <> "; terminal not ready" }
      Just terminal -> do
        let reconnectStatus = state.status
        url <- liftEffect $
          Browser.sessionTerminalWsUrl state.server pending.sessionId
        H.modify_ _
          { reconnectNotice = Just
              { sessionId: pending.sessionId
              , status: reconnectStatus
              }
          }
        liftEffect do
          Terminal.setSelectionMode terminal false
          Terminal.replaceTerminalAfterDestructiveClose terminal url
            ("session " <> pending.sessionId)

finishEndedClose
  :: forall o
   . CloseDialog
  -> CloseExecution
  -> H.HalogenM State Action Slots o Aff Unit
finishEndedClose pending execution = do
  let notice = closeSuccessStatus pending.scope execution.consequence true
  state <- H.get
  H.modify_ _
    { pendingClose = Nothing
    , closePreviewLoading = false
    , closeExecuting = false
    , endedNotice = Just notice
    , reconnectNotice = Nothing
    , attachedSession = ""
    , selectedSession = ""
    , windows = []
    , settingsOpen = false
    , sessionMenuOpen = false
    , windowMenuOpen = false
    , terminalMenuOpen = false
    , terminalSelectionMode = false
    , pasteMenuOpen = false
    , status = notice
    }
  case state.terminal of
    Nothing -> pure unit
    Just terminal -> liftEffect do
      Terminal.setSelectionMode terminal false
      Terminal.abandonTerminal terminal
  refreshEndedClose notice

refreshSurvivingClose
  :: forall o
   . String
  -> String
  -> H.HalogenM State Action Slots o Aff Boolean
refreshSurvivingClose sessionId notice = do
  state <- H.get
  base <- liftEffect $ Browser.apiBase state.server
  sessionsResult <- liftAff $ attempt (Api.fetchSessions base)
  case sessionsResult of
    Left err -> do
      let refreshNotice = notice <> "; session refresh failed: " <> message err
      H.modify_ _ { status = refreshNotice }
      pure false
    Right sessions ->
      if Array.any (\session -> session.id == sessionId) sessions then do
        windowsResult <- liftAff $ attempt (Api.fetchWindows base sessionId)
        case windowsResult of
          Left err -> do
            let refreshNotice = notice <> "; window refresh failed: " <> message err
            H.modify_ _
              { sessions = sessions
              , windows = []
              , attachedSession = sessionId
              , selectedSession = sessionId
              , status = refreshNotice
              }
          Right windows ->
            H.modify_ _
              { sessions = sessions
              , windows = windows
              , attachedSession = sessionId
              , selectedSession = sessionId
              , status = notice
              }
        pure true
      else do
        let missingNotice = notice <> "; session no longer exists"
        H.modify_ _
          { sessions = sessions
          , windows = []
          , attachedSession = ""
          , selectedSession = maybeSessionId (Array.head sessions)
          , status = missingNotice
          }
        case state.terminal of
          Nothing -> pure unit
          Just terminal -> liftEffect do
            Terminal.setSelectionMode terminal false
            Terminal.disconnectTerminal terminal
        pure false

refreshEndedClose
  :: forall o
   . String
  -> H.HalogenM State Action Slots o Aff Unit
refreshEndedClose notice = do
  state <- H.get
  base <- liftEffect $ Browser.apiBase state.server
  result <- liftAff $ attempt (Api.fetchSessions base)
  case result of
    Left err -> do
      let refreshNotice = notice <> "; session refresh failed: " <> message err
      H.modify_ _ { endedNotice = Just refreshNotice, status = refreshNotice }
    Right sessions ->
      H.modify_ _
        { sessions = sessions
        , selectedSession = maybeSessionId (Array.head sessions)
        , attachedSession = ""
        , windows = []
        , endedNotice = Just notice
        , status = notice
        }

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

copyTerminalText
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
copyTerminalText = do
  state <- H.get
  case state.terminal of
    Nothing ->
      H.modify_ _
        { status = "terminal not ready"
        , terminalMenuOpen = false
        }
    Just terminal -> do
      result <- liftAff $ attempt (Terminal.copySelection terminal)
      case result of
        Left err ->
          H.modify_ _
            { status = "copy failed: " <> message err
            , terminalMenuOpen = false
            }
        Right source ->
          H.modify_ _
            { status = copyStatus source
            , terminalMenuOpen = false
            }
  syncUi

toggleTerminalSelectionMode
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
toggleTerminalSelectionMode = do
  state <- H.get
  case state.terminal of
    Nothing ->
      H.modify_ _
        { status = "terminal not ready"
        , terminalMenuOpen = false
        }
    Just terminal -> do
      let next = not state.terminalSelectionMode
      liftEffect $ Terminal.setSelectionMode terminal next
      H.modify_ _
        { terminalSelectionMode = next
        , terminalMenuOpen = false
        , status =
            if next then "touch selection mode" else "terminal mode"
        }
  syncUi

savePasteSnippet
  :: forall o
   . H.HalogenM State Action Slots o Aff Unit
savePasteSnippet = do
  state <- H.get
  if state.pasteName == "" || (state.pasteBody == "" && not state.pasteEnter) then
    H.modify_ _ { status = "paste needs name and text" }
  else do
    let
      paste =
        { name: state.pasteName
        , body: state.pasteBody
        , enter: state.pasteEnter
        }
      pastes = upsertPaste paste state.pastes
    liftEffect $ Browser.savePastes pasteStorageKey pastes
    H.modify_ _
      { pastes = pastes
      , pasteName = ""
      , pasteBody = ""
      , pasteEnter = false
      , pasteEditorOpen = false
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
    , pasteEnter = if state.pasteName == name then false else state.pasteEnter
    , pasteEditorOpen =
        if state.pasteName == name then false else state.pasteEditorOpen
    , status = "deleted paste: " <> name
    }
  syncUi

pasteTerminalText
  :: forall o
   . String
  -> String
  -> Boolean
  -> H.HalogenM State Action Slots o Aff Unit
pasteTerminalText label body enter = do
  state <- H.get
  if body == "" && not enter then
    H.modify_ _ { status = "nothing to paste" }
  else
    case state.terminal of
      Nothing ->
        H.modify_ _
          { status = "terminal not ready"
          , pasteMenuOpen = false
          }
      Just terminal -> do
        liftEffect $ Terminal.sendText terminal (pastePayload body enter)
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

closeActionLabel :: CloseScope -> String
closeActionLabel = case _ of
  ClosePane -> "Close this pane"
  CloseWindow -> "Close this window"

closeConsequenceCopy :: CloseScope -> String -> String
closeConsequenceCopy scope consequence =
  case consequence of
    "pane-removed" ->
      "The current pane will close. Its window and session will remain."
    "pane-and-window-removed" ->
      "This is the window's last pane. The current pane and window will close while the session remains."
    "window-removed" ->
      "The current window and all its panes will close. The session will remain."
    "session-ended" ->
      case scope of
        ClosePane ->
          "This is the final pane in the final window. Closing it will end the session."
        CloseWindow ->
          "This is the final window. Closing it and all its panes will end the session."
    _ ->
      "The server reports consequence “" <> consequence <> "”."

closeSuccessStatus :: CloseScope -> String -> Boolean -> String
closeSuccessStatus scope consequence sessionEnded =
  closeActionLabel scope
    <> " complete: "
    <> consequence
    <> if sessionEnded then " — session ended" else " — session remains"

pastePreview :: String -> String
pastePreview = identity

pastePayload :: String -> Boolean -> String
pastePayload body enter =
  if enter then body <> "\n" else body

copyStatus :: String -> String
copyStatus source =
  case source of
    "selection" -> "copied selection"
    "screen" -> "copied screen"
    _ -> "nothing to copy"

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

dockButton
  :: String
  -> String
  -> Action
  -> Maybe String
  -> Boolean
  -> Boolean
  -> H.ComponentHTML Action Slots Aff
dockButton label iconName action expanded active disabled =
  HH.button
    ( [ cls ("dock-button" <> if active then " active" else "")
      , HP.title label
      , HP.disabled disabled
      , HE.onClick \_ -> action
      ]
        <> case expanded of
          Nothing -> []
          Just value -> [ HP.attr (HH.AttrName "aria-expanded") value ]
    )
    [ icon iconName
    , HH.span
        [ cls "dock-label" ]
        [ HH.text label ]
    ]

iconLink :: String -> String -> String -> H.ComponentHTML Action Slots Aff
iconLink label iconName href =
  HH.a
    [ cls "icon-link"
    , HP.title label
    , HP.attr (HH.AttrName "aria-label") label
    , HP.attr (HH.AttrName "href") href
    , HP.attr (HH.AttrName "target") "_blank"
    , HP.attr (HH.AttrName "rel") "noopener noreferrer"
    ]
    [ icon iconName ]

iconTextLink :: String -> String -> String -> H.ComponentHTML Action Slots Aff
iconTextLink label iconName href =
  HH.a
    [ cls "utility-link"
    , HP.title label
    , HP.attr (HH.AttrName "aria-label") label
    , HP.attr (HH.AttrName "href") href
    , HP.attr (HH.AttrName "target") "_blank"
    , HP.attr (HH.AttrName "rel") "noopener noreferrer"
    ]
    [ icon iconName
    , HH.span
        [ cls "utility-label" ]
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
