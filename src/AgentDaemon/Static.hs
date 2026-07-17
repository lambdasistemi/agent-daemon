module AgentDaemon.Static
    ( resolveStaticDir
    , staticDirFor
    ) where

-- \|
-- Module      : AgentDaemon.Static
-- Description : Resolve development and installed SPA directories
-- Copyright   : (c) Paolo Veronelli, 2026
-- License     : MIT
--
-- Selects an explicit or local development SPA directory when available, then
-- falls back to the distribution layout beside the installed executable.

import System.Directory (doesDirectoryExist)
import System.Environment (getExecutablePath)
import System.FilePath (normalise, takeDirectory, (</>))

-- | Resolve the configured SPA directory for the running executable.
resolveStaticDir :: FilePath -> IO FilePath
resolveStaticDir requested = do
    executable <- getExecutablePath
    localExists <- doesDirectoryExist requested
    pure $ staticDirFor executable requested localExists

-- | Choose an explicit, local-development, or installed SPA directory.
staticDirFor :: FilePath -> FilePath -> Bool -> FilePath
staticDirFor executable requested localExists
    | requested /= "static" = requested
    | localExists = requested
    | otherwise =
        normalise $
            takeDirectory (takeDirectory executable)
                </> "share"
                </> "tmux-ws"
                </> "static"
