{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE LambdaCase #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP

-- | Experiment with injective associated type synonyms.

module ConCat.D where

import Prelude hiding (id,(.),zipWith,curry,uncurry)
import qualified Prelude as P
import Data.Kind
import GHC.Generics (U1(..),(:*:)(..),(:+:)(..),(:.:)(..))
import Control.Applicative (liftA2)
import Control.Monad ((<=<))
import Control.Arrow (arr,Kleisli(..))
import qualified Control.Arrow as A
import Control.Monad.State (State,modify,put,get,execState,StateT,evalStateT)

import Data.Constraint (Dict(..),(:-)(..),refl,trans,(\\))
import Control.Newtype
import Data.Pointed
import Data.Key

import ConCat.Misc (Yes1,inNew,inNew2,oops,type (+->)(..))
import ConCat.Free.VectorSpace
import ConCat.Free.LinearRow (lapplyL,OkLF,idL,(@.),exlL,exrL,forkL,inlL,inrL,joinL,HasL(..))
import ConCat.Rep
import ConCat.Orphans

{--------------------------------------------------------------------
    Constraints
--------------------------------------------------------------------}

type C1 (con :: u -> Constraint) a = con a
type C2 (con :: u -> Constraint) a b = (con a, con b)
type C3 (con :: u -> Constraint) a b c = (con a, con b, con c)
type C4 (con :: u -> Constraint) a b c d = (con a, con b, con c, con d)
type C5 (con :: u -> Constraint) a b c d e = (con a, con b, con c, con d, con e)
type C6 (con :: u -> Constraint) a b c d e f = (con a, con b, con c, con d, con e, con f)

type Ok2 k a b         = C2 (Ok k) a b
type Ok3 k a b c       = C3 (Ok k) a b c
type Ok4 k a b c d     = C4 (Ok k) a b c d
type Ok5 k a b c d e   = C5 (Ok k) a b c d e
type Ok6 k a b c d e f = C6 (Ok k) a b c d e f

-- Phasing out
infixr 1 |-
type (|-) = (:-)

infixl 1 <+
(<+) :: (b => r) -> (a :- b) -> (a => r)
r <+ Sub Dict = r
{-# INLINE (<+) #-}
-- (<+) = (\\)

{--------------------------------------------------------------------
    Categories
--------------------------------------------------------------------}

infixr 9 .
class Category k where
  type Ok k :: u -> Constraint
  type Ok k = Yes1
  id  :: Ok k a => a `k` a
  (.) :: forall b c a. Ok3 k a b c => (b `k` c) -> (a `k` b) -> (a `k` c)

infixl 1 <~
infixr 1 ~>
-- | Add post- and pre-processing
(<~) :: (Category k, Ok4 k a b a' b') 
     => (b `k` b') -> (a' `k` a) -> ((a `k` b) -> (a' `k` b'))
(h <~ f) g = h . g . f

-- | Add pre- and post-processing
(~>) :: (Category k, Ok4 k a b a' b') 
     => (a' `k` a) -> (b `k` b') -> ((a `k` b) -> (a' `k` b'))
f ~> h = h <~ f

class OkProd k where
  okProd :: (Ok k a, Ok k b) :- Ok k (Prod k a b)

infixr 3 &&&, ***
class (OkProd k, Category k) => Cartesian k where
  type Prod k (a :: u) (b :: u) = (ab :: u) | ab -> a b
  exl :: Ok2 k a b => Prod k a b `k` a
  exr :: Ok2 k a b => Prod k a b `k` b
  (&&&) :: forall a c d. Ok3 k a c d => (a `k` c) -> (a `k` d) -> (a `k` Prod k c d)

(***) :: forall k a b c d. (Cartesian k, Ok4 k a b c d)
      => (a `k` c) -> (b `k` d) -> (Prod k a b `k` Prod k c d)
f *** g = f . exl &&& g . exr  <+ okProd @k @a @b

dup :: (Cartesian k, Ok k a) => a `k` Prod k a a
dup = id &&& id

swapP :: forall k a b. (Cartesian k, Ok2 k a b) => Prod k a b `k` Prod k b a
swapP = exr &&& exl  <+ okProd @k @a @b

first :: forall k a a' b. (Cartesian k, Ok3 k a b a')
      => (a `k` a') -> (Prod k a b `k` Prod k a' b)
first = (*** id)
second :: forall k a b b'. (Cartesian k, Ok3 k a b b')
       => (b `k` b') -> (Prod k a b `k` Prod k a b')
second = (id ***)

lassocP :: forall k a b c. (Cartesian k, Ok3 k a b c)
        => Prod k a (Prod k b c) `k` Prod k (Prod k a b) c
lassocP = second exl &&& (exr . exr)
          <+ okProd @k @a @(Prod k b c)
          <+ okProd @k @b @c
          <+ okProd @k @a @b

rassocP :: forall k a b c. (Cartesian k, Ok3 k a b c)
        => Prod k (Prod k a b) c `k` Prod k a (Prod k b c)
rassocP = (exl . exl) &&& first  exr
          <+ okProd @k @(Prod k a b) @c
          <+ okProd @k @b @c
          <+ okProd @k @a @b

class OkCoprod k where okCoprod :: (Ok k a, Ok k b) :- Ok k (Coprod k a b)

infixr 2 +++, |||
-- | Category with coproduct.
class (OkCoprod k,Category k) => Cocartesian k where
  type Coprod k (a :: u) (b :: u) = (ab :: u) | ab -> a b
  inl :: Ok2 k a b => a `k` Coprod k a b
  inr :: Ok2 k a b => b `k` Coprod k a b
  (|||) :: forall a c d. Ok3 k a c d
        => (c `k` a) -> (d `k` a) -> (Coprod k c d `k` a)

(+++) :: forall k a b c d. (Cocartesian k, Ok4 k a b c d)
      => (c `k` a) -> (d `k` b) -> (Coprod k c d `k` Coprod k a b)
f +++ g = inl . f ||| inr . g  <+ okCoprod @k @a @b

class (Category k, Ok k (Unit k)) => Terminal k where
  type Unit k :: u
  it :: Ok k a => a `k` Unit k

class OkExp k where okExp :: (Ok k a, Ok k b) :- Ok k (Exp k a b)

class (OkExp k, Cartesian k) => CartesianClosed k where
  type Exp k (a :: u) (b :: u) = (ab :: u) | ab -> a b
  apply   :: forall a b. Ok2 k a b => Prod k (Exp k a b) a `k` b
  apply = uncurry id
          <+ okExp @k @a @b
  curry   :: Ok3 k a b c => (Prod k a b `k` c) -> (a `k` Exp k b c)
  uncurry :: forall a b c. Ok3 k a b c
          => (a `k` Exp k b c)  -> (Prod k a b `k` c)
  uncurry g = apply . first g
              <+ okProd @k @(Exp k b c) @b
              <+ okProd @k @a @b
              <+ okExp  @k @b @c
  {-# MINIMAL curry, (apply | uncurry) #-}

class (Cartesian k, Ok k (BoolOf k)) => BoolCat k where
  type BoolOf k
  notC :: BoolOf k `k` BoolOf k
  andC, orC, xorC :: Prod k (BoolOf k) (BoolOf k) `k` BoolOf k

okDup :: forall k a. OkProd k => Ok k a :- Ok k (Prod k a a)
okDup = okProd @k @a @a . dup

class (BoolCat k, Ok k a) => EqCat k a where
  equal, notEqual :: Prod k a a `k` BoolOf k
  notEqual = notC . equal    <+ okDup @k @a
  equal    = notC . notEqual <+ okDup @k @a

class Ok k a => NumCat k a where
  negateC :: a `k` a
  addC, subC, mulC :: Prod k a a `k` a
  default subC :: Cartesian k => Prod k a a `k` a
  subC = addC . second negateC <+ okProd @k @a @a
  type IntOf k
  powIC :: Prod k a (IntOf k) `k` a

{--------------------------------------------------------------------
    Functors
--------------------------------------------------------------------}

infixr 9 %, %%

class (Category src, Category trg) => FunctorC f src trg | f -> src trg where
  type f %% (a :: u) :: v
  type OkF f (a :: u) (b :: u) :: Constraint
  (%) :: forall a b. OkF f a b => f -> src a b -> trg (f %% a) (f %% b)

class FunctorC f src trg => CartesianFunctor f src trg where
  preserveProd :: Dict ((f %% Prod src a b) ~ Prod trg (f %% a) (f %% b))
  -- default preserveProd :: (f %% Prod src a b) ~ Prod trg (f %% a) (f %% b)
  --              => Dict ((f %% Prod src a b) ~ Prod trg (f %% a) (f %% b))
  -- preserveProd = Dict

-- This preserveProd default doesn't work in instances. Probably a GHC bug.

class FunctorC f src trg => CocartesianFunctor f src trg where
  preserveCoprod :: Dict ((f %% Coprod src a b) ~ Coprod trg (f %% a) (f %% b))

class FunctorC f src trg => CartesianClosedFunctor f src trg where
  preserveExp :: Dict ((f %% Exp src a b) ~ Exp trg (f %% a) (f %% b))

#if 0
-- Functor composition. I haven't been able to get a declared type to pass.

data (g #. f) = g :#. f

-- compF :: forall u v w (p :: u -> u -> Type) (q :: v -> v -> Type) (r :: w -> w -> Type) f g (a :: u) (b :: u).
--          (FunctorC f p q, FunctorC g q r)
--       => g -> f -> (a `p` b) -> ((g %% f %% a) `r` (g %% f %% b))

(g `compF` f) pab = g % f % pab

-- instance (FunctorC f u v, FunctorC g v w) => FunctorC (g #. f) u w where
--   type (g #. f) %% a = g %% (f %% a)
--   type OkF (g #. f) a b = OkF f a b
--   -- (%) (g :#. f) = (g %) . (f %)
--   (g :#. f) % a = g % (f % a)
#endif

{--------------------------------------------------------------------
    Haskell types and functions ("Hask")
--------------------------------------------------------------------}

instance Category (->) where
  id  = P.id
  (.) = (P..)

instance OkProd (->) where okProd = Sub Dict

instance Cartesian (->) where
  type Prod (->) a b = (a,b)
  exl = fst
  exr = snd
  (f &&& g) x = (f x, g x)

instance OkCoprod (->) where okCoprod = Sub Dict

instance Cocartesian (->) where
  type Coprod (->) a b = Either a b
  inl = Left
  inr = Right
  (|||) = either

instance Terminal (->) where
  type Unit (->) = ()
  it = const ()

instance OkExp (->) where okExp = Sub Dict

instance CartesianClosed (->) where
  type Exp (->) a b = a -> b
  apply (f,x) = f x
  curry = P.curry
  uncurry = P.uncurry

instance BoolCat (->) where
  type BoolOf (->) = Bool
  notC = not
  andC = uncurry (&&)
  orC  = uncurry (||)
  xorC = uncurry (/=)

#if 1
data HFunctor (t :: * -> *) = HFunctor

instance Functor t => FunctorC (HFunctor t) (->) (->) where
  type HFunctor t %% a = t a
  type OkF (HFunctor t) a b = ()
  (%) HFunctor = fmap
#else
-- Alternatively, put the `FunctorC` constraint into `HFunctor`:
data HFunctor (t :: * -> *) = Functor t => HFunctor

instance FunctorC (HFunctor t) (->) (->) where
  type HFunctor t %% a = t a
  type OkF (HFunctor t) a b = ()
  (%) HFunctor = fmap
#endif

{--------------------------------------------------------------------
    Kleisli
--------------------------------------------------------------------}

instance Monad m => Category (Kleisli m) where
  id = pack return
  (.) = inNew2 (<=<)

instance Monad m => Cartesian (Kleisli m) where
  type Prod (Kleisli m) a b = (a,b)
  exl = arr exl
  exr = arr exr
  -- Kleisli f &&& Kleisli g = Kleisli ((liftA2.liftA2) (,) f g)
  -- (&&&) = (inNew2.liftA2.liftA2) (,)
  -- Kleisli f &&& Kleisli g = Kleisli (uncurry (liftA2 (,)) . (f &&& g))
  (&&&) = (A.&&&)

-- f :: a -> m b
-- g :: a -> m c
-- f &&& g :: a -> m b :* m c
-- uncurry (liftA2 (,)) . (f &&& g) :: a -> m (b :* c)

instance Monad m => Cocartesian (Kleisli m) where
  type Coprod (Kleisli m) a b = Either a b
  inl = arr inl
  inr = arr inr
  (|||) = (A.|||)

instance Monad m => Terminal (Kleisli m) where
  type Unit (Kleisli m) = ()
  it = arr it

instance OkProd   (Kleisli m) where okProd   = Sub Dict
instance OkCoprod (Kleisli m) where okCoprod = Sub Dict
instance OkExp    (Kleisli m) where okExp    = Sub Dict

instance Monad m => CartesianClosed (Kleisli m) where
  type Exp (Kleisli m) a b = Kleisli m a b
  apply   = pack (apply . first unpack)
  curry   = inNew (\ f -> return . pack . curry f)
  uncurry = inNew (\ g -> \ (a,b) -> g a >>= ($ b) . unpack)

-- We could handle Kleisli categories as follows, but we'll want specialized
-- versions for specific monads m.

-- instance Monad m => BoolCat (Kleisli m) where
--   type BoolOf (Kleisli m) = Bool
--   notC = arr notC
--   andC = arr andC
--   orC  = arr orC
--   xorC = arr xorC

{--------------------------------------------------------------------
    Constraint entailment
--------------------------------------------------------------------}

instance Category (:-) where
  id  = Sub Dict
  g . f = Sub (Dict <+ g <+ f)

instance OkProd (:-) where okProd = Sub Dict

instance Cartesian (:-) where
  type Prod (:-) a b = (a,b)
  exl = Sub Dict
  exr = Sub Dict
  f &&& g = Sub (Dict <+ f <+ g)

-- instance Category (|-) where
--   id  = refl
--   (.) = trans

instance Terminal (|-) where
  type Unit (|-) = ()
  it = Sub Dict

-- Tweaked from Data.Constraint
mapDict :: (a |- b) -> Dict a -> Dict b
mapDict (Sub q) Dict = q

unmapDict :: (Dict a -> Dict b) -> (a |- b)
unmapDict f = Sub (f Dict)

data MapDict = MapDict

instance FunctorC MapDict (|-) (->) where
  type MapDict %% a = Dict a
  type OkF MapDict a b = ()
  (%) MapDict = mapDict

-- -- Couldn't match type ‘Dict (a && b)’ with ‘(Dict a, Dict b)’
-- instance CartesianFunctor MapDict (|-) (->) where preserveProd = Dict

class HasCon a where
  type Con a :: Constraint
  toDict :: a -> Dict (Con a)
  unDict :: Dict (Con a) -> a

instance HasCon (Dict con) where
  type Con (Dict con) = con
  toDict = id
  unDict = id

instance (HasCon a, HasCon b) => HasCon (a,b) where
  type Con (a,b) = (Con a,Con b)
  toDict (toDict -> Dict, toDict -> Dict) = Dict
  unDict Dict = (unDict Dict,unDict Dict)

entail :: (HasCon a, HasCon b) => (a -> b) -> (Con a |- Con b)
entail f = unmapDict (toDict . f . unDict)

data Entail = Entail

instance FunctorC Entail (->) (:-) where
  type Entail %% a = Con a
  type OkF Entail a b = (HasCon a, HasCon b)
  (%) Entail = entail

-- -- Couldn't match type ‘(Con a, Con b)’ with ‘Con a && Con b’.
-- instance CartesianFunctor Entail (->) (|-) where preserveProd = Dict
-- -- Fails:
-- preserveProd :: Dict (MapDict %% (a && b)) ~ (MapDict %% a, MapDict %% b)

-- Isomorphic but not equal.

{--------------------------------------------------------------------
    Functors applied to given type argument
--------------------------------------------------------------------}

newtype Arg (s :: Type) a b = Arg { unArg :: a s -> b s }

instance Newtype (Arg s a b) where
  { type O (Arg s a b) = a s -> b s ; pack = Arg ; unpack = unArg }

instance Category (Arg s) where
  id = pack id
  (.) = inNew2 (.)

instance OkProd (Arg s) where okProd = Sub Dict

instance Cartesian (Arg s) where
  type Prod (Arg s) a b = a :*: b
  exl = pack (\ (a :*: _) -> a)
  exr = pack (\ (_ :*: b) -> b)
  (&&&) = inNew2 forkF

forkF :: (a t -> c t) -> (a t -> d t) -> a t -> (c :*: d) t
forkF = ((fmap.fmap.fmap) pack (&&&))

-- forkF ac ad = \ a -> (ac a :*: ad a)
-- forkF ac ad = \ a -> pack (ac a,ad a)
-- forkF ac ad = pack . (ac &&& ad)

instance OkCoprod (Arg s) where okCoprod = Sub Dict

instance Cocartesian (Arg s) where
  type Coprod (Arg s) a b = a :+: b
  inl = pack L1
  inr = pack R1
  (|||) = inNew2 eitherF

instance Terminal (Arg s) where
  type Unit (Arg s) = U1
  it = Arg (const U1)

instance OkExp (Arg s) where okExp = Sub Dict

instance CartesianClosed (Arg s) where
  type Exp (Arg s) a b = a +-> b -- from ConCat.Misc
  apply = pack (\ (Fun1 f :*: a) -> f a)
  curry = inNew (\ f -> pack . curry (f . pack))
  uncurry = inNew (\ g -> uncurry (unpack . g) . unpack)

-- curry :: Arg s (a :*: b) c -> Arg s a (b +-> c)

-- Arg f :: Arg s (a :*: b) c
-- f :: (a :*: b) s -> c s
-- f . pack :: (a s,b s) -> c s
-- curry (f . pack) :: a s -> b s -> c s
-- pack . curry (f . pack) :: a s -> (b +-> c) s

--   apply   :: forall a b. Ok2 k a b => Prod k (Exp k a b) a `k` b
--   curry   :: Ok3 k a b c => (Prod k a b `k` c) -> (a `k` Exp k b c)
--   uncurry :: forall a b c. Ok3 k a b c
--           => (a `k` Exp k b c)  -> (Prod k a b `k` c)

toArg :: (HasV s a, HasV s b) => (a -> b) -> Arg s (V s a) (V s b)
toArg f = Arg (toV . f . unV)

-- unArg :: (HasV s a, HasV s b) => Arg s (V s a) (V s b) -> (a -> b)
-- unArg (Arg g) = unV . g . toV

data ToArg (s :: Type) = ToArg

instance FunctorC (ToArg s) (->) (Arg s) where
  type ToArg s %% a = V s a
  type OkF (ToArg s) a b = (HasV s a, HasV s b)
  (%) ToArg = toArg

instance   CartesianFunctor (ToArg s) (->) (Arg s) where   preserveProd = Dict
instance CocartesianFunctor (ToArg s) (->) (Arg s) where preserveCoprod = Dict

-- -- Couldn't match type ‘(->) a :.: V s b’ with ‘V s a +-> V s b’
-- instance CartesianClosedFunctor (ToArg s) (->) (Arg s) where preserveExp = Dict

{--------------------------------------------------------------------
    Linear maps
--------------------------------------------------------------------}

-- Linear map in row-major form
newtype LM s a b = LMap (b (a s))

instance Num s => Category (LM s) where
  type Ok (LM s) = OkLF
  id = LMap idL
  LMap g . LMap f = LMap (g @. f)

instance OkProd (LM s) where okProd = Sub Dict

instance Num s => Cartesian (LM s) where
  type Prod (LM s) a b = a :*: b
  exl = LMap exlL
  exr = LMap exrL
  LMap g &&& LMap f = LMap (g `forkL` f)

instance OkCoprod (LM s) where okCoprod = Sub Dict
  
instance Num s => Cocartesian (LM s) where
  type Coprod (LM s) a b = a :*: b
  inl = LMap inlL
  inr = LMap inrL
  LMap f ||| LMap g = LMap (f `joinL` g)

toLMap :: (OkLF b, HasL a, Num s) => Arg s a b -> LM s a b
toLMap (Arg h) = LMap (linearL h)

data ToLMap s = ToLMap
instance Num s => FunctorC (ToLMap s) (Arg s) (LM s) where
  type ToLMap s %% a = a
  type OkF (ToLMap s) a b = (OkLF b, HasL a)
  (%) ToLMap = toLMap

instance Num s => CartesianFunctor (ToLMap s) (Arg s) (LM s) where preserveProd = Dict

#if 0

-- Apply a linear map
lapply :: (Zip a, Foldable a, Zip b, Num s) => LM s a b -> Arg s a b
lapply (LMap ba) = Arg (lapplyL ba)

data Lapply s = Lapply
instance Num s => FunctorC (Lapply s) (LM s) (Arg s) where
  type Lapply s %% a = a
  type OkF (Lapply s) a b = (Zip a, Foldable a, Zip b)
  (%) Lapply = lapply

#else

-- Apply a linear map
lapply :: (Zip a, Foldable a, Zip b, Num s) => LM s a b -> (a s -> b s)
lapply (LMap ba) = lapplyL ba

data Lapply s = Lapply
instance Num s => FunctorC (Lapply s) (LM s) (->) where
  type Lapply s %% a = a s
  type OkF (Lapply s) a b = (Zip a, Foldable a, Zip b)
  (%) Lapply = lapply

#endif

linear :: (Num s, HasL a, OkLF b) => Arg s a b -> LM s a b
linear (Arg h) = LMap (linearL h)

data Linear s = Linear
instance Num s => FunctorC (Linear s) (Arg s) (LM s) where
  type Linear s %% a = a
  type OkF (Linear s) a b = (HasL a, OkLF b)
  (%) Linear = linear

{--------------------------------------------------------------------
    Differentiable functions
--------------------------------------------------------------------}

-- | Differentiable function on vector space with field s
data DF s a b = D { unD :: a s -> (b s, LM s a b) }

-- TODO: try a more functorish representation: (a :->: b :*: (a :->: b))

deriv :: (a s -> b s) -> (a s -> LM s a b)
deriv f = snd . unD (andDeriv (Arg f))
-- deriv f = snd . h where D h = andDeriv (Arg f)

andDeriv :: Arg s a b -> DF s a b
andDeriv (Arg f) = D (f &&& deriv f)  -- specification

linearD :: (Num s, Ok2 (LM s) a b) => LM s a b -> DF s a b
linearD m = D (lapply m &&& const m)

instance Num s => Category (DF s) where
  type Ok (DF s) = OkLF
  id = linearD id
  D g . D f = D (\ a -> let { (b,f') = f a; (c,g') = g b } in (c, g' . f'))
  {-# INLINE id #-}
  {-# INLINE (.) #-}

instance OkProd (DF s) where okProd = Sub Dict

instance Num s => Cartesian (DF s) where
  type Prod (DF s) a b = a :*: b
  exl = linearD exl
  exr = linearD exr
  D f &&& D g = D (\ a -> let { (b,f') = f a ; (c,g') = g a } in (b :*: c, f' &&& g'))
  {-# INLINE exl #-}
  {-# INLINE exr #-}
  {-# INLINE (&&&) #-}

instance OkCoprod (DF s) where okCoprod = Sub Dict

instance Num s => Cocartesian (DF s) where
  type Coprod (DF s) a b = a :*: b
  inl = linearD inl
  inr = linearD inr
  D f ||| D g = D (\ (a :*: b) -> let { (c,f') = f a ; (d,g') = g b } in (c ^+^ d, f' ||| g'))
  {-# INLINE inl #-}
  {-# INLINE inr #-}
  {-# INLINE (|||) #-}

#if 0

f :: a s -> (c s, a s -> c s)
g :: b s -> (c s, b s -> c s)

a :: a s
b :: b s
c, d :: c s

f' :: a s -> c s
g' :: b s -> c s

#endif

data Deriv s = Deriv
instance Num s => FunctorC (Deriv s) (Arg s) (DF s) where
  type Deriv s %% a = a
  type OkF (Deriv s) a b = OkF (ToLMap s) a b
  (%) Deriv = andDeriv
              -- oops "Deriv % not implemented"

instance Num s => CartesianFunctor (Deriv s) (Arg s) (DF s) where preserveProd = Dict

{--------------------------------------------------------------------
    Circuits
--------------------------------------------------------------------}

-- Copy from C.hs after tweaking

{--------------------------------------------------------------------
    Standardize types
--------------------------------------------------------------------}

class HasStd a where
  type Standard a
  toStd :: a -> Standard a
  unStd :: Standard a -> a
  -- defaults via Rep
  type Standard a = Rep a
  default toStd :: HasRep a => a -> Rep a
  default unStd :: HasRep a => Rep a -> a
  toStd = repr
  unStd = abst

standardize :: (HasStd a, HasStd b) => (a -> b) -> (Standard a -> Standard b)
standardize = toStd <~ unStd

instance (HasStd a, HasStd b) => HasStd (a,b) where
  type Standard (a,b) = (Standard a, Standard b)
  toStd = toStd *** toStd
  unStd = unStd *** unStd

instance (HasStd a, HasStd b) => HasStd (Either a b) where
  type Standard (Either a b) = Either (Standard a) (Standard b)
  toStd = toStd +++ toStd
  unStd = unStd +++ unStd

instance (HasStd a, HasStd b) => HasStd (a -> b) where
  type Standard (a -> b) = Standard a -> Standard b
  toStd = toStd <~ unStd
  unStd = unStd <~ toStd

#define StdPrim(ty) \
instance HasStd (ty) where { type Standard (ty) = (ty) ; toStd = id ; unStd = id }

StdPrim(())
StdPrim(Bool)
StdPrim(Int)
StdPrim(Float)
StdPrim(Double)

instance (HasStd a, HasStd b, HasStd c) => HasStd (a,b,c)

-- If this experiment works out, move HasStd to ConCat.Rep and add instances there.

data Standardize s = Standardize

instance FunctorC (Standardize s) (->) (->) where
  type Standardize s %% a = Standard a
  type OkF (Standardize s) a b = (HasStd a, HasStd b)
  (%) Standardize = standardize

instance CartesianFunctor       (Standardize s) (->) (->) where preserveProd   = Dict
instance CocartesianFunctor     (Standardize s) (->) (->) where preserveCoprod = Dict
instance CartesianClosedFunctor (Standardize s) (->) (->) where preserveExp    = Dict

{--------------------------------------------------------------------
    Memoization
--------------------------------------------------------------------}

-- Copy & tweak from C.hs
