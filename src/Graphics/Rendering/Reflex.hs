{-# LANGUAGE CPP               #-}
{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE GADTs             #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE ViewPatterns      #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Graphics.Rendering.Reflex
-- Copyright   :  (c) 2015 diagrams-reflex team (see LICENSE)
-- License     :  BSD-style (see LICENSE)
-- Maintainer  :  diagrams-discuss@googlegroups.com
--
-- Lower level tools for creating SVGs.
--
-----------------------------------------------------------------------------

module Graphics.Rendering.Reflex
    ( RenderM
    , Element(..)
    , Attrs
    -- , AttributeValue
    -- , svgHeader
    , renderPath
    -- , renderClip
    , renderText
    -- , renderDImage
    -- , renderDImageEmb
    , renderStyles
    , renderMiterLimit
    -- , renderFillTextureDefs
    -- , renderFillTexture
    -- , renderLineTextureDefs
    -- , renderLineTexture
    -- , dataUri
    , getNumAttr
    ) where

import qualified Data.Text as T
#if __GLASGOW_HASKELL__ < 710
import           Data.Foldable               (foldMap)
#endif

-- from mtl
import Control.Monad.Reader as R

-- from diagrams-lib
import           Diagrams.Prelude            hiding (Attribute, Render, with, text)
import           Diagrams.TwoD.Path          (getFillRule)
import           Diagrams.TwoD.Text
import           Diagrams.Core.Transform     (matrixHomRep)

-- from containers
import Data.Map (Map)
import qualified Data.Map as M

-- from base64-bytestring, bytestring
-- import qualified Data.ByteString.Base64.Lazy as BS64
-- import qualified Data.ByteString.Lazy.Char8  as BS8

data Element = Element
               T.Text
               (Map T.Text T.Text)
               [Element]
  | SvgText T.Text

type RenderM = Reader (Style V2 Double) [Element]

instance Monoid RenderM where
  mempty = return []
  mappend a b = mappend <$> a <*> b

type AttributeValue = T.Text

type Attrs = Map T.Text T.Text

showText :: Show a => a -> T.Text
showText = T.pack . show

getNumAttr :: AttributeClass (a Double) => (a Double -> t) -> Style v Double -> Maybe t
getNumAttr f = (f <$>) . getAttr

renderPath :: Path V2 Double -> RenderM
renderPath trs
    | makePath == "" = return []
    | otherwise = do
        sty <- ask
        return [ Element "path" (M.insert "d" makePath $ renderStyles sty) [] ]
  where
    makePath = foldMap renderTrail (op Path trs)

renderTrail :: Located (Trail V2 Double) -> AttributeValue
renderTrail (viewLoc -> (P (V2 x y), t)) =
  T.concat [ "M " , showText x, ",", showText y, " " ]
  <> withTrail renderLine renderLoop t
  where
    renderLine = foldMap renderSeg . lineSegments
    renderLoop lp =
      case loopSegments lp of
        -- let z handle the last segment if it is linear
        (segs, Linear _) -> foldMap renderSeg segs

        -- otherwise we have to emit it explicitly
        _ -> foldMap renderSeg (lineSegments . cutLoop $ lp)
      <> "Z"

renderSeg :: Segment Closed V2 Double -> AttributeValue
renderSeg (Linear (OffsetClosed (V2 x 0))) = T.concat [ "h ", showText x, " "]
renderSeg (Linear (OffsetClosed (V2 0 y))) = T.concat [ "v ", showText y, " " ]
renderSeg (Linear (OffsetClosed (V2 x y))) = T.concat [ "l ", showText x, ",", showText y, " "]
renderSeg (Cubic  (V2 x0 y0) (V2 x1 y1) (OffsetClosed (V2 x2 y2))) =
  T.concat [ " c ", showText x0, ",", showText y0, " ", showText x1, ",", showText y1
         , " ", showText x2, " ", showText y2]

renderText :: Text Double -> RenderM
renderText (Text tt tAlign str) = return [ Element "text" attrs [ SvgText $ T.pack str ] ]
  where
   attrs = M.fromList
     [ ("transform", transformMatrix)
     , ("dominant_baseline", vAlign)
     , ("text_anchor", hAlign)
     , ("stroke", "none")
     ]
   vAlign = case tAlign of
     BaselineText -> "alphabetic"
     BoxAlignedText _ h -> case h of -- A mere approximation
       h' | h' <= 0.25 -> "text-after-edge"
       h' | h' >= 0.75 -> "text-before-edge"
       _ -> "middle"
   hAlign = case tAlign of
     BaselineText -> "start"
     BoxAlignedText w _ -> case w of -- A mere approximation
       w' | w' <= 0.25 -> "start"
       w' | w' >= 0.75 -> "end"
       _ -> "middle"
   t                   = tt <> reflectionY
   [[a,b],[c,d],[e,f]] = matrixHomRep t
   transformMatrix     = matrix a b c d e f

-- | Specifies a transform in the form of a transformation matrix
matrix :: (Show a, RealFloat a) =>  a -> a -> a -> a -> a -> a -> T.Text
matrix a b c d e f =  T.concat
  [ "matrix(", showText a, ",", showText b, ",",  showText c
  , ",",  showText d, ",", showText e, ",",  showText f, ")"]

renderStyles :: Style v Double -> Attrs
renderStyles s = foldMap ($ s) $
  [ renderLineTexture
  , renderFillTexture
  , renderLineWidth
  , renderLineCap
  , renderLineJoin
  , renderFillRule
  , renderDashing
  , renderOpacity
  , renderFontSize
  , renderFontSlant
  , renderFontWeight
  , renderFontFamily
  -- , renderSvgId
  -- , renderSvgClass
  , renderMiterLimit ]

renderMiterLimit :: Style v Double -> Attrs
renderMiterLimit s = renderAttr "stroke-miterlimit" miterLimit
 where miterLimit = getLineMiterLimit <$> getAttr s

renderOpacity :: Style v Double -> Attrs
renderOpacity s = renderAttr "opacity" o
 where o = getOpacity <$> getAttr s

renderFillRule :: Style v Double -> Attrs
renderFillRule s = renderTextAttr "fill-rule" fr
  where fr = (fillRuleToText . getFillRule) <$> getAttr s
        fillRuleToText :: FillRule -> AttributeValue
        fillRuleToText Winding = "nonzero"
        fillRuleToText EvenOdd = "evenodd"

renderLineWidth :: Style v Double -> Attrs
renderLineWidth s = renderAttr "stroke-width" lWidth
  where lWidth = getNumAttr getLineWidth s

renderLineCap :: Style v Double -> Attrs
renderLineCap s = renderTextAttr "stroke-linecap" lCap
  where lCap = (lineCapToText . getLineCap) <$> getAttr s
        lineCapToText :: LineCap -> AttributeValue
        lineCapToText LineCapButt   = "butt"
        lineCapToText LineCapRound  = "round"
        lineCapToText LineCapSquare = "square"

renderLineJoin :: Style v Double -> Attrs
renderLineJoin s = renderTextAttr "stroke-linejoin" lj
  where lj = (lineJoinToText . getLineJoin) <$> getAttr s
        lineJoinToText :: LineJoin -> AttributeValue
        lineJoinToText LineJoinMiter = "miter"
        lineJoinToText LineJoinRound = "round"
        lineJoinToText LineJoinBevel = "bevel"

renderDashing :: Style v Double -> Attrs
renderDashing s = renderTextAttr "stroke-dasharray" arr <>
                  renderAttr "stroke-dashoffset" dOffset
 where
  getDasharray  (Dashing a _) = a
  getDashoffset (Dashing _ o) = o
  dashArrayToStr              = T.intercalate "," . map showText
  -- Ignore dashing if dashing array is empty
  checkEmpty (Just (Dashing [] _)) = Nothing
  checkEmpty other                 = other
  dashing'                    = checkEmpty $ getNumAttr getDashing s
  arr                         = (dashArrayToStr . getDasharray) <$> dashing'
  dOffset                     = getDashoffset <$> dashing'

renderFontSize :: Style v Double -> Attrs
renderFontSize s = renderTextAttr "font-size" fs
 where
  fs = getNumAttr ((<> "px") . showText . getFontSize) s

renderFontSlant :: Style v Double -> Attrs
renderFontSlant s = renderTextAttr "font-style" fs
 where
  fs = (fontSlantAttr . getFontSlant) <$> getAttr s
  fontSlantAttr :: FontSlant -> AttributeValue
  fontSlantAttr FontSlantItalic  = "italic"
  fontSlantAttr FontSlantOblique = "oblique"
  fontSlantAttr FontSlantNormal  = "normal"

renderFontWeight :: Style v Double -> Attrs
renderFontWeight s = renderTextAttr "font-weight" fw
 where
  fw = (fontWeightAttr . getFontWeight) <$> getAttr s
  fontWeightAttr :: FontWeight -> AttributeValue
  fontWeightAttr FontWeightNormal = "normal"
  fontWeightAttr FontWeightBold   = "bold"

renderFontFamily :: Style v Double -> Attrs
renderFontFamily s = renderTextAttr  "font-family" ff
 where
  ff = (T.pack . getFont) <$> getAttr s

-- | Render a style attribute if available, empty otherwise.
renderAttr :: Show s => T.Text -> Maybe s -> Attrs
renderAttr attrName valM = maybe mempty (\v -> M.singleton attrName $ showText v) valM

renderTextAttr :: T.Text -> Maybe AttributeValue -> Attrs
renderTextAttr attrName valM = maybe mempty (\v -> M.singleton attrName v) valM

-- TODO add gradients
-- | Render solid colors, ignore gradients for now.
renderFillTexture :: Style v Double -> Attrs
renderFillTexture s = case getNumAttr getFillTexture s of
  Just (SC (SomeColor c)) ->
    M.fromList [("fill", fillColorRgb), ("fill-opacity", fillColorOpacity)]
    where
      fillColorRgb     = colorToRgbString c
      fillColorOpacity = colorToOpacity c
  _     -> mempty

renderLineTexture :: Style v Double -> Attrs
renderLineTexture s = case getNumAttr getLineTexture s of
  Just (SC (SomeColor c)) -> M.fromList
    [ ("stroke", lineColorRgb), ("stroke-opacity", lineColorOpacity) ]
    where
      lineColorRgb     = colorToRgbString c
      lineColorOpacity = colorToOpacity c
  _ -> mempty

colorToRgbString :: forall c . Color c => c -> T.Text
colorToRgbString c = T.concat
  [ "rgb("
  , int r, ","
  , int g, ","
  , int b
  , ")" ]
 where
   int d     = showText $ (round (d * 255) :: Int)
   (r,g,b,_) = colorToSRGBA c

colorToOpacity :: forall c . Color c => c -> T.Text
colorToOpacity c = showText a
 where (_,_,_,a) = colorToSRGBA c
