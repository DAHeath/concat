{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeOperators #-}

{-# OPTIONS_GHC -Wall #-}

-- | Some experiments in formulating constrained linear optimization problems.

module ConCat.Free.LinearCol where

import Prelude hiding (id,(.),zipWith)

import GHC.Generics (Par1(..),(:*:)(..),(:.:)(..))
import Data.Constraint

import Data.Pointed (Pointed(..))
import Data.Key (Keyed(..),Zip(..),Adjustable(..))

import Control.Newtype

import ConCat.Misc (inNew,inNew2)
import ConCat.Orphans ()
import ConCat.Free.VectorSpace
import ConCat.Category

{--------------------------------------------------------------------
    Linear maps
--------------------------------------------------------------------}

-- Linear map from a s to b s
infixr 1 :-*
type (a :-* b) s = a (b s)

-- TODO: consider instead
-- 
--   type Linear = (:.:)
-- 
-- so that Linear itself forms a vector space.

-- Apply a linear map
infixr 9 $*
($*), lapplyL :: (Zip a, Foldable a, Zip b, Pointed b, Num s)
              => (a :-* b) s -> a s -> b s
bs $* a = sumV (zipWith (*^) a bs)

lapplyL = ($*)

zeroL :: (Pointed a, Pointed b, Num s) => (a :-* b) s
zeroL = point zeroV

#if 0
{--------------------------------------------------------------------
    Affine maps
--------------------------------------------------------------------}

-- Affine map from a s to b s
type Affine a b s = (a :*: Par1 :-* b) s

-- Apply an affine map
affine :: (Zip a, Foldable a, Zip b, Pointed b, Num s)
       => Affine a b s -> a s -> b s
affine bs' a = bs' $* (a :*: Par1 1)

-- Compose affine transformations
(@..) :: (Zip b, Zip c, Pointed c, Foldable b, Num s, Functor a)
      => Affine b c s -> Affine a b s -> Affine a c s
bc @.. ab = affine bc <$> ab

{--------------------------------------------------------------------
    Constrained linear optimization
--------------------------------------------------------------------}

-- Affine function and affine constraints. When b == Id and s is
-- ordered, we can solve as a constrained linear optimization problem.
-- The generality over b improves composability.
data LinOpt a b s = forall c. Foldable c => LO (Affine a b s, Affine a c s)

-- TODO: add existentials by wrapping with ExistArg. I'll have to
-- bridge the gap between the Category classes and the
-- almost-instances above.
#endif

---- Category

-- Identity linear map
idL :: (Adjustable m, Keyed m, Pointed m, Num r)
    => (m :-* m) r
idL = mapWithKey (flip replace 1) zeroL

-- mapWithKey :: Keyed f => (Key f -> a -> b) -> f a -> f b
-- replace :: Adjustable f => Key f -> a -> f a -> f a

-- Compose linear transformations
(@.) :: (Functor a, Foldable b, Zip b, Pointed c, Zip c, Num s)
     => (b :-* c) s -> (a :-* b) s -> (a :-* c) s
bc @. ab = (bc $*) <$> ab

-- (@.) = fmap . ($*)

---- Product

exlL :: (Pointed a, Keyed a, Adjustable a, Pointed b, Num s)
     => (a :*: b :-* a) s
exlL = idL :*: zeroL

exrL :: (Pointed b, Keyed b, Adjustable b, Pointed a, Num s)
     => (a :*: b :-* b) s
exrL = zeroL :*: idL

forkL :: Zip a => (a :-* b) s -> (a :-* c) s -> (a :-* b :*: c) s
forkL = zipWith (:*:)

---- Coproduct as direct sum (represented as Cartesian product)

inlL :: (Pointed a, Keyed a, Adjustable a, Pointed b, Num s)
     => (a :-* a :*: b) s
inlL = (:*: zeroV) <$> idL

inrL :: (Pointed a, Pointed b, Keyed b, Adjustable b, Num s)
     => (b :-* a :*: b) s
inrL = (zeroV :*:) <$> idL

joinL :: (a :-* c) s -> (b :-* c) s -> (a :*: b :-* c) s
joinL = (:*:)

newtype (f :=> g) s = Fun ((f :-* g) s)

{--------------------------------------------------------------------
    Experiment
--------------------------------------------------------------------}

type Linear' = (:.:)

linear' :: (Zip b, Zip a, Pointed b, Foldable a, Num s)
        => Linear' a b s -> a s -> b s
linear' (Comp1 ns) a = sumV (zipWith (*^) a ns)

zeroL' :: (Pointed b, Pointed a, Num s) => Linear' a b s
zeroL' = Comp1 (point zeroV)

idL' :: (Adjustable a, Keyed a, Pointed a, Num s)
     => Linear' a a s
idL' = (inNew . mapWithKey) (flip replace 1) zeroL'

(@@.) :: (Zip c, Zip b, Pointed c, Foldable b, Functor a, Num s)
      => Linear' b c s -> Linear' a b s -> Linear' a c s
(@@.) = inNew . fmap . linear'

-- (@@.) no = inNew (fmap (linear' no))
-- (@@.) no = inNew (linear' no <$>)
-- no @@. Comp1 mn = Comp1 (linear' no <$> mn)

exl' :: (Pointed a, Keyed a, Adjustable a, Pointed b, Num s)
     => Linear' (a :*: b) a s
-- exl' = inNew (idL :*:) zeroL'
exl' = inNew2 (:*:) idL' zeroL'

-- exlL = idL :*: zeroL

fork' :: Zip a => Linear' a b s -> Linear' a c s -> Linear' a (b :*: c) s
fork' = (inNew2 . zipWith) (:*:)

inl' :: (Pointed a, Keyed a, Adjustable a, Pointed b, Num s)
     => Linear' a (a :*: b) s
inl' = (inNew . fmap) (:*: zeroV) idL'

join' :: Linear' a c s -> Linear' b c s -> Linear' (a :*: b) c s
join' = inNew2 (:*:)

{--------------------------------------------------------------------
    Quantify over Num
--------------------------------------------------------------------}

type U a = forall s. Num s => a s

type Linear'' a b = U (a :.: b)

-- data Linear'' a b = forall s. L (Num s => (a :.: b) s)

type NT a b = forall s. Num s => a s -> b s

linear'' :: (Zip b, Zip a, Pointed b, Foldable a)
         => Linear'' a b -> NT a b
linear'' (Comp1 ns) a = sumV (zipWith (*^) a ns)

zeroL'' :: (Pointed b, Pointed a) => Linear'' a b
zeroL'' = Comp1 (point zeroV)

idL'' :: (Adjustable a, Keyed a, Pointed a)
      => Linear'' a a
idL'' = (inNew . mapWithKey) (flip replace 1) zeroL''

exl'' :: (Pointed a, Keyed a, Adjustable a, Pointed b)
      => Linear'' (a :*: b) a
exl'' = inNew (idL :*:) zeroL'

fork'' :: Zip a => Linear'' a b -> Linear'' a c -> Linear'' a (b :*: c)
fork'' = inNew2 (zipWith (:*:))
-- fork'' = (inNew2'' . zipWith) (:*:)

inl'' :: (Pointed a, Keyed a, Adjustable a, Pointed b)
      => Linear'' a (a :*: b)
inl'' = (inNew . fmap) (:*: zeroV) idL''

join'' :: Linear'' a c -> Linear'' b c -> Linear'' (a :*: b) c
join'' = inNew2 (:*:)

{--------------------------------------------------------------------
    Categorical instances
--------------------------------------------------------------------}

newtype LMapF s a b = LMapF ((a :-* b) s)

instance Newtype (LMapF s a b) where
  type O (LMapF s a b) = (a :-* b) s
  pack ab = LMapF ab
  unpack (LMapF ab) = ab

type OkLF a = (Foldable a, Pointed a, Zip a, Keyed a, Adjustable a)

class    (OkLF a, Num s) => OkLMapF s a
instance (OkLF a, Num s) => OkLMapF s a

instance Category (LMapF s) where
  type Ok (LMapF s) = OkLMapF s
  id = pack idL
  (.) = inNew2 (@.)

instance OpCon (:*:) (OkLMapF s) where inOp = Sub Dict

instance ProductCat (LMapF s) where
  type Prod (LMapF s) = (:*:)
  exl = pack exlL
  exr = pack exrL
  (&&&) = inNew2 forkL

instance CoproductCat (LMapF s) where
  type Coprod (LMapF s) = (:*:)
  inl = pack inlL
  inr = pack inrL
  (|||) = inNew2 joinL

-- We can't make a ClosedCat instance compatible with the ProductCat instance.
-- We'd have to change the latter to use the tensor product.

-- type instance Exp (LMapF s) = (:.:)

toExp :: LMapF s a b -> (a :.: b) s
toExp = pack . unpack
-- toExp (LMapF ab) = pack ab


#if 0
newtype LMapF' s a b = LMapF' ((a :.: b) s)
 deriving (Foldable, Pointed, Zip, Keyed, Adjustable)

-- • Cannot derive well-kinded instance of form ‘Foldable (LMapF' ...)’
--     Class ‘Foldable’ expects an argument of kind ‘* -> *’

instance Newtype (LMapF' s a b) where
  type O (LMapF' s a b) = (a :.: b) s
  pack ab = LMapF' ab
  unpack (LMapF' ab) = ab
#endif

{--------------------------------------------------------------------
    Conversion to linear map
--------------------------------------------------------------------}

#if 0

lapply :: (OkLF s a, OkLF s b) => LMapF s a b -> UT s a b
lapply = inNew lapplyL

class (OkLMapF s a, OkLMapF s b) => HasL s a b where
  -- | Law: @'linear' . 'lapply' == 'id'@ (but not the other way around)
  linear :: UT s a b -> LMapF s a b

instance OkLMapF s a => HasL s Par1 a where
  linear (UT f) = LMapF (Par1 (f (Par1 1)))

--              f           :: Par1 s -> b s
--              f (Par1 1)  :: b s
--        Par1 (f (Par1 1)) :: Par1 (b s)
-- LMapF (Par1 (f (Par1 1)) :: LMapF s Par1 b

instance (HasL s a c, HasL s b c) => HasL s (a :*: b) c where
  linear f = linear (f . lapply inl) ||| linear (f . lapply inr)

#else

lapply :: (Num s, OkLF a, OkLF b) => LMapF s a b -> UT s a b
lapply = inNew lapplyL

class OkLF a => HasL a where
  -- | Law: @'linear' . 'lapply' == 'id'@ (but not the other way around)
  linear :: forall s b. (Num s, OkLF b) => UT s a b -> LMapF s a b

instance HasL Par1 where
  linear (UT f) = LMapF (Par1 (f (Par1 1)))

--              f           :: Par1 s -> b s
--              f (Par1 1)  :: b s
--        Par1 (f (Par1 1)) :: Par1 (b s)
-- LMapF (Par1 (f (Par1 1)) :: LMapF s Par1 b

instance (HasL a, HasL b) => HasL (a :*: b) where
  linear f = linear (f . lapply inl) ||| linear (f . lapply inr)

#endif

{--------------------------------------------------------------------
    Functors
--------------------------------------------------------------------}

-- lapply as functor
data Lapply s

instance FunctorC (Lapply s) (LMapF s) (UT s) where
  -- type OkF (Lapply s) a b = (Num s, OkLF a, OkLF b)
  type Lapply s % a = a
  fmapC = lapply

-- linear as functor
data Linear s

instance FunctorC (Linear s) (Constrained HasL (UT s)) (LMapF s) where
  -- type OkF (Linear s) a b = (Num s, HasL a, OkLF b)
  type Linear s % a = a
  fmapC (Constrained f) = linear f
