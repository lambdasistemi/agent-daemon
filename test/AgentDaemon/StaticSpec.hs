module AgentDaemon.StaticSpec (spec) where

import AgentDaemon.Static (staticDirFor)
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "installed static directory" $ do
    it "keeps an explicit static directory" $
        staticDirFor "/opt/tmux-ws/bin/tmux-ws" "/srv/tmux-ws-ui" False
            `shouldBe` "/srv/tmux-ws-ui"
    it "keeps a local development static directory when it exists" $
        staticDirFor "/opt/tmux-ws/bin/tmux-ws" "static" True
            `shouldBe` "static"
    it "finds packaged UI files relative to the executable" $
        staticDirFor "/opt/tmux-ws/bin/tmux-ws" "static" False
            `shouldBe` "/opt/tmux-ws/share/tmux-ws/static"
