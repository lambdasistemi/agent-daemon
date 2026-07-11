module AgentDaemon.CloseSpec (spec) where

import AgentDaemon.Close
import Data.List (find, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Maybe (fromMaybe)
import Test.Hspec (Spec, describe, it, shouldBe)
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
    ( Gen
    , Property
    , checkCoverage
    , chooseInt
    , classify
    , counterexample
    , cover
    , elements
    , forAll
    , property
    , vectorOf
    , (.&&.)
    , (===)
    )

spec :: Spec
spec = describe "close-current state machine" $ do
    prop "removes only the prepared current context" $
        forAll genScopeAndTopology propCurrentOnly
    prop "leaves stale topology unchanged and consumes confirmation" $
        forAll genStaleAttempt propStaleIdentity
    prop "returns a valid topology whenever the session survives" $
        forAll genScopeAndTopology propValidSurvivor
    prop "makes exactly the scope-specific cardinality change" $
        forAll genScopeAndTopology propExactCardinality
    prop "terminates exactly when the last window is removed" $
        forAll genScopeAndTopology propTruthfulTermination
    prop "rejects replay without changing the survivor" $
        forAll genScopeAndTopology propReplayIdentity
    prop "covers required scope and topology combinations" $
        forAll genScopeAndTopology propTopologyCoverage
    prop "covers pane and window currentness races" $
        forAll genStaleAttempt propStaleCoverage
    it "rejects an invalid live topology at preparation" $ do
        prepareClose CloseCurrentPane invalidTopology
            `shouldBe` Left InvalidTopology
    it "rejects duplicate window identities at preparation" $ do
        prepareClose CloseCurrentWindow duplicateWindowTopology
            `shouldBe` Left InvalidTopology
    it "rejects duplicate pane identities at preparation" $ do
        prepareClose CloseCurrentPane duplicatePaneTopology
            `shouldBe` Left InvalidTopology
    it "rejects consequence-changing pane redistribution" $ do
        case prepareClose CloseCurrentPane redistributionPreparedTopology of
            Left failure -> failure `shouldBe` StaleCurrentContext
            Right prepared -> do
                let (consumed, result) =
                        executeClose prepared redistributedTopology
                isConsumed consumed `shouldBe` True
                result `shouldBe` Left StaleCurrentContext

propCurrentOnly :: (CloseScope, CloseTopology) -> Property
propCurrentOnly (scope, topology) =
    checkCoverage
        $ cover 30 (scope == CloseCurrentPane) "pane scope"
        $ cover 30 (scope == CloseCurrentWindow) "window scope"
        $ cover 10 (windowCount topology == 1) "one window"
        $ cover 50 (windowCount topology > 1) "many windows"
        $ cover 10 (currentPaneCount topology == 1) "one current pane"
        $ cover 50 (currentPaneCount topology > 1) "many current panes"
        $ cover
            1
            (scope == CloseCurrentPane && removesLastWindow scope topology)
            "pane ends session"
        $ cover
            5
            ( scope == CloseCurrentPane
                && currentPaneCount topology == 1
                && windowCount topology > 1
            )
            "pane removes window"
        $ cover
            5
            (scope == CloseCurrentWindow && windowCount topology == 1)
            "window ends session"
        $ classify (scope == CloseCurrentPane) "pane scope"
        $ classify (scope == CloseCurrentWindow) "window scope"
        $ classify (windowCount topology == 1) "one window"
        $ classify (windowCount topology > 1) "many windows"
        $ classify (currentPaneCount topology == 1) "one current pane"
        $ classify (currentPaneCount topology > 1) "many current panes"
        $ case runClose scope topology of
            Left failure ->
                counterexample (show failure) False
            Right outcome ->
                removedWindowIds topology outcome
                    === expectedRemovedWindows scope topology
                    .&&. removedPaneIds topology outcome
                        === expectedRemovedPanes scope topology

propStaleIdentity
    :: (CloseScope, CloseTopology, CloseTopology) -> Property
propStaleIdentity (scope, preparedAt, changedCurrent) =
    case prepareClose scope preparedAt of
        Left failure -> counterexample (show failure) False
        Right prepared ->
            case executeClose prepared changedCurrent of
                (consumed, Left StaleCurrentContext) ->
                    property (isConsumed consumed)
                result -> counterexample (show result) False

propValidSurvivor :: (CloseScope, CloseTopology) -> Property
propValidSurvivor (scope, topology) =
    case runClose scope topology of
        Left failure -> counterexample (show failure) False
        Right CloseOutcome{outcomeTopology = Nothing} -> property True
        Right CloseOutcome{outcomeTopology = Just survivor} ->
            counterexample (show survivor) $ property (isValidTopology survivor)

propExactCardinality :: (CloseScope, CloseTopology) -> Property
propExactCardinality (scope, topology) =
    case runClose scope topology of
        Left failure -> counterexample (show failure) False
        Right outcome ->
            resultingWindowCount outcome
                === windowCount topology - expectedWindowDelta scope topology
                .&&. resultingPaneCount outcome
                    === paneCount topology - expectedPaneDelta scope topology

propTruthfulTermination :: (CloseScope, CloseTopology) -> Property
propTruthfulTermination (scope, topology) =
    case runClose scope topology of
        Left failure -> counterexample (show failure) False
        Right CloseOutcome{outcomeConsequence, outcomeTopology} ->
            (outcomeTopology == Nothing)
                === removesLastWindow scope topology
                .&&. (outcomeConsequence == SessionEnded)
                    === (outcomeTopology == Nothing)

propReplayIdentity :: (CloseScope, CloseTopology) -> Property
propReplayIdentity (scope, topology) =
    case prepareClose scope topology of
        Left failure -> counterexample (show failure) False
        Right prepared ->
            case executeClose prepared topology of
                (_, Left failure) -> counterexample (show failure) False
                (consumed, Right firstOutcome) ->
                    let afterFirst = maybe topology id (outcomeTopology firstOutcome)
                    in  case executeClose consumed afterFirst of
                            (stillConsumed, Left ConfirmationConsumed) ->
                                property (isConsumed stillConsumed)
                            result -> counterexample (show result) False

propTopologyCoverage :: (CloseScope, CloseTopology) -> Property
propTopologyCoverage (scope, topology) =
    checkCoverage
        $ cover 30 (scope == CloseCurrentPane) "pane scope"
        $ cover 30 (scope == CloseCurrentWindow) "window scope"
        $ cover 10 (windowCount topology == 1) "one window"
        $ cover 50 (windowCount topology > 1) "many windows"
        $ cover 10 (currentPaneCount topology == 1) "one current pane"
        $ cover 50 (currentPaneCount topology > 1) "many current panes"
        $ cover
            1
            (scope == CloseCurrentPane && removesLastWindow scope topology)
            "pane ends session"
        $ cover
            5
            ( scope == CloseCurrentPane
                && currentPaneCount topology == 1
                && windowCount topology > 1
            )
            "pane removes window"
        $ cover
            5
            (scope == CloseCurrentWindow && windowCount topology == 1)
            "window ends session"
        $ property True

propStaleCoverage
    :: (CloseScope, CloseTopology, CloseTopology) -> Property
propStaleCoverage (scope, before, after) =
    checkCoverage
        $ cover
            30
            (scope == CloseCurrentWindow)
            "window-scope current window changed"
        $ cover 30 (scope == CloseCurrentPane) "pane-scope stale"
        $ cover
            10
            (scope == CloseCurrentPane && windowChanged)
            "pane scope current window changed"
        $ cover
            10
            (scope == CloseCurrentPane && not windowChanged)
            "pane scope current pane changed"
        $ property True
  where
    windowChanged =
        topologyCurrentWindow before /= topologyCurrentWindow after

genScopeAndTopology :: Gen (CloseScope, CloseTopology)
genScopeAndTopology =
    (,)
        <$> elements [CloseCurrentPane, CloseCurrentWindow]
        <*> genTopology

genTopology :: Gen CloseTopology
genTopology = do
    numberOfWindows <- chooseInt (1, 4)
    paneCounts <- vectorOf numberOfWindows (chooseInt (1, 4))
    currentWindowPosition <- chooseInt (0, numberOfWindows - 1)
    currentPanePositions <-
        mapM (\count -> chooseInt (0, count - 1)) paneCounts
    pure $
        topologyFromShape
            paneCounts
            currentWindowPosition
            currentPanePositions

genStaleAttempt :: Gen (CloseScope, CloseTopology, CloseTopology)
genStaleAttempt = do
    scope <- elements [CloseCurrentPane, CloseCurrentWindow]
    case scope of
        CloseCurrentWindow -> do
            numberOfWindows <- chooseInt (2, 4)
            paneCounts <- vectorOf numberOfWindows (chooseInt (1, 4))
            currentPanePositions <-
                mapM (\count -> chooseInt (0, count - 1)) paneCounts
            oldPosition <- chooseInt (0, numberOfWindows - 1)
            offset <- chooseInt (1, numberOfWindows - 1)
            let newPosition = (oldPosition + offset) `mod` numberOfWindows
                before = topologyFromShape paneCounts oldPosition currentPanePositions
                after = topologyFromShape paneCounts newPosition currentPanePositions
            pure (scope, before, after)
        CloseCurrentPane -> do
            numberOfWindows <- chooseInt (2, 4)
            currentWindowPosition <- chooseInt (0, numberOfWindows - 1)
            paneCounts <- vectorOf numberOfWindows (chooseInt (2, 4))
            currentPanePositions <-
                mapM (\count -> chooseInt (0, count - 1)) paneCounts
            changeWindow <- elements [False, True]
            offset <-
                chooseInt
                    ( 1
                    , if changeWindow
                        then numberOfWindows - 1
                        else paneCounts !! currentWindowPosition - 1
                    )
            let oldPanePosition = currentPanePositions !! currentWindowPosition
                newWindowPosition = (currentWindowPosition + offset) `mod` numberOfWindows
                newPanePosition =
                    (oldPanePosition + offset) `mod` (paneCounts !! currentWindowPosition)
                changedPositions =
                    replaceAt currentWindowPosition newPanePosition currentPanePositions
                before =
                    topologyFromShape
                        paneCounts
                        currentWindowPosition
                        currentPanePositions
                after
                    | changeWindow =
                        topologyFromShape paneCounts newWindowPosition currentPanePositions
                    | otherwise =
                        topologyFromShape paneCounts currentWindowPosition changedPositions
            pure (scope, before, after)

topologyFromShape :: [Int] -> Int -> [Int] -> CloseTopology
topologyFromShape paneCounts currentWindowPosition currentPanePositions =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            NE.fromList $ zipWith3 mkWindow [1 ..] paneCounts currentPanePositions
        , topologyCurrentWindow = WindowId currentWindowPosition
        }
  where
    mkWindow windowNumber numberOfPanes currentPanePosition =
        let firstPaneNumber = sum (take (windowNumber - 1) paneCounts)
            panes =
                NE.fromList $
                    PaneId <$> [firstPaneNumber .. firstPaneNumber + numberOfPanes - 1]
        in  CloseWindow
                { closeWindowId = WindowId (windowNumber - 1)
                , closeWindowPanes = panes
                , closeWindowCurrentPane = panes NE.!! currentPanePosition
                }

invalidTopology :: CloseTopology
invalidTopology =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            CloseWindow (WindowId 1) (PaneId 1 :| []) (PaneId 2) :| []
        , topologyCurrentWindow = WindowId 1
        }

duplicateWindowTopology :: CloseTopology
duplicateWindowTopology =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            CloseWindow (WindowId 1) (PaneId 1 :| []) (PaneId 1)
                :| [CloseWindow (WindowId 1) (PaneId 2 :| []) (PaneId 2)]
        , topologyCurrentWindow = WindowId 1
        }

duplicatePaneTopology :: CloseTopology
duplicatePaneTopology =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            CloseWindow (WindowId 1) (PaneId 1 :| []) (PaneId 1)
                :| [CloseWindow (WindowId 2) (PaneId 1 :| []) (PaneId 1)]
        , topologyCurrentWindow = WindowId 1
        }

redistributionPreparedTopology :: CloseTopology
redistributionPreparedTopology =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            CloseWindow (WindowId 1) (PaneId 1 :| []) (PaneId 1)
                :| [ CloseWindow
                        (WindowId 2)
                        (PaneId 2 :| [PaneId 3])
                        (PaneId 2)
                   ]
        , topologyCurrentWindow = WindowId 1
        }

redistributedTopology :: CloseTopology
redistributedTopology =
    CloseTopology
        { topologySession = SessionId 1
        , topologyWindows =
            CloseWindow
                (WindowId 1)
                (PaneId 1 :| [PaneId 3])
                (PaneId 1)
                :| [CloseWindow (WindowId 2) (PaneId 2 :| []) (PaneId 2)]
        , topologyCurrentWindow = WindowId 1
        }

runClose
    :: CloseScope -> CloseTopology -> Either CloseFailure CloseOutcome
runClose scope topology = do
    prepared <- prepareClose scope topology
    snd $ executeClose prepared topology

currentWindow :: CloseTopology -> CloseWindow
currentWindow CloseTopology{topologyCurrentWindow, topologyWindows} =
    fromMaybe (NE.head topologyWindows) $
        find
            ((== topologyCurrentWindow) . closeWindowId)
            (NE.toList topologyWindows)

currentPaneCount :: CloseTopology -> Int
currentPaneCount = NE.length . closeWindowPanes . currentWindow

windowCount :: CloseTopology -> Int
windowCount = NE.length . topologyWindows

paneCount :: CloseTopology -> Int
paneCount =
    sum
        . fmap (NE.length . closeWindowPanes)
        . NE.toList
        . topologyWindows

resultingWindowCount :: CloseOutcome -> Int
resultingWindowCount = maybe 0 windowCount . outcomeTopology

resultingPaneCount :: CloseOutcome -> Int
resultingPaneCount = maybe 0 paneCount . outcomeTopology

windowIds :: CloseTopology -> [WindowId]
windowIds = fmap closeWindowId . NE.toList . topologyWindows

paneIds :: CloseTopology -> [PaneId]
paneIds =
    concatMap (NE.toList . closeWindowPanes) . NE.toList . topologyWindows

removedWindowIds :: CloseTopology -> CloseOutcome -> [WindowId]
removedWindowIds before =
    difference (windowIds before) . maybe [] windowIds . outcomeTopology

removedPaneIds :: CloseTopology -> CloseOutcome -> [PaneId]
removedPaneIds before = difference (paneIds before) . maybe [] paneIds . outcomeTopology

expectedRemovedWindows :: CloseScope -> CloseTopology -> [WindowId]
expectedRemovedWindows CloseCurrentWindow topology = [topologyCurrentWindow topology]
expectedRemovedWindows CloseCurrentPane topology
    | currentPaneCount topology == 1 = [topologyCurrentWindow topology]
    | otherwise = []

expectedRemovedPanes :: CloseScope -> CloseTopology -> [PaneId]
expectedRemovedPanes CloseCurrentWindow = NE.toList . closeWindowPanes . currentWindow
expectedRemovedPanes CloseCurrentPane = pure . closeWindowCurrentPane . currentWindow

expectedWindowDelta :: CloseScope -> CloseTopology -> Int
expectedWindowDelta CloseCurrentWindow _ = 1
expectedWindowDelta CloseCurrentPane topology
    | currentPaneCount topology == 1 = 1
    | otherwise = 0

expectedPaneDelta :: CloseScope -> CloseTopology -> Int
expectedPaneDelta CloseCurrentWindow topology =
    NE.length . closeWindowPanes $ currentWindow topology
expectedPaneDelta CloseCurrentPane _ = 1

removesLastWindow :: CloseScope -> CloseTopology -> Bool
removesLastWindow CloseCurrentWindow topology = windowCount topology == 1
removesLastWindow CloseCurrentPane topology =
    windowCount topology == 1 && currentPaneCount topology == 1

difference :: (Ord a) => [a] -> [a] -> [a]
difference left right = sort left `without` sort right
  where
    without [] _ = []
    without xs [] = xs
    without xs@(x : xt) ys@(y : yt)
        | x < y = x : without xt ys
        | x == y = without xt yt
        | otherwise = without xs yt

replaceAt :: Int -> a -> [a] -> [a]
replaceAt index replacement values =
    take index values <> [replacement] <> drop (index + 1) values
