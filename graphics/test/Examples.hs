{-# LANGUAGE FlexibleContexts #-}
-- To run:
-- 
--   stack build :graphics-examples
--
--   stack build :graphics-trace >& ~/Haskell/concat/graphics/out/o1
-- 
-- You might also want to use stack's --file-watch flag for automatic recompilation.

{-# LANGUAGE CPP                 #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds     #-}
{-# LANGUAGE TypeApplications    #-}

{-# OPTIONS_GHC -Wall #-}

{-# OPTIONS_GHC -Wno-missing-signatures #-}
{-# OPTIONS_GHC -Wno-unused-imports #-}

{-# OPTIONS_GHC -dsuppress-idinfo #-}
{-# OPTIONS_GHC -dsuppress-uniques #-}
{-# OPTIONS_GHC -dsuppress-module-prefixes #-}

-- {-# OPTIONS_GHC -ddump-simpl #-}

-- {-# OPTIONS_GHC -ddump-rule-rewrites #-}
-- {-# OPTIONS_GHC -fsimpl-tick-factor=250 #-}  -- default 100

-- {-# OPTIONS -fplugin-opt=ConCat.Plugin:trace #-}

{-# OPTIONS_GHC -fno-do-lambda-eta-expansion #-}

module Main where

import Control.Applicative (liftA2,liftA3)
import GHC.Float (int2Double)   -- TEMP

import ConCat.Misc ((:*),R,sqr,magSqr,Unop,Binop,inNew,inNew2)
import ConCat.Circuit (GenBuses,(:>))
import ConCat.Graphics.GLSL (genHtml,runHtml)
import ConCat.Graphics.Image
import qualified ConCat.RunCircuit as RC
import ConCat.Syntactic (Syn,render)
import ConCat.AltCat (Ok2,ccc,(:**:)(..))
import qualified ConCat.AltCat as A

import ConCat.Rebox () -- necessary for reboxing rules to fire

main :: IO ()
main = sequence_
  [ putChar '\n' -- return ()

  -- , runSynCirc "example-a" $ ccc $ \ t (x::R,y) -> x > y + sin t

  -- , runSynCirc "example-a2" $ ccc $
  --     \ (t :: R) -> let s = sin t in \ (x,y) -> x > y + s

  -- , runSynCirc "example-a2-uncurry" $ ccc $
  --     uncurry (\ (t :: R) -> let s = sin t in \ (x,y) -> x > y + s)

  -- , runSynCirc "example-b" $ ccc $ \ (t :: R) -> let s = sin t in \ (x,y) -> x > y + s

  -- , runSynCirc "example-c" $ ccc exampleC

  -- , runSynCirc "example-d" $ ccc exampleD

  -- , runSynCirc "example-c2" $ exampleC2

  -- , runSynCirc "example-c3p" $ exampleC3'

  -- , runHtml "example-a" $ ccc $ \ t (x,y) -> x > y + sin t

  -- , runSynCirc "disk-sizing-uncurry"   $ ccc $ uncurry (disk . cos)

  , runHtml "disk-sizing"   $ ccc $ disk . cos
  -- , genHtml "wobbly-disk" $ ccc $
  --     \ t -> disk' (0.75 + 0.25 * cos t)
  -- , genHtml "diag-plus-im"  $ ccc $ \ t ((x,y) :: R2) -> x + sin t > y
  -- , genHtml "diag-disk-turning" $ ccc $
  --     \ t -> udisk `intersectR` rotate t xPos
  -- , genHtml "checker-rotate" $ ccc $ \ t -> rotate t checker13
  -- , genHtml "diag-disk-turning-sizing" $ ccc $
  --     \ t -> disk' (cos t) `xorR` rotate t xyPos

  -- , genHtml "orbits1" $ ccc $ orbits1
  -- , genHtml "checker-orbits1" $ ccc $
  --     liftA2 xorR (const checker13) orbits1
  -- , genHtml "checker-orbits2" $ ccc $ \ t ->
  --     uscale (sin t + 1.05) checker `xorR` orbits1 t
  -- , genHtml "checker-orbits3" $ ccc $ \ t -> 
  --     orbits1 t `intersectR` checker13
  -- , genHtml "checker-orbits4" $ ccc $ \ t -> 
  --     orbits1 t `intersectR` translate (t/10,0) checker13
  -- , genHtml "checker-orbits5" $ ccc $ \ t -> 
  --     orbits1 t `intersectR` rotate (t/10) checker13
  -- , runHtml "orbits2" $ ccc $ orbits2
  -- , runHtml "checker-orbits6" $ ccc $ \ t ->
  --     orbits2 t `intersectR` rotate (t/10) checker13

  ]

{--------------------------------------------------------------------
    Testing utilities
--------------------------------------------------------------------}

type GO a b = (GenBuses a, Ok2 (:>) a b)

type EC = Syn :**: (:>)

runSyn :: Syn a b -> IO ()
runSyn syn = putStrLn ('\n' : render syn)

runCirc :: GO a b => String -> (a :> b) -> IO ()
runCirc nm circ = RC.run nm [] circ

runSynCirc :: GO a b => String -> EC a b -> IO ()
runSynCirc nm (syn :**: circ) = runSyn syn >> runCirc nm circ

runCircHtml :: GenBuses a => String -> (a :> Region) -> IO ()
runCircHtml nm circ = runCirc nm circ >> runHtml nm circ

-- TODO: Fix runCircHtml to construct the graph once instead of twice.

{--------------------------------------------------------------------
    Misc
--------------------------------------------------------------------}

later :: Num t => t -> Unop (t -> a)
later dt f = f . subtract dt

orbits1 :: R -> Region
orbits1 z = translate (cos theta,0) d `xorR` translate (0,sin theta) d
 where
   d = disk (1/2)
   theta = z * 2

orbits2 :: R -> Region
orbits2 z =
  translate (cos theta,0) (disk r1) `xorR` translate (0,sin theta) (disk r2)
 where
   r1 = (sin (z * 3) + 1) / 2
   r2 = 1 - r1
   theta = z * 2

checker13 :: Region
checker13 = uscale (1/3) checker

exampleB :: R -> Region
exampleB = \ t -> let s = sin t in \ (x,y) -> x > y + s

exampleC :: Double -> Double -> Double
exampleC = \ t -> let s = sin t in \ x -> x + s

exampleC2 :: EC R (R -> R)
exampleC2 = A.curry (A.addC A.. (A.exr A.&&& A.sinC A.. A.exl))

exampleC3 :: EC R (R -> R)
exampleC3 = A.curry (A.addC A.. (A.exr A.&&& A.exl)) A.. A.sinC

exampleC3' :: ( A.ClosedCat k, A.FloatingCat k R, A.NumCat k R
              , A.Ok k (R :* R), A.Ok k (R -> R) )
           => R `k` (R -> R)
exampleC3' = A.curry (A.addC A.. (A.exr A.&&& A.exl)) A.. A.sinC

-- Swap addends
exampleD :: Double -> Double -> Double
exampleD = \ t -> let s = sin t in \ x -> s + x
