
-- | The (real) main (that is, entry-) module for the game

module Game.MainLoop (
    initialSize,
    gameMain,
    renderCallback,
    AppState,
    initialStateRef,
    initScene,
    initSceneFromEditor,
  ) where

-- my utils

import Utils
import GlobalCatcher
import Constants
import Configuration

-- normal haskell stuff

import Data.Set as Set (Set, empty, insert, delete, toList)
import Data.IORef

import Control.Monad.State hiding ((>=>))
import Control.Monad.Compose
import Control.Category ((>>>))

import System.IO
import System.Exit

import GHC.Conc

-- special gaming stuff

import Graphics.Qt

import Physics.Chipmunk as CM

import Game.FPSState
import Game.Events
import Game.Scene
import Game.Scene.Grounds
import Game.Objects
import Game.Objects.General
import Game.OptimizeChipmunks

import Editor.Conversions
import Editor.Scene (EObject, UnloadedEObject)


initialSize :: Size Int
initialSize = Size windowWidth windowHeight


gameMain :: IO ()
gameMain = do
    putStrLn "\ngame started..."
    hSetBuffering stdout NoBuffering

    app <- newQApplication
    window <- newAppWidget 1

    debugQtVersion

    debugNumberOfHecs

    when (fullscreen Configuration.development) $
        setFullscreenAppWidget window True

    directRendered <- directRenderingAppWidget window
    when (not directRendered) $
        warn "No direct rendering available :("
    paintEngineType <- paintEngineTypeAppWidget window
    warn ("paintEngine: " ++ show paintEngineType)

    (Just (levelname, eobjects)) <- load (Just "default")
    isr <- initialStateRef app window (flip initScene eobjects)
    ec <- qtRendering app window "QT_P_O_C" initialSize (renderCallback isr) globalCatcherGame

    readIORef isr >>= (fpsState >>> terminateFpsState)
    exitWith ec

-- prints the version number of qt and exits
debugQtVersion :: IO ()
debugQtVersion = do
    v <- qVersion
    putStrLn ("Qt-Version: " ++ v)

-- prints the number of HECs (see haskell concurrency)
debugNumberOfHecs :: IO ()
debugNumberOfHecs =
    putStrLn ("Number of HECs: " ++ show numCapabilities)


initScene :: Space -> Grounds UnloadedEObject -> IO Scene
initScene space =
    pure (fmap eObject2Object) >=>
    loadSpriteds >=>
    mkScene >=>
    optimizeChipmunks >=>
    sceneInitChipmunks space >=>
    sceneInitCollisions space


-- * used by the editor
initSceneFromEditor :: Space -> Grounds EObject -> IO Scene
initSceneFromEditor space =
    pure (fmap eObject2Object) >=>
    mkScene >=>
    optimizeChipmunks >=>
    sceneInitChipmunks space >=>
    sceneInitCollisions space


-- * running the state monad inside the render IO command
renderCallback :: IORef AppState -> [QtEvent] -> Ptr QPainter -> IO ()
renderCallback stateRef qtEvents painter = do
    let allEvents = toEitherList qtEvents []

    state <- readIORef stateRef
    ((), state') <- runStateT (renderWithState allEvents painter) state
    writeIORef stateRef state'

-- Application Monad and State

type AppMonad o = StateT AppState IO o

data AppState = AppState {
    qApplication :: Ptr QApplication,
    qWidget :: Ptr AppWidget,
    keyState :: Set AppButton,
    fpsState :: FpsState,
    cmSpace :: CM.Space,
    scene :: Scene,
    timer :: Ptr QTime
  }

setKeyState :: AppState -> Set AppButton -> AppState
setKeyState (AppState a b _ d e f g) c = AppState a b c d e f g
setFpsState :: AppState -> FpsState -> AppState
setFpsState (AppState a b c _ e f g) d = AppState a b c d e f g
setScene :: AppState -> Scene -> AppState
setScene    (AppState a b c d e _ g) f = AppState a b c d e f g


initialStateRef :: Ptr QApplication -> Ptr AppWidget -> (CM.Space -> IO Scene)
    -> IO (IORef AppState)
initialStateRef app widget scene = initialState app widget scene >>= newIORef

initialState :: Ptr QApplication -> Ptr AppWidget -> (CM.Space -> IO Scene) -> IO AppState
initialState app widget startScene = do
    fps <- initialFPSState
    cmSpace <- initSpace
    scene <- startScene cmSpace
    qtime <- newQTime
    startQTime qtime
    return $ AppState app widget Set.empty fps cmSpace scene qtime



-- State monad command for rendering (for drawing callback)
renderWithState :: [Either QtEvent JJ_Event] -> Ptr QPainter -> AppMonad ()
renderWithState events painter = do
    -- input events
    oldKeyState <- gets keyState
    let appEvents = concatMap (toAppEvent oldKeyState) events
    heldKeys <- actualizeKeyState appEvents

    -- stepping of the scene (includes rendering)
    now <- getSecs
    space <- gets cmSpace
    sc <- gets scene
    sc' <- liftIO $
        stepScene now space (ControlData appEvents heldKeys) painter sc

    -- FPS counter
    actualizeFPS

    puts setScene sc'
    case sc' of
        FinalState x -> liftIO (print x) >> sendQuit
        _ -> return ()

-- | returns the time passed since program start
getSecs :: AppMonad Double
getSecs = do
    qtime <- gets timer
    time <- liftIO $ elapsed qtime
    return (fromIntegral time / 10 ^ 3)


actualizeFPS :: StateT AppState IO ()
actualizeFPS = modifiesT fpsState setFpsState tickFPS

actualizeKeyState :: [AppEvent] -> AppMonad [AppButton]
actualizeKeyState events = do
    modifies keyState setKeyState (chainApp inner events)
    fmap toList $ gets keyState
  where
    inner :: AppEvent -> Set AppButton -> Set AppButton
    inner (Press k) ll = insert k ll
    inner (Release k) ll = delete k ll


sendQuit :: AppMonad ()
sendQuit = do
    widget <- gets qWidget
    app <- gets qApplication
    liftIO $ do
        setDrawingCallbackAppWidget widget Nothing
        quitQApplication




