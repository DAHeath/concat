{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE CPP #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-unused-imports #-} -- TEMP

-- | 

module ConCat.Distrib where

import Prelude hiding ((.))

import Data.Map (Map)
import qualified Data.Map as M

import ConCat.Misc (R)
import ConCat.AltCat
import qualified ConCat.Category

newtype Distrib a b = Distrib (a -> Map b R)

-- TODO: generalize Distrib to a category transformer

instance Category Distrib where
  type Ok Distrib = Ord
  id = Distrib (\ a -> M.singleton a 1)
  Distrib g . Distrib f = Distrib h
   where
     -- h = M.fromListWith (+) . concatMap (rescale . first (M.toList . g)) . M.toList . f
     -- rescale (w,q) = second (q *) <$> w

     -- h a = M.fromListWith (+) [ (c,p*q) | (b,p) <- M.toList (f a), (c,q) <- M.toList (g b) ]

     h a = M.unionsWith (+) [ (p *) <$> g b | (b,p) <- M.toList (f a) ]

     -- h a = M.unionsWith (+) (w <$> M.toList (f a)) where w (b,p) = (p *) <$> g b

     -- h = M.unionsWith (+) . fmap w . M.toList . f where w (b,p) = (p *) <$> g b

     -- h = M.unionsWith (+) . fmap (\ (b,p) -> (p *) <$> g b) . M.toList . f

#if 0

f :: a -> Map b R
g :: b -> Map c R

toList . f :: a -> [b :* R]
map (first g) . toList . f :: a -> [Map c R :* R]
map (first (toList . g)) . toList . f :: a -> [[c :* R] :* R]
map (rescale . first (toList . g)) . toList . f :: a -> [[c :* R]]
concatMap (rescale . first (toList . g)) . toList . f :: a -> [c :* R]
fromListWith . concatMap (rescale . first (toList . g)) . toList . f :: a -> [c :* R]

#endif
