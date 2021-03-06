{-# language ScopedTypeVariables #-}

-- This is a replacment for cabal's autogenerated Paths_nikki.hs
-- Use this instead to find data files.
-- Needed for deployment in one folder

module Base.Paths (
    getDataFileName,
    getDataFiles,
    getConfigurationDirectory,
    getConfigurationFile,
    loadConfiguration,
    withDynamicConfiguration,

    module StoryMode.Paths
  ) where


import Safe

import Data.List
import Data.Initial
import Data.Maybe

import Text.Logging

import Control.Monad.State.Strict
import Control.Monad.CatchState
import Control.Monad.CatchIO

import System.Info
import System.FilePath
import System.Directory
import System.Environment
import System.Console.CmdArgs.Missing

import Utils

import Base.Types
import Base.Configuration
import Base.Paths.GetDataFileName

import StoryMode.Paths


-- | returns unhidden files with a given extension in a given data directory.
getDataFiles :: FilePath -> (Maybe String) -> RM [FilePath]
getDataFiles path_ extension = do
    path <- getDataFileName path_
    pathExists <- io $ doesDirectoryExist path
    if pathExists then do
        map (path </>) <$> io (getFiles path extension)
      else
        return []


-- * configuration

-- | returns the user's configuration directory
getConfigurationDirectory :: IO FilePath
getConfigurationDirectory = do
    d <- getAppUserDataDirectory "nikki"
    createDirectoryIfMissing True d
    return d

-- | Returns the path to the configuration file.
-- The file might be non-existent.
getConfigurationFile :: IO FilePath
getConfigurationFile = do
    d <- getConfigurationDirectory
    return (d </> "configuration")

-- | loads the configuration and initialises the logging command.
-- (before calling loadConfiguration, nothing should be logged.)
loadConfiguration :: IO Configuration
loadConfiguration = do
    filteredArgs <- filterUnwantedArgs <$> getArgs
    mLoadedSavedConfig <- loadConfigurationFromFile
    showDevelopmentOptions <- shouldShowDevelopmentOptions
    let loadedSavedConfig = case mLoadedSavedConfig of
            Left (logLevel, msg) -> initial
            Right x -> x
        loadedConfig = savedConfigurationToConfiguration showDevelopmentOptions loadedSavedConfig
    config <- cmdTheseArgs loadedConfig filteredArgs
    case mLoadedSavedConfig of
        -- retain error messages till after execution of cmdArgs
        -- to prevent pollution of version or help output
        Left (logLevel, msg) -> logg logLevel msg
        _ -> return ()
    return config

-- | Returns whether development options should be shown.
-- This is the case when NIKKI_DEVELOPMENT is defined.
shouldShowDevelopmentOptions :: IO Bool
shouldShowDevelopmentOptions = do
    v <- lookup "NIKKI_DEVELOPMENT" <$> getEnvironment
    return $ isJust v

-- | on OS X there is a default command line argument
-- (-psn_SOMETHING_WITH_THE_PID) passed to the application
-- when launched in application bundle mode.
-- We remove this from the arguments before processing via CmdArgs.
filterUnwantedArgs :: [String] -> [String]
filterUnwantedArgs = case System.Info.os of
    "darwin" -> filter (\ arg -> not ("-psn_" `isPrefixOf` arg))
    _ -> id

-- | loads the configuration from file.
-- If the file does not exists, it is initialized with the default configuration.
-- Also returns a message, if necessary.
loadConfigurationFromFile :: IO (Either (LogLevel, String) SavedConfiguration)
loadConfigurationFromFile = do
    file <- getConfigurationFile
    exists <- doesFileExist file
    if (not exists) then
        -- no config file found
        return $ Left (Info, "no configuration file found, using default configuration.")
      else do
        -- attempting to load configuration
        mLoaded :: Maybe SavedConfiguration <- readMay <$> readFile file
        case mLoaded of
            Nothing ->
                return $ Left (Error, "unable to read configuration file, using default configuration")
            Just config -> return $ Right config

saveConfigurationToFile :: SavedConfiguration -> IO ()
saveConfigurationToFile config = do
    file <- getConfigurationFile
    writeFile file (show config)

-- | Executes an M Monad.
-- Will save changes to the configuration afterwards
-- (Once this is possible, for now M is just ReaderT Configuration IO)
withDynamicConfiguration :: Configuration -> M a -> IO a
withDynamicConfiguration configuration action =
    fst <$> runCatchState (action `finally` save) configuration
  where
    save =
        (io . saveConfigurationToFile . configurationToSavedConfiguration) =<< get
