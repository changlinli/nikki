{-# language MultiParamTypeClasses, DeriveDataTypeable, NamedFieldPuns #-}

module Sorts.Switch (
    sorts, 
    Switch,
    triggered,
    unwrapSwitch,
  ) where


import Data.Generics
import Data.Abelian
import Data.Set (member)

import System.FilePath

import Physics.Chipmunk as CM

import Graphics.Qt hiding (scale)

import Base

import Object

import Sorts.Tiles (tileShapeAttributes)
import Sorts.Nikki (nikkiMass)


-- * configuration

stampMaterialMass = 1.7677053824362605


-- * loading

sorts :: RM [Sort_]
sorts = do
    boxOffPix <- mkPath "switch-standard-off" >>= loadPixmap (Position 1 1)
    boxOnPix <- mkPath "switch-standard-on" >>= loadPixmap (Position 1 1)
    stampPix <- mkPath "switch-platform" >>= loadPixmap (Position 1 1)
    return $ map Sort_ [SwitchSort boxOffPix boxOnPix stampPix]

mkPath :: String -> RM FilePath
mkPath name = getDataFileName (pngDir </> "objects" </> name <.> "png")


data SwitchSort
    = SwitchSort {
        boxOffPix :: Pixmap,
        boxOnPix :: Pixmap,
        stampPix :: Pixmap
      }
  deriving (Typeable, Show)

data Switch
    = Switch {
        boxChipmunk :: Chipmunk,
        stampChipmunk :: Chipmunk,
        triggerChipmunk :: Chipmunk,
        triggerShape :: Shape,
        triggered :: Bool
      }
  deriving (Typeable, Show)

unwrapSwitch :: Object_ -> Maybe Switch
unwrapSwitch (Object_ sort o) = cast o

instance Sort SwitchSort Switch where
    sortId _ = SortId "switch/levelExit"
    size _ = boxSize +~ Size 0 (fromUber 7)

    sortRender sort ptr _ = do
        renderPixmapSimple ptr (stampPix sort)
        translate ptr (Position 0 (fromUber 7))
        renderPixmapSimple ptr (boxOffPix sort)

    initialize sort (Just space) ep Nothing = do
        let ((boxShapes, boxBaryCenterOffset), triggerShapes, (stampShapes, stampBaryCenterOffset)) =
                    switchShapes

            boxPos = Vector (editorX ep) (editorY ep - height boxSize)
                     +~ boxBaryCenterOffset
        boxChip <- initChipmunk space (boxAttributes boxPos) boxShapes boxBaryCenterOffset
        triggerChip <- initChipmunk space (boxAttributes boxPos) triggerShapes boxBaryCenterOffset
        let [triggerShape] = shapes triggerChip

        let stampPos =
                Vector (editorX ep)
                       (editorY ep - height boxSize - yPlatformDistance - height platformSize)
                       +~ stampBaryCenterOffset
            stampAttributes = stampBodyAttributes stampPos
        stampChip <- initChipmunk space stampAttributes stampShapes stampBaryCenterOffset

        let switch = Switch boxChip stampChip triggerChip triggerShape False
        updateAntiGravity switch

        return switch 

    immutableCopy s@Switch{boxChipmunk, stampChipmunk} = do
        newBoxChipmunk <- CM.immutableCopy boxChipmunk
        newStampChipmunk <- CM.immutableCopy stampChipmunk
        return s{boxChipmunk = newBoxChipmunk, stampChipmunk = newStampChipmunk}

    chipmunks (Switch a b c _ _) = [a, b, c]

    updateNoSceneChange sort mode now contacts cd switch@Switch{triggered = False} =
        if triggerShape switch `member` triggers contacts then do
            let new = switch{triggered = True}
            updateAntiGravity new
            return new
          else
            return switch
    updateNoSceneChange s _ _ _ _ o = return o

    render switch sort ptr offset now = do
        renderChipmunk ptr offset (stampPix sort) (stampChipmunk switch)
        let boxPix = if triggered switch then boxOnPix sort else boxOffPix sort
        renderChipmunk ptr offset boxPix (boxChipmunk switch)


boxAttributes :: Vector -> BodyAttributes
boxAttributes pos =
    StaticBodyAttributes {
        CM.position = pos
      }

stampBodyAttributes :: CM.Position -> BodyAttributes
stampBodyAttributes =
    mkMaterialBodyAttributes stampMaterialMass stampShapes
  where
    (_, _, (stampShapeDescriptions, _)) = switchShapes
    stampShapes = map shapeType stampShapeDescriptions




innerStampShapeAttributes :: ShapeAttributes
innerStampShapeAttributes =
    ShapeAttributes {
        elasticity = 0,
        friction = 0,
        CM.collisionType = TileCT
      }

triggerShapeAttributes :: ShapeAttributes
triggerShapeAttributes =
    ShapeAttributes {
        elasticity = 0.1,
        friction = 1,
        CM.collisionType = TriggerCT
      }


boxSize = Size (fromUber 30) (fromUber 15)


switchShapes :: (([ShapeDescription], Vector),
                 [ShapeDescription],
                 ([ShapeDescription], Vector))
switchShapes =
    ((map (mkShapeDescription tileShapeAttributes) box, boxBaryCenterOffset),
     [mkShapeDescription triggerShapeAttributes trigger],
     (stamp, stampBaryCenterOffset))

-- Configuration
platformSize = Size (width boxSize) (fromUber 5)
outerWallThickness = 32
-- size of the shaft, that  can be seen outside the box
shaftSize = Size (fromUber 11) yPlatformDistance
-- y distance between platform and box
yPlatformDistance = fromUber 2
innerPadding = 4
shaftPadding = 0.2
openingWidth = width shaftSize + 2 * shaftPadding
triggerHeight = 0.2

-- calculated
boxBaryCenterOffset = Vector (width boxSize / 2) (height boxSize / 2)
-- the stampBaryCenterOffset is exactly below the shaft
-- and above the innerStampThingie
stampBaryCenterOffset = Vector (width boxSize / 2)
    (height platformSize + yPlatformDistance)

wedgeEpsilon = 1


box = (
    -- left to shaft opening
    LineSegment
        (Vector (boxLeft + outerWallThickness) boxUpper)
        (Vector (boxLeft + outerToOpening) boxUpper)
        0 :
    -- right to opening
    LineSegment
        (Vector (boxRight - outerToOpening) boxUpper)
        (Vector (boxRight - outerWallThickness) boxUpper)
        0 :
    -- left side
    Polygon [
        Vector boxLeft boxUpper,
        Vector boxLeft boxLower,
        Vector (boxLeft + outerWallThickness) (boxLower - wedgeEpsilon),
        Vector (boxLeft + outerWallThickness) boxUpper
      ] :
    -- bottom
    Polygon [
        Vector (boxLeft + wedgeEpsilon) (boxLower - outerWallThickness),
        Vector boxLeft boxLower,
        Vector boxRight boxLower,
        Vector (boxRight - wedgeEpsilon) (boxLower - outerWallThickness)
      ] :
    -- right side
    Polygon [
        Vector (boxRight - outerWallThickness) boxUpper,
        Vector (boxRight - outerWallThickness) (boxLower - wedgeEpsilon),
        Vector boxRight boxLower,
        Vector boxRight boxUpper
      ] :
    [])

stamp :: [ShapeDescription]
stamp = [
    (mkShapeDescription tileShapeAttributes platform),
    (mkShapeDescription innerStampShapeAttributes shaft),
    (mkShapeDescription innerStampShapeAttributes innerStampThingie)
    ]
platform = mkRect
    (Position (- width platformSize / 2) (- height shaftSize - height platformSize))
    platformSize
shaft = mkRect
    (Position (- (width shaftSize / 2)) (- height shaftSize - shaftOverlap))
    (shaftSize +~ Size 0 (2 * shaftOverlap))
  where
    -- The shaft has to overlap the other stamp shapes.
    -- The shaftOverlap is not taken into consideration in shaftSize.
    shaftOverlap = fromUber 1
innerStampThingie = mkRect
    (Position (- (width boxSize / 2) + outerWallThickness + innerPadding) 0)
    (Size (width boxSize - 2 * (outerWallThickness + innerPadding))
        (height boxSize - outerWallThickness - yPlatformDistance))
trigger =
    mkRect (Position
                (- (outerWallThickness / 2))
                (boxLower - outerWallThickness - triggerHeight))
            (Size outerWallThickness triggerHeight)

outerToOpening = ((width boxSize - openingWidth) / 2)

boxLeft = - boxRight
boxRight = width boxSize / 2
boxLower = height boxSize / 2
boxUpper = - boxLower


-- * Physics

-- | switches the anti-gravity on or off that pushes the switch stamp up.
updateAntiGravity :: Switch -> IO ()
updateAntiGravity switch = do
    stampMass <- getMass $ stampChipmunk switch
    applyOnlyForce (body $ stampChipmunk switch) (force stampMass) zero
  where
    force stampMass =
        if not $ triggered switch then
            (Vector 0 (- (gravity * (stampMass + nikkiMass * 0.4))))
        else
            zero
