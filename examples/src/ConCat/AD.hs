{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
-- {-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP

-- | Automatic differentiation

module ConCat.AD where

import Prelude hiding (id,(.),curry,uncurry,const,unzip)

import GHC.Generics(Par1(..))
import Control.Newtype (unpack)
-- import Data.Key (Zip(..))

import ConCat.Misc ((:*),Yes1)
import ConCat.Free.VectorSpace (HasV(..))
import ConCat.Free.LinearRow
-- The following import allows the instances to type-check. Why?
import qualified ConCat.Category as C
import ConCat.AltCat
-- import ConCat.Free.Diagonal (diagF)
import ConCat.GAD

-- Differentiable functions
type D s = GD (L s)

type instance GDOk (L s) = Yes1

-- instance ClosedCat (D s) where
--   apply = applyD
-- --   curry = curryD

-- applyD :: forall s a b. Ok2 (D s) a b => D s ((a -> b) :* a) b
-- applyD = D (\ (f,a) -> let (b,f') = andDeriv f a in
--               (b, _))

instance Num s => TerminalCat (D s) where
  it = linearD (const ()) zeroLM
  {-# INLINE it #-}

instance Ok (L s) b => ConstCat (D s) b where
  const b = D (const (b, zeroLM))
  {-# INLINE const #-}

instance Ok (L s) s => NumCat (D s) s where
  negateC = linearD negateC (scale (-1))
  addC    = linearD addC    jamLM
  mulC    = D (mulC &&& (\ (a,b) -> scale b `joinLM` scale a))
  powIC   = notDef "powC"       -- TODO
  {-# INLINE negateC #-}
  {-# INLINE addC    #-}
  {-# INLINE mulC    #-}
  {-# INLINE powIC   #-}
  -- subC = addC . second negateC -- experiment: same as default
  -- {-# INLINE subC    #-}

const' :: (a -> c) -> (a -> b -> c)
const' = (const .)

scalarD :: Ok (L s) s => (s -> s) -> (s -> s -> s) -> D s s s
scalarD f d = D (\ x -> let r = f x in (r, scale (d x r)))
{-# INLINE scalarD #-}

-- Use scalarD with const f when only r matters and with const' g when only x
-- matters.

scalarR :: Ok (L s) s => (s -> s) -> (s -> s) -> D s s s
scalarR f f' = scalarD f (\ _ -> f')
-- scalarR f x = scalarD f (const x)
-- scalarR f = scalarD f . const
{-# INLINE scalarR #-}

scalarX :: Ok (L s) s => (s -> s) -> (s -> s) -> D s s s
scalarX f f' = scalarD f (\ x _ -> f' x)
-- scalarX f f' = scalarD f (\ x y -> const (f' x) y)
-- scalarX f f' = scalarD f (\ x -> const (f' x))
-- scalarX f f' = scalarD f (const . f')
-- scalarX f f' = scalarD f (const' f')
-- scalarX f = scalarD f . const'
{-# INLINE scalarX #-}

square :: Num a => a -> a
square a = a * a
{-# INLINE square #-}

instance (Ok (L s) s, Fractional s) => FractionalCat (D s) s where
  recipC = scalarR recip (negate . square)
  {-# INLINE recipC #-}

instance (Ok (L s) s, Floating s) => FloatingCat (D s) s where
  expC = scalarR exp id
  sinC = scalarX sin cos
  cosC = scalarX cos (negate . sin)
  {-# INLINE expC #-}
  {-# INLINE sinC #-}
  {-# INLINE cosC #-}

-- instance LinearCat (L s) h where

-- instance (Applicative h, Foldable h) => LinearCat (D s) h where
--   -- fmapC (D f) =
--   --   D (\ as -> let (cs,fs') = unzip (fmap f as) in (cs, L (foo (diagF zeroLM fs'))))
--   zipC  = linearD zipC zipC
--   sumC  = linearD sumC sumC

-- foo :: h (h (L s a b)) -> V s (h b) (V s (h a) s)
-- foo = undefined

#if 0

f :: a -> b :* L s a b
as :: h a
f <$> as :: h (b :* L s a b)
unzip (f <$> as) :: h b :* h (L s a b)
bs :: h b
fs' :: h (L s a b)
zeroLM :: L s a b
diagF zeroLM fs' :: h (h (L s a b))

need :: L s (h a) (h b)
     =~ V s (h b) (V s (h a) s)

#endif

-- diagF zeroLM fs'

-- diagF :: (Applicative f, Keyed f, Adjustable f) => a -> f a -> f (f a)

unzip :: Functor f => f (a :* b) -> f a :* f b
unzip ps = (fst <$> ps, snd <$> ps)

-- TODO: Generalize from D s to GD k. zipC and sumC come easily, but maybe I
-- need to generalize diagF to a method.

{--------------------------------------------------------------------
    Differentiation interface
--------------------------------------------------------------------}

-- andDer :: forall a b . (a -> b) -> (a -> b :* LR a b)
andDer :: forall s a b . (a -> b) -> (a -> b :* L s a b)
andDer = andDeriv
{-# INLINE andDer #-}

der :: forall s a b . (a -> b) -> (a -> L s a b)
der = deriv
{-# INLINE der #-}

type IsScalar s = V s s ~ Par1

gradient :: (HasV s a, IsScalar s) => (a -> s) -> a -> a
-- gradient :: HasV R a => (a -> R) -> a -> a
gradient f = gradientD (toCcc f)
{-# INLINE gradient #-}

gradientD :: (HasV s a, IsScalar s) => D s a s -> a -> a
-- gradientD :: HasV R a => D R a R -> a -> a
gradientD (D h) = unV . unPar1 . unpack . snd . h
{-# INLINE gradientD #-}


--                             f :: a -> s
--                         der f :: a -> L s a s
--                unpack . der f :: a -> V s s (V s a s)
--                               :: a -> Par1 (V s a s)
--       unPar1 . unpack . der f :: a -> V s a s
-- unV . unPar1 . unpack . der f :: a -> a

