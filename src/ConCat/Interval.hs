{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE IncoherentInstances #-}   -- ???

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP

-- | Interval analysis

module ConCat.Interval where

import Prelude hiding (id,(.),curry,uncurry,const)

import Control.Newtype

import ConCat.Misc ((:*),R,Yes1)
import ConCat.Category

type family Iv a

type instance Iv R = R :* R
type instance Iv Int = Int :* Int

type instance Iv (a :* b) = Iv a :* Iv b
type instance Iv (a -> b) = Iv a -> Iv b  -- ?

data IF a b = IF { unIF :: Iv a -> Iv b }

instance Newtype (IF a b) where
  type O (IF a b) = Iv a -> Iv b
  pack = IF
  unpack = unIF

-- TODO: use Newtype

instance Category IF where
  -- type Ok IF = Yes1
  id = IF id
  IF g . IF f = IF (g . f)

{-
    • Overlapping instances for Yes1 (Iv a) arising from a use of ‘id’
      Matching instances:
        instance forall k (a :: k). Yes1 a
          -- Defined at /Users/conal/Haskell/concat/src/ConCat/Misc.hs:98:10
      There exists a (perhaps superclass) match:
        from the context: Ok IF a
          bound by the type signature for:
                     id :: Ok IF a => IF a a
          at /Users/conal/Haskell/concat/src/ConCat/Interval.hs:30:3-4
      (The choice depends on the instantiation of ‘a’
       To pick the first instance above, use IncoherentInstances
       when compiling the other instance declarations)
-}

instance ProductCat IF where
  exl = IF exl
  exr = IF exr
  IF f &&& IF g = IF (f &&& g)

instance ClosedCat IF where
  apply = IF apply
  curry (IF f) = IF (curry f)
  uncurry (IF g) = IF (uncurry g)

-- TODO: Generalize via constIv method for HasIv
instance Iv b ~ (b :* b) => ConstCat IF b where
  const b = IF (const (b,b))

instance (Iv a ~ (a :* a), Num a, Ord a) => NumCat IF a where
  negateC = IF (\ (al,ah) -> (-ah, -al))
  addC = IF (\ ((al,ah),(bl,bh)) -> (al+bl,ah+bh))
  subC = addC . second negateC
  mulC = IF (\ ((al,ah),(bl,bh)) ->
               let cs = ((al*bl,al*bh),(ah*bl,ah*bh)) in
                 (min4 cs, max4 cs))
  powIC = error "powIC: not yet defined on IF"

type Two a = a :* a
type Four a = Two (Two a)

min4,max4 :: Ord a => Four a -> a
min4 ((a,b),(c,d)) = min (min a b) (min c d)
max4 ((a,b),(c,d)) = max (max a b) (max c d)
