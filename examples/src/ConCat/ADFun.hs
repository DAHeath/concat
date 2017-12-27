{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ViewPatterns #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP

-- | Automatic differentiation

module ConCat.ADFun where

import Prelude hiding (id,(.),curry,uncurry,const,zip,unzip)
-- import Debug.Trace (trace)
import GHC.Generics (Par1)

import Control.Newtype (Newtype(..))
import Data.Pointed (Pointed(..))
import Data.Key (Zip(..))
import Data.Constraint hiding ((&&&),(***),(:=>))
import Data.Distributive (Distributive(..))
import Data.Functor.Rep (Representable(..))

import ConCat.Misc ((:*),R,Yes1,oops,unzip,type (&+&),sqr)
import ConCat.Free.VectorSpace (HasV(..),inV,IsScalar)
import ConCat.Free.LinearRow -- hiding (linear)
import ConCat.AltCat
import ConCat.GAD -- hiding (linear)
import ConCat.Additive
-- The following imports allows the instances to type-check. Why?
import qualified ConCat.Category  as C

-- Differentiable functions
type D = GD (->)

-- type instance GDOk (->) = Yes1

-- type instance GDOk (->) = Additive

#if 0
instance ClosedCat D where
  apply = D (\ (f,a) -> (f a, \ (df,da) -> df a ^+^ deriv f a da))
  curry (D h) = D (\ a -> (curry f a, \ da -> \ b -> f' (a,b) (da,zero)))
   where
     (f,f') = unfork h
  {-# INLINE apply #-}
  {-# INLINE curry #-}

-- TODO: generalize to ClosedCat k for an arbitrary CCC k. I guess I can simply
-- apply ccc to the lambda expressions.
#elif 1

instance ClosedCat D where
  apply = applyD ; {-# INLINE apply #-}
  curry = curryD ; {-# INLINE curry #-}

applyD :: forall a b. Ok2 D a b => D ((a -> b) :* a) b
-- applyD = D (\ (f,a) -> (f a, \ (df,da) -> df a ^+^ f da))
applyD = -- trace "calling applyD" $
 D (\ (f,a) -> let (b,f') = andDerF f a in (b, \ (df,da) -> df a ^+^ f' da))
-- applyD = oops "applyD called"   -- does it?

curryD :: forall a b c. Ok3 D a b c => D (a :* b) c -> D a (b -> c)
curryD (D (unfork -> (f,f'))) =
  D (\ a -> (curry f a, \ da -> \ b -> f' (a,b) (da,zero)))

{-# INLINE applyD #-}
{-# INLINE curryD #-}
#else
-- No ClosedCat D instance
#endif


-- instance ClosedCat (D s) where
--   apply = applyD
-- --   curry = curryD

-- applyD :: forall s a b. Ok2 (D s) a b => D s ((a -> b) :* a) b
-- applyD = D (\ (f,a) -> let (b,f') = andDeriv f a in
--               (b, _))

-- Differentiable linear function
linearDF :: (a -> b) -> D a b
linearDF f = linearD f f
{-# INLINE linearDF #-}

-- TODO: use linear in place of linearDF

instance Additive b => ConstCat D b where
  const b = D (const (b, const zero))
  {-# INLINE const #-}

instance TerminalCat D where
  it = const ()
  {-# INLINE it #-}

instance (Num s, Additive s) => NumCat D s where
  negateC = linearDF negateC
  addC    = linearDF addC
  mulC    = D (mulC &&& \ (a,b) (da,db) -> a * db + da * b)
  powIC   = notDef "powIC"       -- TODO
  {-# INLINE negateC #-}
  {-# INLINE addC    #-}
  {-# INLINE mulC    #-}
  {-# INLINE powIC   #-}

-- const' :: (a -> c) -> (a -> b -> c)
-- const' = (const .)

scalarD :: Num s => (s -> s) -> (s -> s -> s) -> D s s
scalarD f d = D (\ x -> let r = f x in (r, (* d x r)))
{-# INLINE scalarD #-}

-- Use scalarD with const f when only r matters and with const' g when only x
-- matters.

scalarR :: Num s => (s -> s) -> (s -> s) -> D s s
scalarR f f' = scalarD f (\ _ -> f')
-- scalarR f x = scalarD f (const x)
-- scalarR f   = scalarD f . const
{-# INLINE scalarR #-}

scalarX :: Num s => (s -> s) -> (s -> s) -> D s s
scalarX f f' = scalarD f (\ x _ -> f' x)
-- scalarX f f' = scalarD f (\ x y -> const (f' x) y)
-- scalarX f f' = scalarD f (\ x   -> const (f' x))
-- scalarX f f' = scalarD f (const . f')
-- scalarX f f' = scalarD f (const' f')
-- scalarX f    = scalarD f . const'
{-# INLINE scalarX #-}

instance (Fractional s, Additive s) => FractionalCat D s where
  recipC = scalarR recip (negate . sqr)
  {-# INLINE recipC #-}

instance (Floating s, Additive s) => FloatingCat D s where
  expC = scalarR exp id
  logC = scalarX log recip
  sinC = scalarX sin cos
  cosC = scalarX cos (negate . sin)
  {-# INLINE expC #-}
  {-# INLINE sinC #-}
  {-# INLINE cosC #-}
  {-# INLINE logC #-}

instance Ord a => MinMaxCat D a where
  -- minC = D (\ (x,y) -> (minC (x,y), if x <= y then exl else exr))
  -- maxC = D (\ (x,y) -> (maxC (x,y), if x <= y then exr else exl))
  minC = D (\ xy -> (minC xy, if lessThanOrEqual xy then exl else exr))
  maxC = D (\ xy -> (maxC xy, if lessThanOrEqual xy then exr else exl))
  {-# INLINE minC #-} 
  {-# INLINE maxC #-} 

-- type Ok D = (Yes1 &+& Additive)

-- instance Additive1 h => OkFunctor D h where
--   okFunctor :: forall a. Ok' D a |- Ok' D (h a)
--   okFunctor = inForkCon (yes1 *** additive1 @h @a)
--   {-# INLINE okFunctor #-}

instance (Functor h, Zip h, Additive1 h) => FunctorCat D h where
  fmapC (D q) = D (second zap . unzip . fmap q)
  unzipC = linearDF unzipC
  {-# INLINE fmapC #-}

-- q :: a -> b :* (a -> b)

-- fmap q :: h a -> h (b :* (a -> b))
-- unzip . fmap q :: h a -> h b :* h (a -> b)

-- TODO: Move OkFunctor and FunctorCat instances to GAD.

#if 0

-- Now generalized in GAD

instance (Zip h, Additive1 h) => ZipCat D h where
  zipC = linearDF zipC
  {-# INLINE zipC #-}
  -- zipWithC = linearDF zipWithC
  -- {-# INLINE zipWithC #-}

instance (Pointed h, Additive1 h) => PointedCat D h where
  pointC = linearDF pointC
  {-# INLINE pointC #-}

instance (Foldable h, Additive1 h) => SumCat D h where
  sumC = linearDF sumC
  {-# INLINE sumC #-}

instance (Zip h, Foldable h, Additive1 h) => Strong D h where
  strength = linearDF strength
  {-# INLINE strength #-}

instance (Distributive g, Functor f) => DistributiveCat D g f where
  distributeC = linearDF distributeC
  {-# INLINE distributeC #-}

instance Representable g => RepresentableCat D g where
  indexC    = linearDF indexC
  tabulateC = linearDF tabulateC
  {-# INLINE indexC #-}
  {-# INLINE tabulateC #-}

#endif

{--------------------------------------------------------------------
    Differentiation interface
--------------------------------------------------------------------}

-- Type specialization of andDeriv
andDerF :: forall a b . (a -> b) -> (a -> b :* (a -> b))
andDerF = andDeriv
{-# INLINE andDerF #-}

-- Type specialization of deriv
derF :: forall a b . (a -> b) -> (a -> (a -> b))
derF = deriv
{-# INLINE derF #-}

-- AD with derivative-as-function, then converted to linear map
andDerFL :: forall s a b. HasLin s a b => (a -> b) -> (a -> b :* L s a b)
andDerFL f = second linear . andDerF f
{-# INLINE andDerFL #-}

-- AD with derivative-as-function, then converted to linear map
derFL :: forall s a b. HasLin s a b => (a -> b) -> (a -> L s a b)
derFL f = linear . derF f
{-# INLINE derFL #-}

dualV :: forall s a. (HasLin s a s, IsScalar s) => (a -> s) -> a
dualV h = unV (unpack (unpack (linear @s h)))
{-# INLINE dualV #-}

--                                h    :: a -> s
--                      linear @s h    :: L s a s
--              unpack (linear @s h)   :: V s s (V s a s)
--                                     :: Par1 (V s a s)
--      unpack (unpack (linear @s h))  :: V s a s
-- unV (unpack (unpack (linear @s h))) :: a

andGradFL :: (HasLin s a s, IsScalar s) => (a -> s) -> (a -> s :* a)
andGradFL f = second dualV . andDerF f
{-# INLINE andGradFL #-}

gradF :: (HasLin s a s, IsScalar s) => (a -> s) -> (a -> a)
gradF f = dualV . derF f
{-# INLINE gradF #-}

#if 1

{--------------------------------------------------------------------
    Conversion to linear map. Replace HasL in LinearRow and LinearCol
--------------------------------------------------------------------}

linear1 :: (Representable f, Eq (Rep f), Num s)
        => (f s -> s) -> f s
-- linear1 = (<$> diag 0 1)
linear1 = (`fmapC` diag 0 1)
{-# INLINE linear1 #-}

linearN :: (Representable f, Eq (Rep f), Distributive g, Num s)
        => (f s -> g s) -> (f :-* g) s
linearN h = linear1 <$> distribute h
{-# INLINE linearN #-}

-- h :: f s -> g s
-- distribute h :: g (f s -> s)
-- linear1 <$> distribute h :: g (f s)

{--------------------------------------------------------------------
    Alternative definitions using Representable
--------------------------------------------------------------------}

type RepresentableV s a = (HasV s a, Representable (V s a))
type RepresentableVE s a = (RepresentableV s a, Eq (Rep (V s a)))
type HasLinR s a b = (RepresentableVE s a, RepresentableV s b, Num s)

linearNR :: ( HasV s a, RepresentableVE s a
            , HasV s b, Distributive (V s b), Num s )
         => (a -> b) -> L s a b
linearNR h = pack (linear1 <$> distribute (inV h))
{-# INLINE linearNR #-}

-- AD with derivative-as-function, then converted to linear map
andDerFLR :: forall s a b. HasLinR s a b => (a -> b) -> (a -> b :* L s a b)
andDerFLR f = second linearNR . andDerF f
{-# INLINE andDerFLR #-}

-- AD with derivative-as-function, then converted to linear map
derFLR :: forall s a b. HasLinR s a b => (a -> b) -> (a -> L s a b)
derFLR f = linearNR . derF f
{-# INLINE derFLR #-}

dualVR :: forall s a. (HasV s a, RepresentableVE s a, IsScalar s, Num s)
      => (a -> s) -> a
dualVR h = unV (linear1 (unpack . inV @s h))
{-# INLINE dualVR #-}

--                            h   :: a -> s
--                        inV h   :: V s a s -> V s s s
--                                :: V s a s -> Par1 s
--              (unpack . inV h)  :: V s a s -> s
--      linear1 (unpack . inV h)  :: V s a s
-- unV (linear1 (unpack . inV h)) :: a

andGradFLR :: forall s a. (IsScalar s, RepresentableVE s a, Num s)
           => (a -> s) -> (a -> s :* a)
andGradFLR f = second dualVR . andDerF f
{-# INLINE andGradFLR #-}

gradFR :: forall s a. (IsScalar s, RepresentableVE s a, Num s)
       => (a -> s) -> (a -> a)
gradFR f = dualVR . derF f
{-# INLINE gradFR #-}

#endif

