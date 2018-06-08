{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-unused-imports #-} -- TEMP

-- When spurious recompilation is fixed, use this plugin, and drop ConCat.Known.
-- {-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}

-- | Domain-typed arrays

module ConCat.TArr where

import Prelude hiding (id, (.), const, curry, uncurry)  -- Coming from ConCat.AltCat.

import Data.Monoid
import Data.Foldable
import GHC.TypeLits
import GHC.Types (Nat)
import Data.Proxy
-- import Data.Tuple            (swap)

import Data.Finite.Internal  (Finite(..))
import Data.Vector.Sized (Vector)
import qualified Data.Vector.Sized as V
import Control.Newtype
import Data.Distributive (Distributive(..))
import Data.Functor.Rep (Representable,index,tabulate,distributeRep)
import qualified Data.Functor.Rep as R
import Data.Constraint ((\\))

import ConCat.Misc           ((:*), (:+), cond,nat,int)
import ConCat.Rep
import ConCat.AltCat
import ConCat.Isomorphism
import ConCat.Known

{----------------------------------------------------------------------
   Some useful isomorphisms.
----------------------------------------------------------------------}

finSum :: forall k m n. (FiniteCat k, KnownNat2 m n) => Iso k (Finite m :+ Finite n) (Finite (m + n))
finSum = Iso combineSum separateSum
{-# INLINE finSum #-}

finProd :: forall k m n. (FiniteCat k, KnownNat2 m n) => Iso k (Finite m :* Finite n) (Finite (m * n))
finProd = Iso combineProd separateProd
{-# INLINE finProd #-}

-- finSum :: forall m n. KnownNat m => Finite m :+ Finite n <-> Finite (m + n)
-- finSum = Iso combineSum separateSum

-- finSum = Iso to un
--  where 
--    to (Left  (Finite l)) = Finite l
--    to (Right (Finite k)) = Finite (nat @m + k)
--    un (Finite l) | l < m     = Left  (Finite l)
--                  | otherwise = Right (Finite (l - m))
--     where
--       m = nat @m

-- finProd :: forall m n. KnownNat n => Finite m :* Finite n <-> Finite (m * n)
-- finProd = Iso combineProd separateProd

-- finProd = Iso to un
--  where
--    to (Finite l, Finite k) = Finite (nat @n * l + k)
--    un (Finite l) = (Finite q, Finite r) where (q,r) = l `divMod` nat @n

#if 0

type a :^ b = b -> a

-- Using Horner's rule and its inverse, as per Conal's suggestion.
finExp :: forall m n. KnownNat2 m n => Finite m :^ Finite n <-> Finite (m ^ n)
finExp = Iso h g
  where -- g :: forall m n. KnownNat2 m n => Finite (m ^ n) -> Finite m :^ Finite n
        g (Finite l) = \ n -> v `V.index` n
          where v :: V.Vector n (Finite m)
                v = V.unfoldrN (first Finite . swap . flip divMod (nat @m)) l

        -- h :: forall m n. KnownNat2 m n => Finite m :^ Finite n -> Finite (m ^ n)
        -- h f = Finite $ V.foldl' (\accum m -> accum * (nat @m) + getFinite m)
        --                       0
        --                       $ V.reverse $ V.generate f
        -- h f = V.foldl' (curry u) (Finite 0) ((V.reverse . V.generate) f)
        -- h = V.foldl' (curry u) (Finite 0) . (V.reverse . V.generate)
        h = (V.foldl' . curry) u (Finite 0) . (V.reverse . V.generate)
          where u (Finite acc, Finite m) = Finite (acc * nat @m + m)

inFin :: (HasFin a, HasFin b) => (Finite (Card a) -> Finite (Card b)) -> (a -> b)
inFin f' = unFin . f' . toFin

liftFin :: (HasFin a, HasFin b) => (a -> b) -> Finite (Card a) -> Finite (Card b)
liftFin f = toFin . f . unFin

#endif

toFin :: HasFin a => a -> Finite (Card a)
toFin = isoFwd iso

unFin :: HasFin a => Finite (Card a) -> a
unFin = isoRev iso

{----------------------------------------------------------------------
   A class of types with known finite representations.
----------------------------------------------------------------------}

type KnownCard a = KnownNat (Card a)

type KnownCard2 a b = (KnownCard a, KnownCard b)

class {- KnownCard a => -} HasFin a where
  type Card a :: Nat
  iso :: a <-> Finite (Card a)

-- See below.
type HasFin' a = (KnownCard a, HasFin a)

instance HasFin () where
  type Card () = 1
  iso = Iso (const (Finite 0)) (const ())

instance HasFin Bool where
  type Card Bool = 2
  iso = Iso (Finite . cond 1 0) (\ (Finite n) -> n > 0)

instance KnownNat n => HasFin (Finite n) where
  type Card (Finite n) = n
  iso = id

-- Moving KnownCard from HasFin to HasFin' solves the puzzle of persuading GHC
-- that KnownCard (a :+ b), a superclass constraint for HasFin (a :+ b). When
-- the spurious recompilation problem is fixed, and we drop the explicit
-- KnownNat entailments, move KnownCard back to HasFin.

instance (HasFin' a, HasFin' b) => HasFin (a :+ b) where
  type Card (a :+ b) = Card a + Card b
  iso = finSum . (iso +++ iso)

instance (HasFin' a, HasFin' b) => HasFin (a :* b) where
  type Card (a :* b) = Card a * Card b
  iso = finProd . (iso *** iso)

-- instance (HasFin a, HasFin b) => HasFin (a :^ b) where
--   type Card (a :^ b) = Card a ^ Card b
--   iso = finExp . Iso liftFin inFin

{----------------------------------------------------------------------
  Domain-typed "arrays"
----------------------------------------------------------------------}

newtype Arr a b = Arr (Vector (Card a) b)

instance Newtype (Arr a b) where
  type O (Arr a b) = Vector (Card a) b
  pack v = Arr v
  unpack (Arr v) = v

instance HasRep (Arr a b) where
  type Rep (Arr a b) = O (Arr a b)
  abst = pack
  repr = unpack

-- TODO: maybe a macro for HasRep instances that mirror Newtype instances.

deriving instance Functor (Arr a)
deriving instance HasFin' a => Applicative (Arr a)

-- TODO: Distributive and Representable instances.

instance HasFin' a => Distributive (Arr a) where
  distribute :: Functor f => f (Arr a b) -> Arr a (f b)
  distribute = distributeRep
  {-# INLINE distribute #-}

instance HasFin' a => Representable (Arr a) where
  type Rep (Arr a) = a
  tabulate :: (a -> b) -> Arr a b
  tabulate f = pack (tabulate (f . unFin))
  index :: Arr a b -> (a -> b)
  Arr v `index` a = v `index` toFin a
  {-# INLINE tabulate #-}
  {-# INLINE index #-}

(!) :: HasFin' a => Arr a b -> (a -> b)
(!) = index
{-# INLINE (!) #-}

type Flat f = Arr (R.Rep f)

{--------------------------------------------------------------------
    Splitting
--------------------------------------------------------------------}

chunk :: forall m n a. KnownNat2 m n => Vector (m * n) a -> Finite m -> Vector n a
chunk mn i = tabulate (index mn . curry toFin i) \\ knownMul @m @n
{-# INLINE chunk #-}

#if 0

                as                  :: Vector (m * n) a
                                 i  :: Finite m
                           toFin    :: Finite m :* Finite n -> Finite (m :* n)
                     curry toFin    :: Finite m -> Finite n -> Finite (m :* n)
                     curry toFin i  :: Finite n -> Finite (m :* n)
          index as                  :: Finite (m :* n) -> a
          index as . curry toFin i  :: Finite n -> a
tabulate (index as . curry toFin i) :: Vector n a

#endif

vecSplitSum :: forall m n a. KnownNat2 m n => Vector (m + n) a -> Vector m a :* Vector n a
vecSplitSum as = (tabulate *** tabulate) (unjoin (index as . toFin)) \\ knownAdd @m @n
{-# INLINE vecSplitSum #-}

#if 0

                             as           :: Vector (m + n) a
                       index as           :: Finite (m + n) -> a
                       index as . toFin   :: Finite m :+ Finite n -> a
               unjoin (index as . toFin)  :: (Finite m -> a) :* (Finite n -> a)
(tab *** tab) (unjoin (index as . toFin)) :: Vector m a :* Vector n a

#endif

arrSplitSum :: KnownCard2 a b => Arr (a :+ b) c -> Arr a c :* Arr b c
arrSplitSum = (pack *** pack) . vecSplitSum . unpack
{-# INLINE arrSplitSum #-}

vecSplitProd :: KnownNat2 m n => Vector (m * n) a -> Vector m (Vector n a)
vecSplitProd = tabulate . chunk
{-# INLINE vecSplitProd #-}

-- vecSplitProd as = tabulate (chunk as)
-- vecSplitProd as = tabulate (\ i -> chunk as i)

arrSplitProd :: KnownCard2 a b => Arr (a :* b) c -> Arr a (Arr b c)
arrSplitProd = pack . fmap pack . vecSplitProd . unpack
{-# INLINE arrSplitProd #-}

{--------------------------------------------------------------------
    Folds
--------------------------------------------------------------------}

#if 0

instance (HasFin a, Foldable ((->) a)) => Foldable (Arr a) where
  foldMap f = foldMap f . index
  {-# INLINE foldMap #-}

#else

-- The explicit repetition of the fold and sum defaults below prevent premature
-- optimization that leads to exposing the representation of unsized vectors.
-- See 2018-06-07 journal notes.

#define DEFAULTS \
fold = foldMap id ; \
{-# INLINE fold #-} ; \
sum = getSum . foldMap Sum ; \
{-# INLINE sum #-}

instance Foldable (Arr ()) where
  -- foldMap f xs = f (xs ! ())
  foldMap f xs = f (xs ! ())
  {-# INLINE foldMap #-}
  DEFAULTS
  -- fold = foldMap id ; {-# INLINE fold #-}
  -- sum = getSum . foldMap Sum ; {-# INLINE sum #-}

instance Foldable (Arr Bool) where
  foldMap f xs = f (xs ! False) <> f (xs ! True)
  {-# INLINE foldMap #-}
  DEFAULTS
  -- sum = getSum . foldMap Sum ; {-# INLINE sum #-}
  -- fold = foldMap id; {-# INLINE fold #-}

instance (Foldable (Arr a), Foldable (Arr b), KnownCard2 a b)
      => Foldable (Arr (a :+ b)) where
  -- foldMap f u = foldMap f v <> foldMap f w where (v,w) = arrSplitSum u
  foldMap f = uncurry (<>) . (foldMap f *** foldMap f) . arrSplitSum
  {-# INLINE foldMap #-}
  -- sum = getSum . foldMap Sum ; {-# INLINE sum #-}
  -- fold = foldMap id; {-# INLINE fold #-}

instance (Foldable (Arr a), Foldable (Arr b), KnownCard2 a b)
      => Foldable (Arr (a :* b)) where
  -- foldMap f = (foldMap.foldMap) f . arrSplitProd
  foldMap f = fold . fmap f
  {-# INLINE foldMap #-}
  fold = fold . fmap fold . arrSplitProd
  {-# INLINE fold #-}
  sum = getSum . foldMap Sum ; {-# INLINE sum #-}

#endif
