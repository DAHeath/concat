-- Attempt to recode the 2nd exercise from the Udacity Deep Learning
-- course from Python to Haskell, using the new machinery in concat.
--
-- Original author: David Banas <capn.freako@gmail.com>
-- Original date:   August 31, 2017
--
-- Copyright (c) 2017 David Banas; all rights reserved World wide.
-----------------------------------------------------------------------
-- To run:
--
--   stack build :tst-dl2
--
-- You might also want to use stack's --file-watch flag for automatic recompilation.

{-# LANGUAGE CPP             #-}
{-# LANGUAGE RecordWildCards #-}

{-# OPTIONS_GHC -Wall                   #-}
{-# OPTIONS_GHC -Wno-missing-signatures #-}

module Main where

import Prelude hiding (readFile)

import Control.Arrow
import Data.Either
import qualified Data.Vector.Storable as VS
import System.Directory
import System.Random.Shuffle

import Codec.Picture
import Codec.Picture.Types

-- import ConCat.AD   (gradient)
-- import ConCat.Misc (R)

#if 0
-- A simple experiment with automatic differentiation, as a pipe cleaner.
f :: R -> R
f x = x * x + 2 * x + 1

f_name :: String
f_name = "x^2 + 2x + 1"

effectHaskell :: (Show a, Num a, Enum a, Show b) => String -> (a -> b) -> String
effectHaskell name func = unlines
  [ "The derivative of " ++ show f_name
  , "is producing the following input/output pairs:"
  , showFunc func
  , "You'll need to verify them."
  , "(Sorry, I'm not allowed to show you raw functions.)"
  ]

showFunc :: (Show a, Num a, Enum a, Show b) => (a -> b) -> String
showFunc f = show $ zip xs (map f xs)
  where xs = [0..2]

main :: IO ()
main = putStr $ effectHaskell f_name (gradient f)

#else
-- The real McCoy.

type Img = VS.Vector Double  -- concatenation of pixel rows
type Lbl = VS.Vector Double  -- N-element vector of label probabilities

-- | Given a training set and a test set, report the accuracy of test
-- set classification.
genOutput :: ([Lbl], [Img]) -> ([Lbl], [Img]) -> String
genOutput (lbls_trn, samps_trn) (lbls_tst, samps_tst) = unlines
  [ "\nAfter training on " ++ show (length lbls_trn) ++ " sample points,"
  , "my accuracy in classifying the test data is: " ++ show (accuracy (map VS.maxIndex lbls_tst) (map VS.maxIndex lbls_res))
  ]
    where lbls_res = trainAndClassify (lbls_trn, samps_trn) samps_tst

accuracy :: Eq a => [a] -> [a] -> Float
accuracy ref res = fromIntegral (length matches) / (fromIntegral (length ref) :: Float)
  where matches = filter (uncurry (==)) $ zip ref res

trainAndClassify :: ([Lbl], [Img]) -> [Img] -> [Lbl]
trainAndClassify = map . trainAndClassify'

-- | Train to a pair of lists containing labels and images, respectively, and return a classification function.
--
-- This is a "brute force" implemention that works as follows:
-- - Take the dot product of the input image with each image in the training set.
-- - Use the result of the dot product to scale each label vector of the training set.
-- - Accumulate those scaled label vectors.
-- - Normalize the final result, such that it forms a probability vector.
--   (The maximum value in the returned vector should indicate which letter was in the input image.)
--
-- Note: I'm assuming that the performance of this function will be unacceptable, and that
--       it will serve well to establish the motivation for taking a machine learning approach.
trainAndClassify' :: ([Lbl], [Img]) -> Img -> Lbl
trainAndClassify' trn_set img = VS.map (/ norm) v
  where v        = foldl func init_vec in_prs
        norm     = VS.sum v
        func     :: Lbl -> (Lbl, Img) -> Lbl
        func     = flip (vadd . uncurry (flip vscale) . second (vdot img))
        init_vec :: Lbl
        init_vec = VS.replicate (VS.length $ head $ fst trn_set) 0
        in_prs   :: [(Lbl,Img)]
        in_prs   = uncurry zip trn_set

vdot :: (Num a, VS.Storable a) => VS.Vector a -> VS.Vector a -> a
vdot v1 v2 = VS.sum $ VS.zipWith (*) v1 v2

vscale :: (Num a, VS.Storable a) => a -> VS.Vector a -> VS.Vector a
vscale s = VS.map (* s)

vadd :: (Num a, VS.Storable a) => VS.Vector a -> VS.Vector a -> VS.Vector a
vadd = VS.zipWith (+)

main :: IO ()
main = do
  (inputs, labels) <- dataset

  let trp      = length inputs * 70 `div` 100
      tep      = length inputs * 30 `div` 100

      -- training data
      trinputs = take trp inputs
      trlabels = take trp labels

      -- test data
      teinputs = take tep . drop trp $ inputs
      telabels = take tep . drop trp $ labels

  putStrLn $ genOutput (trlabels, trinputs) (telabels, teinputs)
#endif

-- | Found this code for reading in the notMNIST images, here:
-- https://github.com/mdibaiee/sibe/blob/master/examples/notmnist.hs
dataset :: IO ([VS.Vector Double], [VS.Vector Double])
dataset = do
  let dir = "notMNIST_small/"

  groups <- filter ((/= '.') . head) <$> listDirectory dir

  inputFiles <- mapM (listDirectory . (dir ++)) groups

  let n = 512 {-- minimum (map length inputFiles) --}
      numbers = map (`div` n) [0..n * length groups - 1]
      inputFilesFull = map (\(i, g) -> map ((dir ++ i ++ "/") ++) g) (zip groups inputFiles)


  inputImages <- mapM (mapM readImage . take n) inputFilesFull

  -- let names = map (take n) inputFilesFull

  -- let (l, r) = partitionEithers $ concat inputImages
  let (_, r) = partitionEithers $ concat inputImages
      inputs = map (fromPixels . convertRGB8) r
      labels = map (\i -> VS.replicate i 0 `VS.snoc` 1 VS.++ VS.replicate (9 - i) 0) numbers

      pairs  = zip inputs labels

  shuffled <- shuffleM pairs
  return (map fst shuffled, map snd shuffled)

  where
    fromPixels :: Image PixelRGB8 -> VS.Vector Double
    fromPixels img@Image { .. } =
      let pairs = [(x, y) | x <- [0..imageWidth - 1], y <- [0..imageHeight - 1]]
      in VS.fromList $ map iter pairs
      where
        iter (x, y) =
          let (PixelRGB8 r g b) = convertPixel $ pixelAt img x y
          in
            if r == 0 && g == 0 && b == 0 then 0 else 1

