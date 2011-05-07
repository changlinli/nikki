{-# language ScopedTypeVariables #-}

-- | The (real) main (that is, entry-) module for the game

module Game.MainLoop (
    gameLoop,
    GameState(..)
  ) where


import Data.Initial

import Text.Logging

import Control.Monad.State hiding ((>=>))
import Control.Concurrent
import Clocked

import Physics.Chipmunk (Space)

import Graphics.Qt

import Utils

import Base

import Object

import Game.Scene


-- prints the version number of qt and exits
debugQtVersion :: IO ()
debugQtVersion = do
    v <- qtVersion
    logInfo ("Qt-Version: " ++ v)


-- * running the state monad inside the render IO command
-- renderCallback :: Application -> IORef GameAppState -> [QtEvent] -> Ptr QPainter -> IO ()
-- renderCallback app stateRef qtEvents painter = do
--     let allEvents = toEitherList qtEvents []
-- 
--     state <- readIORef stateRef
--     ((), state') <- runStateT (renderWithState app painter) state
--     writeIORef stateRef state'

-- Application Monad and State

type GameMonad o = StateT GameState M o

data GameState = GameState {
    cmSpace :: Space,
    scene :: Scene Object_
  }

setScene :: GameState -> Scene Object_ -> GameState
setScene s x = s{scene = x}


-- | main loop for logic thread in gaming mode
-- the sceneMVar has to be empty initially.
gameLoop :: Application -> MVar (RenderScene, DebuggingCommand) -> GameMonad ()
gameLoop app sceneMVar = do
    initializeSceneMVar
    timer <- io $ newTimer
    withArrowAutoRepeat app $
        loop timer
  where
    loop :: Timer -> GameMonad ()
    loop timer = do
        io $ resetDebugging

        -- input events
        controlData <- lift $ pollAppEvents app

        -- stepping of the scene (includes rendering)
        space <- gets cmSpace
        sc <- gets scene
        configuration <- lift get
        sc' <- io $ stepScene configuration space controlData sc
        puts setScene sc'

        swapSceneMVar =<< io getDebugging

        case sc' ^. mode of
            LevelFinished t _ ->
                when (null $ pressed controlData)
                    continue
            _ -> if isGameBackPressed (controls configuration) controlData then do
                io $ logInfo "NYI: game menu"
                return () -- TODO: should be a menu
              else
                continue
      where
        continue = do
            io $ waitTimer timer (realToFrac (stepQuantum / timeFactor))
            loop timer

    initializeSceneMVar :: GameMonad ()
    initializeSceneMVar = do
        empty <- io $ isEmptyMVar sceneMVar
        when (not empty) $ fail "sceneMVar has to be empty"
        s <- gets scene
        immutableCopyOfScene <- io $ mkRenderScene s
        io $ putMVar sceneMVar (immutableCopyOfScene, initial)
    swapSceneMVar :: DebuggingCommand -> GameMonad ()
    swapSceneMVar debugging = do
        s <- gets scene
        io $ do
            immutableCopyOfScene <- mkRenderScene s
            modifyMVar_ sceneMVar (const $ return (immutableCopyOfScene, debugging))
            return ()

withArrowAutoRepeat :: MonadIO m => Application -> m a -> m a
withArrowAutoRepeat app cmd = do
    io $ setArrowAutoRepeat (window app) False
    a <- cmd
    io $ setArrowAutoRepeat (window app) True
    return a
