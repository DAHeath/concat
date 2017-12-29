{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

{-# OPTIONS_GHC -Wall #-}

-- | Commutative monoid intended to be used with a multiplicative monoid

module ConCat.Additive where

import Prelude hiding (id,(.),curry,uncurry,zipWith)
import Data.Monoid
import Data.Foldable (fold)
import Data.Complex hiding (magnitude)
import Data.Ratio
import Foreign.C.Types (CSChar, CInt, CShort, CLong, CLLong, CIntMax, CFloat, CDouble)
import GHC.Generics (U1(..),Par1(..),(:*:)(..),(:.:)(..))
-- import Data.Constraint (Dict(..),(:-)(..))
import GHC.TypeLits (KnownNat)

import Data.Constraint (Dict(..),(:-)(..))
import Data.Key(Zip(..))
import Data.Pointed(Pointed(..))
import Data.Vector.Sized (Vector)

import Control.Newtype (Newtype(..))

import ConCat.Misc
import ConCat.Orphans ()
import ConCat.Pair
import ConCat.AltCat
import ConCat.Rep
-- The following imports allows the instances to type-check. Why?
import qualified ConCat.Category  as C

-- | Commutative monoid intended to be used with a multiplicative monoid
class Additive a where
  zero  :: a
  infixl 6 ^+^
  (^+^) :: a -> a -> a
  default zero :: (Pointed h, Additive b) => h b
  zero = point zero
  default (^+^) :: (Zip h, Additive b) => Binop (h b)
  (^+^) = zipWith (^+^)
  {-# INLINE (^+^) #-}

-- zipWith' :: Representable h
--          => (a -> b -> c) -> (h a -> h b -> h c)
-- zipWith' f as bs = fmap (uncurry f) (zip (as,bs))
-- {-# INLINER zipWith' #-}

instance Additive () where
  zero = ()
  () ^+^ () = ()

#define ScalarType(t) \
  instance Additive (t) where { zero = 0 ; (^+^) = (+) }

ScalarType(Int)
ScalarType(Integer)
ScalarType(Float)
ScalarType(Double)
ScalarType(CSChar)
ScalarType(CInt)
ScalarType(CShort)
ScalarType(CLong)
ScalarType(CLLong)
ScalarType(CIntMax)
ScalarType(CDouble)
ScalarType(CFloat)

instance Integral a => Additive (Ratio a) where
  zero  = 0
  (^+^) = (+)

instance (RealFloat v, Additive v) => Additive (Complex v) where
  zero  = zero :+ zero
  (^+^) = (+)

-- The 'RealFloat' constraint is unfortunate here. It's due to a
-- questionable decision to place 'RealFloat' into the definition of the
-- 'Complex' /type/, rather than in functions and instances as needed.

instance (Additive u,Additive v) => Additive (u,v) where
  zero             = (zero,zero)
  (u,v) ^+^ (u',v') = (u^+^u',v^+^v')

instance (Additive u,Additive v,Additive w)
    => Additive (u,v,w) where
  zero                   = (zero,zero,zero)
  (u,v,w) ^+^ (u',v',w') = (u^+^u',v^+^v',w^+^w')

instance (Additive u,Additive v,Additive w,Additive x)
    => Additive (u,v,w,x) where
  zero                        = (zero,zero,zero,zero)
  (u,v,w,x) ^+^ (u',v',w',x') = (u^+^u',v^+^v',w^+^w',x^+^x')

instance Additive v => Additive (a -> v)
instance Additive v => Additive (Sum     v)
instance Additive v => Additive (Product v)

type AddF f = (Pointed f, Zip f)

instance Additive v => Additive (U1 v)
instance Additive v => Additive (Par1 v)
instance (Additive v, AddF f, AddF g) => Additive ((f :*: g) v)
instance (Additive v, AddF f, AddF g) => Additive ((g :.: f) v)

-- instance Additive v => Additive (Pair v)

-- instance (Eq i, Additive v) => Additive (Arr i v) where
--   zero = point zero
--   as ^+^ bs = fmap (uncurry (^+^)) (zipC (as,bs))

-- TODO: Define and use zipWithC (^+^) as bs.

instance (Additive v, KnownNat n) => Additive (Vector n v)

class Additive1 h where additive1 :: Sat Additive a |- Sat Additive (h a)

instance Additive1 ((->) a) where additive1 = Entail (Sub Dict)

instance Additive1 Sum where additive1 = Entail (Sub Dict)
instance Additive1 Product where additive1 = Entail (Sub Dict)
instance Additive1 U1 where additive1 = Entail (Sub Dict)
instance Additive1 Par1 where additive1 = Entail (Sub Dict)
instance (AddF f, AddF g) => Additive1 (f :*: g) where additive1 = Entail (Sub Dict)
instance (AddF f, AddF g) => Additive1 (g :.: f) where additive1 = Entail (Sub Dict)

instance Additive1 Pair where additive1 = Entail (Sub Dict)

instance KnownNat n => Additive1 (Vector n) where
  additive1 = Entail (Sub Dict)

-- Maybe is handled like the Maybe-of-Sum monoid
instance Additive a => Additive (Maybe a) where
  zero                = Nothing
  Nothing ^+^ b'      = b'
  a' ^+^ Nothing      = a'
  Just a' ^+^ Just b' = Just (a' ^+^ b')

-- -- Memo tries
-- instance (HasTrie u, Additive v) => Additive (u :->: v) where
--   zero  = pure   zero
--   (^+^) = liftA2 (^+^)

instance OpCon (:*) (Sat Additive) where
  inOp = Entail (Sub Dict)
  {-# INLINE inOp #-}

instance OpCon (->) (Sat Additive) where
  inOp = Entail (Sub Dict)
  {-# INLINE inOp #-}

{--------------------------------------------------------------------
    Monoid wrapper
--------------------------------------------------------------------}

-- | Monoid under group addition.  Alternative to the @Sum@ in
-- "Data.Monoid", which uses 'Num' instead of 'Additive'.
newtype Add a = Add { getAdd :: a }
  deriving (Eq, Ord, Read, Show, Bounded)

instance Newtype (Add a) where
  type O (Add a) = a
  pack   = Add
  unpack = getAdd

instance Functor Add where fmap = inNew

instance Applicative Add where
  pure  = pack
  (<*>) = inNew2 ($)

instance Additive a => Monoid (Add a) where
  mempty  = pack zero
  mappend = inNew2 (^+^)

instance Additive a => Additive (Add a) where
  zero  = mempty
  (^+^) = mappend

add :: (Foldable f, Functor f, Additive a) => f a -> a
add = getAdd . fold . fmap Add

{--------------------------------------------------------------------
    Additive homomorphisms
--------------------------------------------------------------------}

-- | Additive homomorphisms
data AdditiveMap a b = AdditiveMap (a -> b)

instance HasRep (AdditiveMap a b) where
  type Rep (AdditiveMap a b) = a -> b
  abst f = AdditiveMap f
  repr (AdditiveMap f) = f

instance Category AdditiveMap where
  type Ok AdditiveMap = Additive
  id = abst id
  (.) = inAbst2 (.)

instance ProductCat AdditiveMap where
  exl    = abst exl
  exr    = abst exr
  (&&&)  = inAbst2 (&&&)
  (***)  = inAbst2 (***)
  dup    = abst dup
  swapP  = abst swapP
  first  = inAbst first
  second = inAbst second

instance CoproductCatD AdditiveMap where
  inlD   = abst (,zero)
  inrD   = abst (zero,)
  (||||) = inAbst2 (\ f g (x,y) -> f x ^+^ g y)
  (++++) = inAbst2 (***)
  jamD   = abst (uncurry (^+^))
  swapSD = abst swapP
  -- ...
