-- {-# LANGUAGE TypeInType #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE ViewPatterns #-}

{-# OPTIONS_GHC -Wall #-}

{-# OPTIONS_GHC -fno-warn-unused-imports #-}  -- TEMP
{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-} -- for Oks

-- | Another go at constrained categories. This time without Prod, Coprod, Exp.

-- #define DefaultCat

module ConCat.Category where

import Prelude hiding (id,(.),curry,uncurry,const)
import qualified Prelude as P
#ifdef DefaultCat
import qualified Control.Category as C
#endif
import Control.Arrow (Kleisli(..),arr)
import qualified Control.Arrow as A
import Control.Applicative (liftA2)
import Control.Monad ((<=<))
import Data.Proxy (Proxy)
import GHC.Types (Constraint)
import Data.Constraint hiding ((&&&),(***),(:=>))
-- import GHC.Types (type (*))  -- experiment with TypeInType
-- import qualified Data.Constraint as K

import Control.Newtype (Newtype(..))

import Data.MemoTrie

import ConCat.Misc hiding ((<~),(~>),type (&&),type (&+&))
import ConCat.Rep
import ConCat.Orphans ()

{--------------------------------------------------------------------
    Constraints
--------------------------------------------------------------------}

class HasCon a where
  type Con a :: Constraint
  toD :: a -> Dict (Con a)
  unD :: Con a => a

newtype Sat kon a = Sat (Dict (kon a))

instance HasCon (Sat kon a) where
  type Con (Sat kon a) = kon a
  toD (Sat d) = d
  unD = Sat Dict

instance (HasCon a, HasCon b) => HasCon (a :* b) where
  type Con (a :* b) = (Con a,Con b)
  toD (toD -> Dict, toD -> Dict) = Dict
  unD = (unD,unD)

infixr 1 |-
newtype a |- b = Entail (Con a :- Con b)

instance Newtype (a |- b) where
  type O (a |- b) = Con a :- Con b
  pack e = Entail e
  unpack (Entail e) = e

instance Category (|-) where
  -- type Ok (|-) = HasCon
  id = pack refl
  (.) = inNew2 (\ g f -> Sub $ Dict \\ g \\ f)

instance OpCon (:*) (Sat HasCon) where
  inOp = Entail (Sub Dict)

instance ProductCat (|-) where
  -- type Prod (|-) = (:*)
  exl = pack (Sub Dict)
  exr = pack (Sub Dict)
  dup = pack (Sub Dict)
  (&&&) = inNew2 $ \ f g -> Sub $ Dict \\ f \\ g
  (***) = inNew2 $ \ f g -> Sub $ Dict \\ f \\ g

infixl 1 <+

-- | Wrapper
(<+) :: Con a => (Con b => r) -> (a |- b) -> r
f <+ Entail e = f \\ e

infixr 3 &&
-- (&&) = Prod (|-)
type (&&) = (:*)

class OpCon op con where
  inOp :: con a && con b |- con (a `op` b)

-- class    OpCon op (Dict (kon a)) => OpCon' op kon a
-- instance OpCon op (Dict (kon a)) => OpCon' op kon a

-- class    kon a => Sat kon a
-- instance kon a => Sat kon a

type Yes1' = Sat Yes1

type Ok' k = Sat (Ok k)

type OpSat op kon = OpCon op (Sat kon)

inSat :: OpCon op (Sat con) => Sat con a && Sat con b |- Sat con (a `op` b)
inSat = inOp

inOpL :: OpCon op con => (con a && con b) && con c |- con ((a `op` b) `op` c)
inOpL = inOp . first  inOp

inOpR :: OpCon op con => con a && (con b && con c) |- con (a `op` (b `op` c))
inOpR = inOp . second inOp

inOpL' :: OpCon op con 
       => (con a && con b) && con c |- con (a `op` b) && con ((a `op` b) `op` c)
inOpL' = second inOp . rassocP . first (dup . inOp)

-- (con a && con b) && con c
-- con (a `op` b) && con c
-- (con (a `op` b) && con (a `op` b)) && con c
-- con (a `op` b) && (con (a `op` b) && con c)
-- con (a `op` b) && con ((a `op` b) `op` c)

inOpR' :: OpCon op con => con a && (con b && con c) |- con (a `op` (b `op` c)) &&  con (b `op` c)
inOpR' = first inOp . lassocP . second (dup . inOp)

inOpLR :: forall op con a b c. OpCon op con =>
  ((con a && con b) && con c) && (con a && (con b && con c))
  |- con ((a `op` b) `op` c) && con (a `op` (b `op` c))
inOpLR = inOpL *** inOpR

instance OpCon op Yes1' where
  inOp = Entail (Sub Dict)

#if 1
type C1 (con :: u -> Constraint) a = con a
type C2 con a b         = (C1 con a, con b)
type C3 con a b c       = (C2 con a b, con c)
type C4 con a b c d     = (C3 con a b c, con d)
type C5 con a b c d e   = (C4 con a b c d, con e)
type C6 con a b c d e f = (C5 con a b c d e, con f)

type Ok2 k a b         = C2 (Ok k) a b
type Ok3 k a b c       = C3 (Ok k) a b c
type Ok4 k a b c d     = C4 (Ok k) a b c d
type Ok5 k a b c d e   = C5 (Ok k) a b c d e
type Ok6 k a b c d e f = C6 (Ok k) a b c d e f
#endif

type Oks k as = AllC (Ok k) as

{--------------------------------------------------------------------
    Categories
--------------------------------------------------------------------}

class Category k where
  type Ok k :: * -> Constraint
  type Ok k = Yes1
  id  :: Ok k a => a `k` a
  infixr 9 .
  (.) :: forall b c a. Oks k [a,b,c] => (b `k` c) -> (a `k` b) -> (a `k` c)
#ifdef DefaultCat
  -- Defaults experiment
  default id :: C.Category k => a `k` a
  id = C.id
  default (.) :: C.Category k => b `k` c -> a `k` b -> a `k` c
  (.) = (C..)
#endif

infixl 1 <~
infixr 1 ~>
-- | Add post- and pre-processing
(<~) :: (Category k, Oks k [a,b,a',b']) 
     => (b `k` b') -> (a' `k` a) -> ((a `k` b) -> (a' `k` b'))
(h <~ f) g = h . g . f

-- | Add pre- and post-processing
(~>) :: (Category k, Oks k [a,b,a',b']) 
     => (a' `k` a) -> (b `k` b') -> ((a `k` b) -> (a' `k` b'))
f ~> h = h <~ f

instance Category (->) where
#ifndef DefaultCat
  id  = P.id
  (.) = (P..)
#endif

instance Monad m => Category (Kleisli m) where
#ifndef DefaultCat
  id  = pack return
  (.) = inNew2 (<=<)
#endif

{--------------------------------------------------------------------
    Products
--------------------------------------------------------------------}

type Prod k = (:*)

infixr 3 ***, &&&

okProd :: forall k a b. OpCon (Prod k) (Ok' k)
       => Ok' k a && Ok' k b |- Ok' k (Prod k a b)
okProd = inOp

-- | Category with product.
class (OpCon (Prod k) (Ok' k), Category k) => ProductCat k where
  -- type Prod k :: u -> u -> u
  -- type Prod k = (:*)
  exl :: Oks k [a,b] => Prod k a b `k` a
  exr :: Oks k [a,b] => Prod k a b `k` b
  dup :: Ok  k a => a `k` Prod k a a
  dup = id &&& id
  swapP :: forall a b. Oks k [a,b] => Prod k a b `k` Prod k b a
  swapP = exr &&& exl
          <+ okProd @k @a @b
  (***) :: forall a b c d. Oks k [a,b,c,d] 
        => (a `k` c) -> (b `k` d) -> (Prod k a b `k` Prod k c d)
  f *** g = f . exl &&& g . exr
            <+ okProd @k @a @b
  (&&&) :: forall a c d. Oks k [a,c,d] 
        => (a `k` c) -> (a `k` d) -> (a `k` Prod k c d)
#ifndef DefaultCat
  -- We can't give two default definitions for (&&&).
  f &&& g = (f *** g) . dup
    <+ okProd @k @a @a
    <+ okProd @k @c @d
#endif
  first :: forall a a' b. Oks k [a,b,a'] 
        => (a `k` a') -> (Prod k a b `k` Prod k a' b)
  first = (*** id)
  second :: forall a b b'. Oks k [a,b,b'] 
         => (b `k` b') -> (Prod k a b `k` Prod k a b')
  second = (id ***)
  lassocP :: forall a b c. Oks k [a,b,c]
          => Prod k a (Prod k b c) `k` Prod k (Prod k a b) c
  lassocP = second exl &&& (exr . exr)
            <+ okProd @k @a @b
            <+ inOpR' @(Prod k) @(Ok' k) @a @b @c
  rassocP :: forall a b c. Oks k [a,b,c]
          => Prod k (Prod k a b) c `k` Prod k a (Prod k b c)
  rassocP = (exl . exl) &&& first  exr
            <+ okProd @k    @b @c
            <+ inOpL' @(Prod k) @(Ok' k) @a @b @c
#ifdef DefaultCat
  -- These defaults are not kicking in for (->). Why not?
  -- default exl :: A.Arrow k => Prod k a b `k` a
  default exl :: (A.Arrow k, Ok k ~ Yes1, Oks k [a,b]) => (a :* b) `k` a
  exl = arr exl
  default exr :: A.Arrow k => Prod k a b `k` b
  exr = arr exr
  default (&&&) :: A.Arrow k => a `k` c -> a `k` d -> a `k` (c :* d)
  (&&&) = (A.&&&)
#endif
  {-# MINIMAL exl, exr, ((&&&) | ((***), dup)) #-}

instance ProductCat (->) where
#ifndef DefaultCat
  -- type Prod (->) = (:*)
  exl     = fst
  exr     = snd
  (&&&)   = (A.&&&)
  (***)   = (A.***)
  first   = A.first
  second  = A.second
  lassocP = \ (a,(b,c)) -> ((a,b),c)
  rassocP = \ ((a,b),c) -> (a,(b,c))
#endif

-- | Apply to both parts of a product
twiceP :: (ProductCat k, Oks k [a,c]) 
       => (a `k` c) -> Prod k a a `k` (Prod k c c)
twiceP f = f *** f

-- | Operate on left-associated form
inLassocP :: forall k a b c a' b' c'.
             -- (ProductCat k, Ok6 k a b c a' b' c') 
             -- Needs :set -fconstraint-solver-iterations=5 or greater:
             (ProductCat k, Oks k [a,b,c,a',b',c'])
          => Prod k (Prod k a b) c `k` Prod k (Prod k a' b') c'
          -> Prod k a (Prod k b c) `k` (Prod k a' (Prod k b' c'))
inLassocP = rassocP <~ lassocP
              <+ (inOpLR @(Prod k) @(Ok' k) @a  @b  @c ***
                  inOpLR @(Prod k) @(Ok' k) @a' @b' @c')

-- | Operate on right-associated form
inRassocP :: forall a b c a' b' c' k.
--              (ProductCat k, Ok6 k a b c a' b' c') 
             (ProductCat k, Oks k [a,b,c,a',b',c'])
          => Prod k a (Prod k b c) `k` (Prod k a' (Prod k b' c'))
          -> Prod k (Prod k a b) c `k` Prod k (Prod k a' b') c'
inRassocP = lassocP <~ rassocP
              <+ (inOpLR @(Prod k) @(Ok' k) @a  @b  @c ***
                  inOpLR @(Prod k) @(Ok' k) @a' @b' @c')

transposeP :: forall k a b c d. (ProductCat k, Oks k [a,b,c,d])
           => Prod k (Prod k a b) (Prod k c d) `k` Prod k (Prod k a c) (Prod k b d)
transposeP = (exl.exl &&& exl.exr) &&& (exr.exl &&& exr.exr)
  <+ okProd @k @(Prod k a b) @(Prod k c d)
  <+ okProd @k @c @d
  <+ okProd @k @a @b
  <+ okProd @k @b @d
  <+ okProd @k @a @c

-- | Inverse to '(&&&)'
unfork :: forall k a c d. (ProductCat k, Oks k [a,c,d]) 
       => (a `k` Prod k c d) -> (a `k` c, a `k` d)
unfork f = (exl . f, exr . f)  <+ okProd @k @c @d

instance Monad m => ProductCat (Kleisli m) where
  -- type Prod (Kleisli m) = (:*)
  exl   = arr exl
  exr   = arr exr
  dup   = arr dup
  (&&&) = inNew2 forkK
  (***) = inNew2 crossK

-- Underlies '(&&&)' on Kleisli arrows
forkK :: Applicative m => (a -> m c) -> (a -> m d) -> (a -> m (c :* d))
(f `forkK` g) a = liftA2 (,) (f a) (g a)

-- Underlies '(***)' on Kleisli arrows
crossK :: Applicative m => (a -> m c) -> (b -> m d) -> (a :* b -> m (c :* d))
(f `crossK` g) (a,b) = liftA2 (,) (f a) (g b)

{--------------------------------------------------------------------
    Coproducts
--------------------------------------------------------------------}

type Coprod k = (:+)

okCoprod :: forall k a b. OpCon (Coprod k) (Ok' k)
         => Ok' k a && Ok' k b |- Ok' k (Coprod k a b)
okCoprod = inOp

infixr 2 +++, |||

-- | Category with coproduct.
class (OpCon (Coprod k) (Ok' k), Category k) => CoproductCat k where
  -- type Coprod k :: u -> u -> u
  -- type Coprod k = (:+)
  inl :: Oks k [a,b] => a `k` Coprod k a b
  inr :: Oks k [a,b] => b `k` Coprod k a b
  jam :: Oks k '[a] => Coprod k a a `k` a
  jam = id ||| id
  swapS :: forall a b. Oks k [a,b] => Coprod k a b `k` Coprod k b a
  swapS = inr ||| inl
          <+ okCoprod @k @b @a
  (+++) :: forall a b c d. Oks k [a,b,c,d] 
        => (c `k` a) -> (d `k` b) -> (Coprod k c d `k` Coprod k a b)
  f +++ g = inl . f ||| inr . g
            <+ okCoprod @k @a @b
  (|||) :: forall a c d. Oks k [a,c,d] 
        => (c `k` a) -> (d `k` a) -> (Coprod k c d `k` a)
#ifndef DefaultCat
  -- We can't give two default definitions for (&&&).
  f ||| g = jam . (f +++ g)
          <+ okCoprod @k @a @a
          <+ okCoprod @k @c @d
#endif
  left  :: forall a a' b. Oks k [a,b,a'] 
        => (a `k` a') -> (Coprod k a b `k` Coprod k a' b)
  left  = (+++ id)
  right :: forall a b b'. Oks k [a,b,b'] 
        => (b `k` b') -> (Coprod k a b `k` Coprod k a b')
  right = (id +++)
  lassocS :: forall a b c. Oks k [a,b,c]
          => Coprod k a (Coprod k b c) `k` Coprod k (Coprod k a b) c
  lassocS = inl.inl ||| (inl.inr ||| inr)
            <+ inOpL' @(Coprod k) @(Ok' k) @a @b @c
            <+ okCoprod @k    @b @c
  rassocS :: forall a b c. Oks k [a,b,c]
          => Coprod k (Coprod k a b) c `k` Coprod k a (Coprod k b c)
  rassocS = (inl ||| inr.inl) ||| inr.inr
            <+ inOpR' @(Coprod k) @(Ok' k) @a @b @c
            <+ okCoprod @k @a @b
#ifdef DefaultCat
  default inl :: A.ArrowChoice k => a `k` Coprod k a b
  inl = arr inl
  default inr :: A.ArrowChoice k => b `k` Coprod k a b
  inr = arr inr
  default (|||) :: A.ArrowChoice k => (a `k` c) -> (b `k` c) -> (Coprod k a b `k` c)
  (|||) = (A.|||)
#endif
  {-# MINIMAL inl, inr, ((|||) | ((+++), jam)) #-}

-- type CoprodOk' k ok = (CoproductCat k, ok ~ Ok' k)

instance CoproductCat (->) where
#ifndef DefaultCat
  -- type Coprod (->) = (:+)
  inl   = Left
  inr   = Right
  (|||) = (A.|||)
  (+++) = (A.+++)
  left  = A.left
  right = A.right
#endif

-- | Operate on left-associated form
inLassocS :: forall k a b c a' b' c'.
             -- (CoproductCat k, Ok6 k a b c a' b' c') 
             (CoproductCat k, Oks k [a,b,c,a',b',c'])
          => Coprod k (Coprod k a b) c `k` Coprod k (Coprod k a' b') c'
          -> Coprod k a (Coprod k b c) `k` (Coprod k a' (Coprod k b' c'))
inLassocS = rassocS <~ lassocS
            <+ (inOpLR @(Coprod k) @(Ok' k) @a  @b  @c ***
                inOpLR @(Coprod k) @(Ok' k) @a' @b' @c')

-- | Operate on right-associated form
inRassocS :: forall a b c a' b' c' k.
             -- (CoproductCat k, Ok6 k a b c a' b' c') 
             (CoproductCat k, Oks k [a,b,c,a',b',c'])
          => Coprod k a (Coprod k b c) `k` (Coprod k a' (Coprod k b' c'))
          -> Coprod k (Coprod k a b) c `k` Coprod k (Coprod k a' b') c'
inRassocS = lassocS <~ rassocS
            <+ (inOpLR @(Coprod k) @(Ok' k) @a  @b  @c ***
                inOpLR @(Coprod k) @(Ok' k) @a' @b' @c')

transposeS :: forall k a b c d. (CoproductCat k, Oks k [a,b,c,d])
           => Coprod k (Coprod k a b) (Coprod k c d) `k` Coprod k (Coprod k a c) (Coprod k b d)
transposeS = (inl.inl ||| inr.inl) ||| (inl.inr ||| inr.inr)
  <+ okCoprod @k @(Coprod k a c) @(Coprod k b d)
  <+ okCoprod @k @c @d
  <+ okCoprod @k @a @b
  <+ okCoprod @k @b @d
  <+ okCoprod @k @a @c

-- | Inverse to '(|||)'
unjoin :: forall k a c d. (CoproductCat k, Oks k [a,c,d]) 
       => (Coprod k c d `k` a) -> (c `k` a, d `k` a)
unjoin f = (f . inl, f . inr)  <+ okCoprod @k @c @d

{--------------------------------------------------------------------
    Distributive
--------------------------------------------------------------------}

class (ProductCat k, CoproductCat k) => DistribCat k where
  distl :: forall a u v. Oks k [a,u,v]
        => Prod k a (Coprod k u v) `k` Coprod k (Prod k a u) (Prod k a v)
  distr :: forall u v b. Oks k [u,v,b]
        => Prod k (Coprod k u v) b `k` Coprod k (Prod k u b) (Prod k v b)
  distl = (swapP +++ swapP) . distr . swapP
    <+ okProd   @k @(Coprod k u v) @a
    <+ okCoprod @k @(Prod k u a) @(Prod k v a)
    <+ okProd   @k @u @a
    <+ okProd   @k @v @a
    <+ okCoprod @k @(Prod k a u) @(Prod k a v)
    <+ okProd   @k @a @u
    <+ okProd   @k @a @v
    <+ okProd   @k @a @(Coprod k u v)
    <+ okCoprod @k @u @v
  distr = (swapP +++ swapP) . distl . swapP
    <+ okProd   @k @b @(Coprod k u v)
    <+ okCoprod @k @(Prod k b u) @(Prod k b v)
    <+ okProd   @k @b @u
    <+ okProd   @k @b @v
    <+ okCoprod @k @(Prod k u b) @(Prod k v b)
    <+ okProd   @k @u @b
    <+ okProd   @k @v @b
    <+ okProd   @k @(Coprod k u v) @b
    <+ okCoprod @k @u @v
  {-# MINIMAL distl | distr #-}

-- | Inverse to 'distl': @(a * u) + (a * v) --> a * (u + v)@
undistl :: forall k a u v. (ProductCat k, CoproductCat k, Oks k [a,u,v])
        => Coprod k (Prod k a u) (Prod k a v) `k` Prod k a (Coprod k u v)
undistl = (exl ||| exl) &&& (exr +++ exr)
  <+ okCoprod @k @(Prod k a u) @(Prod k a v)
  <+ okProd   @k @a @u
  <+ okProd   @k @a @v
  <+ okCoprod @k @u @v

-- | Inverse to 'distr': @(u * b) + (v * b) --> (u + v) * b@
undistr :: forall k u v b. (ProductCat k, CoproductCat k, Oks k [u,v,b])
        => Coprod k (Prod k u b) (Prod k v b) `k` Prod k (Coprod k u v) b
undistr = (exl +++ exl) &&& (exr ||| exr)
  <+ okCoprod @k @(Prod k u b) @(Prod k v b)
  <+ okCoprod @k @u @v
  <+ okProd   @k @u @b
  <+ okProd   @k @v @b

{--------------------------------------------------------------------
    Exponentials
--------------------------------------------------------------------}

okExp :: forall k a b. OpCon (Exp k) (Ok' k)
      => Ok' k a && Ok' k b |- Ok' k (Exp k a b)
okExp = inOp

type Exp k = (->)

class (OpCon (Exp k) (Ok' k), ProductCat k) => ClosedCat k where
  -- type Exp k :: u -> u -> u
  apply   :: forall a b. Oks k [a,b] => Prod k (Exp k a b) a `k` b
  apply = uncurry id
          <+ okExp @k @a @b
  curry   :: Oks k [a,b,c] => (Prod k a b `k` c) -> (a `k` Exp k b c)
  uncurry :: forall a b c. Oks k [a,b,c]
          => (a `k` Exp k b c)  -> (Prod k a b `k` c)
  uncurry g = apply . first g
              <+ okProd @k @(Exp k b c) @b
              <+ okProd @k @a @b
              <+ okExp @k @b @c
  {-# MINIMAL curry, (apply | uncurry) #-}

--   apply   :: (Oks k [a,b], p ~ Prod k, e ~ Exp k) => ((a `e` b) `p` a) `k` b

instance ClosedCat (->) where
  -- type Exp (->) = (->)
  apply   = P.uncurry ($)
  curry   = P.curry
  uncurry = P.uncurry

#if 0
#if 1
applyK   ::            Kleisli m (Kleisli m a b :* a) b
curryK   :: Monad m => Kleisli m (a :* b) c -> Kleisli m a (Kleisli m b c)
uncurryK :: Monad m => Kleisli m a (Kleisli m b c) -> Kleisli m (a :* b) c

applyK   = pack (apply . first unpack)
curryK   = inNew $ \ h -> return . pack . curry h
uncurryK = inNew $ \ f -> \ (a,b) -> f a >>= ($ b) . unpack

instance Monad m => ClosedCat (Kleisli m) where
  -- type Exp (Kleisli m) = Kleisli m
  apply   = applyK
  curry   = curryK
  uncurry = uncurryK
#else
instance Monad m => ClosedCat (Kleisli m) where
  type Exp (Kleisli m) = Kleisli m
  apply   = pack (apply . first unpack)
  curry   = inNew $ \ h -> return . pack . curry h
  uncurry = inNew $ \ f -> \ (a,b) -> f a >>= ($ b) . unpack
#endif
#endif

type Unit k = ()

class (Category k, Ok k (Unit k)) => TerminalCat k where
  -- type Unit k :: u
  it :: Ok k a => a `k` Unit k

instance TerminalCat (->) where
  -- type Unit (->) = ()
  it = const ()

instance Monad m => TerminalCat (Kleisli m) where
  -- type Unit (Kleisli m) = ()
  it = arr it

-- -- | Categories with constant arrows (generalized elements)
-- class ConstCat k where
--   konst :: forall a b. Oks k [a,b] => b -> (a `k` b)

-- instance ConstCat (->) where konst = const

-- instance Monad m => ConstCat (Kleisli m) where konst b = arr (const b)

-- class ApplyToCat k where
--   applyTo :: Oks k [a,b] => a -> ((a -> b) `k` b)

-- Do I want `Exp k a b` in place of `a -> b`?
-- LMap seems to want ->.

-- class ClosedCat k => ApplyToCat k where
--   applyTo :: Oks k [a,b] => a -> (Exp k a b `k` b)

#if 0

class Category k => UnsafeArr k where
  unsafeArr :: Oks k [a,b] => (a -> b) -> a `k` b

instance UnsafeArr (->) where
  unsafeArr = A.arr

instance Monad m => UnsafeArr (Kleisli m) where
  unsafeArr = A.arr
  
#endif

constFun :: forall k p a b. (ClosedCat k, Oks k [p,a,b])
         => (a `k` b) -> (p `k` Exp k a b)
constFun f = curry (f . exr)
             <+ okProd @k @p @a

--        f        :: a `k` b
--        f . exl  :: Prod k p a `k` b
-- curry (f . exl) :: p `k` (Exp k a b)

-- Combine with currying:

constFun2 :: forall k p a b c. (ClosedCat k, Oks k [p,a,b,c])
          => (Prod k a b `k` c) -> (p `k` (Exp k a (Exp k b c)))
constFun2 = constFun . curry
            <+ okExp @k @b @c

unitFun :: forall k a b. (ClosedCat k, TerminalCat k, Oks k [a,b])
        => (a `k` b) -> (Unit k `k` (Exp k a b))
unitFun = constFun

unUnitFun :: forall k p a. (ClosedCat k, TerminalCat k, Oks k [p,a]) =>
             (Unit k `k` Exp k p a) -> (p `k` a)
unUnitFun g = uncurry g . (it &&& id)
              <+ okProd @k @(Unit k) @p

{--------------------------------------------------------------------
    Constant arrows
--------------------------------------------------------------------}

#if 0
  
class TerminalCat k => ConstCat k where
  const :: Oks k [a,b] => b -> (a `k` b)
  const b = unitArrow b . it
  unitArrow  :: Ok k b => b -> Unit k `k` b
  unitArrow = const
  {-# MINIMAL const | unitArrow #-}

#elif 0

-- Alternatively, make `b` a parameter to `ConstCat`:

class (TerminalCat k, Ok k b) => ConstCat k b where
  unitArrow  :: b -> Unit k `k` b
  const :: Ok k a => b -> (a `k` b)
  const b = unitArrow b . it
  unitArrow = const
  {-# MINIMAL unitArrow | const #-}

#elif 0

-- Associated type for the codomain

class (TerminalCat k, Ok k (ConstObj k b)) => ConstCat k b where
  type ConstObj k b
  type ConstObj k b = b
  unitArrow  :: b -> (Unit k `k` ConstObj k b)
  const :: Ok k a => b -> (a `k` ConstObj k b)
  const b = unitArrow b . it
  unitArrow = const
  {-# MINIMAL unitArrow | const #-}

#else

-- Drop ConstObj for now

type ConstObj k b = b

class (TerminalCat k, Ok k (ConstObj k b)) => ConstCat k b where
--   type ConstObj k b
--   type ConstObj k b = b
  unitArrow  :: b -> (Unit k `k` ConstObj k b)
  const :: Ok k a => b -> (a `k` ConstObj k b)
  const b = unitArrow b . it
  unitArrow = const
  {-# MINIMAL unitArrow | const #-}

#endif

instance ConstCat (->) b where const = const

instance Monad m => ConstCat (Kleisli m) b where const b = arr (const b)

-- For prims, use constFun instead.

-- Note that `ConstCat` is *not* poly-kinded. Since the codomain `b` is an
-- argument to `unitArrow` and `const`, `k :: * -> * -> *`. I'm uneasy
-- about this kind restriction, which would preclude some useful categories,
-- including linear maps and entailment. Revisit this issue later.

{--------------------------------------------------------------------
    Class aggregates
--------------------------------------------------------------------}

-- | Bi-cartesion (cartesian & co-cartesian) closed categories. Also lumps in
-- terminal and distributive, though should probably be moved out.
type BiCCC k = (ClosedCat k, CoproductCat k, TerminalCat k, DistribCat k)

-- -- | 'BiCCC' with constant arrows.
-- type BiCCCC k p = (BiCCC k, ConstCat k p {-, RepCat k, LoopCat k, DelayCat k-})


{--------------------------------------------------------------------
    Add constraints to a category
--------------------------------------------------------------------}

infixr 3 &+&

-- data (f &+& g) a = And1 (f a) (g a)

class    (con a, con' a) => (con &+& con') a
instance (con a, con' a) => (con &+& con') a

-- instance (HasCon (f a), HasCon (g a)) => HasCon ((f &+& g) a) where
--   type Con ((f &+& g) a) = (Con (f a),Con (g a))
--   toD (And1 (toD -> Dict) (toD -> Dict)) = Dict
--   unD = And1 unD unD

-- class    (f a, g a) => (f &+& g) a
-- instance (f a, g a) => (f &+& g) a

data Constrained (con :: * -> Constraint) k a b = Constrained (a `k` b)

instance (OpSat op con, OpSat op con') => OpCon op (Sat (con &+& con')) where
  inOp :: forall a b. Sat (con &+& con') a && Sat (con &+& con') b |- Sat (con &+& con') (a `op` b)
  inOp = Entail (Sub $ Dict <+ inSat @op @con @a @b <+ inSat @op @con' @a @b)

-- TODO: define inSat, combining inOp and Sat

instance Category k => Category (Constrained con k) where
  type Ok (Constrained con k) = Ok k &+& con
  id = Constrained id
  Constrained g . Constrained f = Constrained (g . f)

instance (ProductCat k, OpSat (Prod k) con) => ProductCat (Constrained con k) where
  -- type Prod (Constrained con k) = Prod k
  exl = Constrained exl
  exr = Constrained exr
  Constrained f &&& Constrained g = Constrained (f &&& g)

instance (CoproductCat k, OpSat (Coprod k) con) => CoproductCat (Constrained con k) where
  -- type Coprod (Constrained con k) = Coprod k
  inl = Constrained inl
  inr = Constrained inr
  Constrained a ||| Constrained b = Constrained (a ||| b)

instance (ClosedCat k, OpSat (Prod k) con, OpSat (Exp k) con) => ClosedCat (Constrained con k) where
  -- type Exp (Constrained con k) = Exp k
  apply = Constrained apply
  curry   (Constrained f) = Constrained (curry f)
  uncurry (Constrained g) = Constrained (uncurry g)

{--------------------------------------------------------------------
    Other category subclasses, perhaps to move elsewhere
--------------------------------------------------------------------}

-- I don't think I want the general Kleisli instances for the rest.
-- For instance, for circuits, type BoolOf (:>) = Source Bool.

-- #define KleisliInstances

-- Adapted from Circat.Classes

type BoolOf k = Bool

class (ProductCat k, Ok k (BoolOf k)) => BoolCat k where
  -- type BoolOf k
  notC :: BoolOf k `k` BoolOf k
  andC, orC, xorC :: Prod k (BoolOf k) (BoolOf k) `k` BoolOf k

--     • Potential superclass cycle for ‘BoolCat’
--         one of whose superclass constraints is headed by a type family:
--           ‘Ok k bool’
--       Use UndecidableSuperClasses to accept this
--     • In the class declaration for ‘BoolCat’

instance BoolCat (->) where
  -- type BoolOf (->) = Bool
  notC = not
  andC = P.uncurry (&&)
  orC  = P.uncurry (||)
  xorC = P.uncurry (/=)

#ifdef KleisliInstances
instance Monad m => BoolCat (Kleisli m) where
  -- type BoolOf (Kleisli m) = Bool
  notC = arr notC
  andC = arr andC
  orC  = arr orC
  xorC = arr xorC
#endif

class Num a => NumCat k a where
  negateC :: a `k` a
  addC, subC, mulC :: Prod k a a `k` a
  powIC :: Prod k a Int `k` a

instance Num a => NumCat (->) a where
  negateC = negate
  addC    = uncurry (+)
  subC    = uncurry (-)
  mulC    = uncurry (*)
  powIC   = uncurry (^)

#ifdef Kleisli
instance (Monad m, Num a) => NumCat (Kleisli m) a where
  negateC = arr negateC
  addC    = arr addC
  subC    = arr subC
  mulC    = arr mulC
  powIC   = arr powIC
#endif

class Fractional a => FractionalCat k a where
  recipC :: a `k` a
  divideC :: Prod k a a `k` a

instance Fractional a => FractionalCat (->) a where
  recipC = recip
  divideC = uncurry (/)

#ifdef Kleisli
instance (Monad m, Fractional a) => FractionalCat (Kleisli m) a where
  recipC  = arr recipC
  divideC = arr divideC
#endif

-- HACK: generalize/replace/...
class Floating a => FloatingCat k a where
  expC, cosC, sinC :: a `k` a

instance Floating a => FloatingCat (->) a where
  expC = exp
  cosC = cos
  sinC = sin

#ifdef Kleisli
instance (Monad m, Floating a) => FloatingCat (Kleisli m) a where
  expC = arr expC
  cosC = arr cosC
  sinC = arr sinC
#endif

-- Stand-in for fromIntegral, avoiding the intermediate Integer in the Prelude
-- definition.
class (Integral a, Num b) => FromIntegralCat k a b where
  fromIntegralC :: a `k` b

instance (Integral a, Num b) => FromIntegralCat (->) a b where
  fromIntegralC = fromIntegral

#ifdef Kleisli
instance (Monad m, Integral a, Num b) => FromIntegralCat (Kleisli m) a b where
  fromIntegralC = arr fromIntegral
#endif

okTT :: forall k a. OpCon (Prod k) (Ok' k) => Ok' k a |- Ok' k (Prod k a a)
okTT = okProd @k @a @a . dup

class (BoolCat k, Ok k a, Eq a) => EqCat k a where
  equal, notEqual :: Prod k a a `k` BoolOf k
  notEqual = notC . equal    <+ okTT @k @a
  equal    = notC . notEqual <+ okTT @k @a
  {-# MINIMAL equal | notEqual #-}

instance Eq a => EqCat (->) a where
  equal    = uncurry (==)
  notEqual = uncurry (/=)

#ifdef Kleisli
instance (Monad m, Eq a) => EqCat (Kleisli m) a where
  equal    = arr equal
  notEqual = arr notEqual
#endif

class (EqCat k a, Ord a) => OrdCat k a where
  lessThan, greaterThan, lessThanOrEqual, greaterThanOrEqual :: Prod k a a `k` BoolOf k
  greaterThan        = lessThan . swapP    <+ okTT @k @a
  lessThan           = greaterThan . swapP <+ okTT @k @a
  lessThanOrEqual    = notC . greaterThan  <+ okTT @k @a
  greaterThanOrEqual = notC . lessThan     <+ okTT @k @a
  {-# MINIMAL lessThan | greaterThan #-}

instance Ord a => OrdCat (->) a where
  lessThan           = uncurry (<)
  greaterThan        = uncurry (>)
  lessThanOrEqual    = uncurry (<=)
  greaterThanOrEqual = uncurry (>=)

#ifdef Kleisli
instance (Monad m, Ord a) => OrdCat (Kleisli m) a where
  lessThan           = arr lessThan
  greaterThan        = arr greaterThan
  lessThanOrEqual    = arr lessThanOrEqual
  greaterThanOrEqual = arr greaterThanOrEqual
#endif

class Ok k a => BottomCat k a where
  bottomC :: Unit k `k` a

instance BottomCat (->) a where bottomC = error "bottomC for (->) evaluated"

type IfT k a = Prod k (BoolOf k) (Prod k a a) `k` a

class (BoolCat k, Ok k a) => IfCat k a where
  ifC :: IfT k a

instance IfCat (->) a where
  ifC (i,(t,e)) = if i then t else e

#ifdef Kleisli
instance Monad m => IfCat (Kleisli m) a where
  ifC = arr ifC
#endif

unitIf :: forall k. (TerminalCat k, BoolCat k) => IfT k (Unit k)
unitIf = it <+ (inOpR @(Prod k) @(Ok' k) @(BoolOf k) @(Unit k) @(Unit k))

okIf :: forall k a. BoolCat k => Ok' k a |- Ok' k (Prod k (BoolOf k) (Prod k a a)) && Ok' k (Prod k a a)
okIf = inOpR' @(Prod k) @(Ok' k) @(BoolOf k) @a @a . Entail (Sub Dict)

prodIf :: forall k a b. (IfCat k a, IfCat k b) => IfT k (Prod k a b)
prodIf = (ifC . second (twiceP exl)) &&& (ifC . second (twiceP exr))
           <+ okIf @k @(Prod k a b)
           <+ okProd @k @a @b
           <+ okIf @k @a
           <+ okIf @k @b

#if 0

   prodIf
== \ (c,((a,b),(a',b'))) -> (ifC (c,(a,a')), ifC (c,(b,b')))
== (\ (c,((a,b),(a',b'))) -> ifC (c,(a,a'))) &&& ...
== (ifC . (\ (c,((a,b),(a',b'))) -> (c,(a,a')))) &&& ...
== (ifC . second (\ ((a,b),(a',b')) -> (a,a'))) &&& ...
== (ifC . second (twiceP exl)) &&& (ifC . second (twiceP exr))

#endif

-- funIf :: forall k a b. (ClosedCat k, IfCat k b) => IfT k (Exp k a b)
-- funIf = curry (ifC . (exl . exl &&& (half exl &&& half exr)))
--  where
--    half :: (u `k` Exp k a b) -> (Prod k (Prod k _bool u) a `k` b)
--    half h = apply . first (h . exr)

funIf :: forall k a b. (ClosedCat k, Ok k a, IfCat k b) => IfT k (Exp k a b)
funIf = curry (ifC . (exl . exl &&& (apply . first (exl . exr) &&& apply . first (exr . exr))))
           <+ okProd @k @(Prod k (BoolOf k) (Prod k (Exp k a b) (Exp k a b))) @a
           <+ okIf @k @(Exp k a b)
           <+ okProd @k @(Exp k a b) @a
           <+ okExp @k @a @b
           <+ okIf @k @b

#if 0

   funIf
== \ (c,(f,f')) -> \ a -> ifC (c,(f a,f' a))
== curry (\ ((c,(f,f')),a) -> ifC (c,(f a,f' a)))
== curry (ifC . \ ((c,(f,f')),a) -> (c,(f a,f' a)))
== curry (ifC . (exl.exl &&& \ ((c,(f,f')),a) -> (f a,f' a)))
== curry (ifC . (exl.exl &&& ((\ ((c,(f,f')),a) -> f a) &&& (\ ((c,(f,f')),a) -> f' a))))
== curry (ifC . (exl.exl &&& (apply (first (exl.exr)) &&& (apply (first (exl.exr))))))

#endif

repIf :: forall k a. (RepCat k, ProductCat k, Ok k a, HasRep a, IfCat k (Rep a))
      => IfT k a
repIf = abstC . ifC . second (twiceP reprC)
        <+ okProd @k @(BoolOf k) @(Prod k (Rep a) (Rep a))
        <+ okProd @k @(Rep a) @(Rep a)
        <+ okProd @k @(BoolOf k) @(Prod k a a)
        <+ okProd @k @a @a

#if 0
   repIf
== \ (c,(a,a')) -> abstC (ifC (c,(reprC a,reprC a')))
== \ (c,(a,a')) -> abstC (ifC (c,(twiceP reprC (a,a'))))
== \ (c,(a,a')) -> abstC (ifC (second (twiceP reprC) (c,((a,a')))))
== abstC . ifC . second (twiceP reprC)
#endif

class UnknownCat k a b where
  unknownC :: a `k` b

instance UnknownCat (->) a b where
  unknownC = error "unknown"


class RepCat k where
  reprC :: HasRep a => a `k` Rep a
  abstC :: HasRep a => Rep a `k` a

instance RepCat (->) where
  reprC = repr
  abstC = abst
