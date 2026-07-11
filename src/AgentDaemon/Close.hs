{- |
Module      : AgentDaemon.Close
Description : Pure close-current state-machine model
Copyright   : (c) 2026 Paolo Veronelli
License     : MIT

Models preparation and single-use execution of current-pane and
current-window closes independently of tmux and the API layer.
-}
module AgentDaemon.Close
    ( SessionId (..)
    , WindowId (..)
    , PaneId (..)
    , CloseScope (..)
    , CloseWindow (..)
    , CloseTopology (..)
    , CurrentContext (..)
    , CloseConsequence (..)
    , CloseFailure (..)
    , PreparedClose
    , CloseOutcome (..)
    , prepareClose
    , executeClose
    , isConsumed
    , isValidTopology
    )
where

import Data.List (find, nub)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NE

-- | Stable identity of a live session.
newtype SessionId = SessionId Int
    deriving stock (Eq, Ord, Show)

-- | Stable identity of a live window.
newtype WindowId = WindowId Int
    deriving stock (Eq, Ord, Show)

-- | Stable identity of a live pane.
newtype PaneId = PaneId Int
    deriving stock (Eq, Ord, Show)

-- | Current context affected by a close.
data CloseScope
    = CloseCurrentPane
    | CloseCurrentWindow
    deriving stock (Eq, Show)

-- | One valid live window and its current pane.
data CloseWindow = CloseWindow
    { closeWindowId :: WindowId
    , closeWindowPanes :: NonEmpty PaneId
    , closeWindowCurrentPane :: PaneId
    }
    deriving stock (Eq, Show)

-- | A non-empty live session topology and its current window.
data CloseTopology = CloseTopology
    { topologySession :: SessionId
    , topologyWindows :: NonEmpty CloseWindow
    , topologyCurrentWindow :: WindowId
    }
    deriving stock (Eq, Show)

-- | Prepared identity and cardinality snapshot.
data CurrentContext = CurrentContext
    { contextSession :: SessionId
    , contextScope :: CloseScope
    , contextWindow :: WindowId
    , contextPane :: Maybe PaneId
    , contextWindowCount :: Int
    , contextPaneCount :: Int
    , contextCurrentWindowPaneCount :: Int
    }
    deriving stock (Eq, Show)

-- | Truthful consequence previewed and returned by execution.
data CloseConsequence
    = PaneRemoved
    | PaneAndWindowRemoved
    | WindowRemoved
    | SessionEnded
    deriving stock (Eq, Show)

-- | Failure that leaves the supplied topology unchanged.
data CloseFailure
    = InvalidTopology
    | StaleCurrentContext
    | ConfirmationConsumed
    deriving stock (Eq, Show)

-- | Single-use prepared confirmation state.
data PreparedClose
    = Available CurrentContext CloseConsequence
    | Consumed CurrentContext CloseConsequence
    deriving stock (Eq, Show)

-- | Successful consequence and optional surviving topology.
data CloseOutcome = CloseOutcome
    { outcomeConsequence :: CloseConsequence
    , outcomeTopology :: Maybe CloseTopology
    }
    deriving stock (Eq, Show)

-- | Prepare a confirmation for a valid topology.
prepareClose
    :: CloseScope
    -> CloseTopology
    -> Either CloseFailure PreparedClose
prepareClose scope topology
    | isValidTopology topology =
        Right $
            Available
                (snapshot scope topology)
                (consequenceFor scope topology)
    | otherwise = Left InvalidTopology

-- | Consume a confirmation and execute it against fresh topology.
executeClose
    :: PreparedClose
    -> CloseTopology
    -> (PreparedClose, Either CloseFailure CloseOutcome)
executeClose consumed@Consumed{} _ =
    (consumed, Left ConfirmationConsumed)
executeClose available@(Available context consequence) topology
    | not $ isValidTopology topology =
        (consume available, Left InvalidTopology)
    | snapshot (contextScope context) topology /= context =
        (consume available, Left StaleCurrentContext)
    | otherwise =
        ( consume available
        , Right $ applyClose (contextScope context) consequence topology
        )

-- | Whether a confirmation has already had an execution attempt.
isConsumed :: PreparedClose -> Bool
isConsumed Available{} = False
isConsumed Consumed{} = True

-- | Check all live-topology identity and currentness invariants.
isValidTopology :: CloseTopology -> Bool
isValidTopology CloseTopology{topologyWindows, topologyCurrentWindow} =
    unique windowIdentities
        && unique paneIdentities
        && topologyCurrentWindow `elem` windowIdentities
        && all currentPaneExists windows
  where
    windows = NE.toList topologyWindows
    windowIdentities = closeWindowId <$> windows
    paneIdentities = concatMap (NE.toList . closeWindowPanes) windows
    currentPaneExists CloseWindow{closeWindowPanes, closeWindowCurrentPane} =
        closeWindowCurrentPane `elem` closeWindowPanes

snapshot :: CloseScope -> CloseTopology -> CurrentContext
snapshot scope topology@CloseTopology{topologySession, topologyCurrentWindow} =
    CurrentContext
        { contextSession = topologySession
        , contextScope = scope
        , contextWindow = topologyCurrentWindow
        , contextPane = paneForScope scope topology
        , contextWindowCount = NE.length $ topologyWindows topology
        , contextPaneCount =
            sum $ NE.length . closeWindowPanes <$> topologyWindows topology
        , contextCurrentWindowPaneCount =
            maybe 0 (NE.length . closeWindowPanes) $ currentWindowFor topology
        }

paneForScope :: CloseScope -> CloseTopology -> Maybe PaneId
paneForScope CloseCurrentWindow _ = Nothing
paneForScope CloseCurrentPane CloseTopology{topologyWindows, topologyCurrentWindow} =
    closeWindowCurrentPane
        <$> find
            ((== topologyCurrentWindow) . closeWindowId)
            (NE.toList topologyWindows)

consume :: PreparedClose -> PreparedClose
consume (Available context consequence) = Consumed context consequence
consume consumed@Consumed{} = consumed

unique :: (Eq a) => [a] -> Bool
unique values = length values == length (nub values)

consequenceFor :: CloseScope -> CloseTopology -> CloseConsequence
consequenceFor CloseCurrentWindow CloseTopology{topologyWindows}
    | NE.length topologyWindows == 1 = SessionEnded
    | otherwise = WindowRemoved
consequenceFor CloseCurrentPane topology@CloseTopology{topologyWindows} =
    case currentWindowFor topology of
        Just window
            | NE.length (closeWindowPanes window) > 1 -> PaneRemoved
            | NE.length topologyWindows > 1 -> PaneAndWindowRemoved
        _ -> SessionEnded

applyClose
    :: CloseScope
    -> CloseConsequence
    -> CloseTopology
    -> CloseOutcome
applyClose CloseCurrentPane consequence topology =
    closePane consequence topology
applyClose CloseCurrentWindow consequence topology =
    closeWindow consequence topology

closePane :: CloseConsequence -> CloseTopology -> CloseOutcome
closePane consequence topology =
    case currentWindowFor topology of
        Nothing -> CloseOutcome SessionEnded Nothing
        Just window ->
            case remainingPanes window of
                Just panes ->
                    CloseOutcome consequence . Just $
                        topology
                            { topologyWindows =
                                replaceCurrentWindow
                                    topology
                                    window
                                        { closeWindowPanes = panes
                                        , closeWindowCurrentPane = NE.head panes
                                        }
                            }
                Nothing -> closeWindow consequence topology

closeWindow :: CloseConsequence -> CloseTopology -> CloseOutcome
closeWindow consequence topology =
    case remainingWindows topology of
        Nothing -> CloseOutcome SessionEnded Nothing
        Just windows ->
            CloseOutcome consequence . Just $
                topology
                    { topologyWindows = windows
                    , topologyCurrentWindow = closeWindowId $ NE.head windows
                    }

currentWindowFor :: CloseTopology -> Maybe CloseWindow
currentWindowFor CloseTopology{topologyWindows, topologyCurrentWindow} =
    find
        ((== topologyCurrentWindow) . closeWindowId)
        (NE.toList topologyWindows)

remainingPanes :: CloseWindow -> Maybe (NonEmpty PaneId)
remainingPanes CloseWindow{closeWindowPanes, closeWindowCurrentPane} =
    NE.nonEmpty $
        filter (/= closeWindowCurrentPane) $
            NE.toList closeWindowPanes

remainingWindows :: CloseTopology -> Maybe (NonEmpty CloseWindow)
remainingWindows CloseTopology{topologyWindows, topologyCurrentWindow} =
    NE.nonEmpty $
        filter ((/= topologyCurrentWindow) . closeWindowId) $
            NE.toList topologyWindows

replaceCurrentWindow
    :: CloseTopology
    -> CloseWindow
    -> NonEmpty CloseWindow
replaceCurrentWindow CloseTopology{topologyWindows, topologyCurrentWindow} replacement =
    replace <$> topologyWindows
  where
    replace window
        | closeWindowId window == topologyCurrentWindow = replacement
        | otherwise = window
