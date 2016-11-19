{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE PatternGuards #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-} -- TEMP
-- {-# OPTIONS_GHC -fno-warn-unused-binds -fno-warn-unused-matches #-} -- TEMP

-- | GHC plugin converting to CCC form.

module ConCat.Plugin where

import Control.Arrow (first)
import Control.Applicative (liftA2,(<|>))
import Control.Monad (unless,guard)
import Data.Foldable (toList)
import Data.Maybe (isNothing,fromMaybe,catMaybes)
import Data.List (isPrefixOf,isSuffixOf,elemIndex,sort)
import Data.Char (toLower)
import Data.Data (Data)
import Data.Generics (GenericQ,mkQ,everything)
import Data.Sequence (Seq)
import qualified Data.Sequence as S
import Data.Map (Map)
import qualified Data.Map as M
import Text.Printf (printf)

import GhcPlugins hiding (substTy,cat)
import Class (classAllSelIds)
import CoreArity (etaExpand)
import CoreLint (lintExpr)
import DynamicLoading
import MkId (mkDictSelRhs)
import Pair (Pair(..))
import PrelNames (leftDataConName,rightDataConName)
import Type (coreView)
import TcType (isIntTy, isFloatTy, isDoubleTy)
import FamInstEnv (normaliseType)
import TyCoRep                          -- TODO: explicit imports
import Unique (mkBuiltinUnique)

import ConCat.Misc (Unop,Binop,Ternop)
import ConCat.Simplify
import ConCat.BuildDictionary

-- Information needed for reification. We construct this info in
-- CoreM and use it in the reify rule, which must be pure.
data CccEnv = CccEnv { dtrace    :: forall a. String -> SDoc -> a -> a
                     , cccV      :: Id
                     , idV       :: Id
                     , constV    :: Id
                     , forkV     :: Id
                     , applyV    :: Id
                     , composeV  :: Id
                     , curryV    :: Id
                     , uncurryV  :: Id
                     , exlV      :: Id
                     , exrV      :: Id
                     , constFunV :: Id
                     , ops       :: OpsMap
                     , hsc_env   :: HscEnv
                     }

-- Map from fully qualified name of standard operation.
type OpsMap = Map String (Var,[Type])

-- Whether to run Core Lint after every step
lintSteps :: Bool
lintSteps = True -- False

type Rewrite a = a -> Maybe a
type ReExpr = Rewrite CoreExpr

-- #define Trying(str) e | dtrace ("Trying " ++ (str)) (e `seq` empty) False -> undefined

#define Trying(str)

#define Doing(str) dtrace "Doing" (text (str)) id $

-- #define Doing(str)

-- Category
type Cat = Type

ccc :: CccEnv -> ModGuts -> DynFlags -> InScopeEnv -> Type -> ReExpr
ccc (CccEnv {..}) guts dflags inScope cat =
  traceRewrite "ccc" $
  (if lintSteps then lintReExpr else id) $
  go
 where
   go :: ReExpr
   -- go e | dtrace "go ccc:" (ppr e) False = undefined
   -- go (Var v) = pprTrace "go Var" (ppr v) $
   --              catFun v <|>
   --              (pprTrace "inlining" (ppr v) $
   --               mkCcc <$> inlineId v)
   -- go (etaReduceN -> transCatOp -> Just e') = Just e'
   go (Lam x body) = -- goLam x body
                     goLam x (etaReduceN body)
   go e = go (etaExpand 1 e)
          -- return $ mkCcc (etaExpand 1 e)
   -- TODO: If I don't etaReduceN, merge goLam back into the go Lam case.
   -- goLam x body | dtrace "go ccc:" (ppr (Lam x body)) False = undefined
   goLam x body = case body of
     -- Trying("constant") 
     Trying("Var")
     Var y | x == y            -> Doing("Var")
                                  return (mkId cat xty)
       --  | not (isFunTy bty) -> Doing ("Const") return (mkConst cat xty body)
     Trying("Category operation")
     _ | not (isFreeIn x body), Just e' <- transCatOp body ->
       Doing("Category operation")
       return (mkConstFun cat xty e')
     Trying("App")
     -- (\ x -> U V) --> apply . (\ x -> U) &&& (\ x -> V)
     u `App` v | not (isTyCoDictArg v) ->
       Doing("App")
       return $ mkCompose cat
                  (mkApply cat vty bty)
                  (mkFork cat (mkCcc (Lam x u)) (mkCcc (Lam x v)))
      where
        vty = exprType v
     Trying("unfold")
     -- Only unfold applications if no argument is a regular value
     e@(collectArgsPred isTyCoDictArg -> (Var v,_))
       | isNothing (catFun cat v)
       , Just e' <- unfoldMaybe e
       -> Doing("unfold")
          return (mkCcc (Lam x e'))
          -- goLam x e'
     Trying("Lam")
     Lam y e ->
       -- (\ x -> \ y -> U) --> curry (\ z -> U[fst z/x, snd z/y])
       Doing("Lam")
       return $ mkCurry cat (mkCcc (Lam z (subst sub e)))
      where
        yty = varType y
        z = freshId (exprFreeVars e) zName (pairTy xty yty)
        zName = uqVarName x ++ "_" ++ uqVarName y
        sub = [(x,mkEx funCat exlV (Var z)),(y,mkEx funCat exrV (Var z))]
        -- TODO: consider using fst & snd instead of exl and exr here
     Trying("Case of product")
     e@(Case scrut wild _rhsTy [(DataAlt dc, [a,b], rhs)])
         | isBoxedTupleTyCon (dataConTyCon dc) ->
       -- To start, require v to be unused. Later, extend.
       if not (isDeadBinder wild) then
            pprPanic "ccc: product case with live wild var (not yet handled)" (ppr e)
       else
          Doing("Case of product")
#if 0
          -- (\ x -> case scrut of _ { (a, b) -> rhs }) ==
          -- (\ x -> uncurry (\ a b -> rhs) scrut)
          return (mkCcc (Lam x (mkUncurry funCat (mkLams [a,b] rhs) `App` scrut)))
#else
          -- \ x -> case scrut of _ { (a, b) -> rhs }
          -- \ x -> (\ (a,b) -> rhs) scrut
          -- \ x -> (\ c -> rhs[a/exl c, b/exr c) scrut
          -- TODO: refactor with Lam case
          let c     = freshId (exprFreeVars e) cName (exprType scrut)  -- (pairTy (varTy a) (varTy b))
              cName = uqVarName a ++ "_" ++ uqVarName b
              sub   = [(a,mkEx funCat exlV (Var c)),(b,mkEx funCat exrV (Var c))]
          in
            return (mkCcc (Lam x (App (Lam c (subst sub rhs)) scrut)))
#endif
          -- goLam x (mkUncurry (mkLams [a,b] rhs) `App` scrut)
     -- Give up
     _e -> dtrace "ccc" ("Unhandled:" <+> ppr _e) $
           Nothing
    where
      xty = varType x
      bty = exprType body
   unfoldMaybe :: ReExpr
   unfoldMaybe = -- traceRewrite "unfoldMaybe" $
                 onExprHead ({-traceRewrite "inlineMaybe"-} inlineMaybe)
   inlineMaybe :: Id -> Maybe CoreExpr
   -- inlineMaybe v | dtrace "inlineMaybe" (ppr v) False = undefined
   inlineMaybe v = (inlineId <+ -- onInlineFail <+ traceRewrite "inlineClassOp"
                                inlineClassOp) v
   -- onInlineFail :: Id -> Maybe CoreExpr
   -- onInlineFail v =
   --   pprTrace "onInlineFail idDetails" (ppr v <+> colon <+> ppr (idDetails v))
   --   Nothing
   noDictErr :: SDoc -> Maybe a -> a
   noDictErr doc =
     fromMaybe (pprPanic "ccc - couldn't build dictionary for" doc)
   onDictMaybe :: CoreExpr -> Maybe CoreExpr
   onDictMaybe e | Just (ty,_) <- splitFunTy_maybe (exprType e)
                 , isPredTy ty =
                     App e <$> buildDictMaybe ty
                 | otherwise = pprPanic "ccc / onDictMaybe: not a function from pred"
                                 (pprWithType e)
   onDict :: Unop CoreExpr
   onDict f = noDictErr (pprWithType f) (onDictMaybe f)
   buildDictMaybe :: Type -> Maybe CoreExpr
   buildDictMaybe ty = simplifyE dflags False <$>
                       buildDictionary hsc_env dflags guts inScope ty
   -- buildDict :: Type -> CoreExpr
   -- buildDict ty = noDictErr (ppr ty) (buildDictMaybe ty)
   catOp' :: Cat -> Var -> [Type] -> CoreExpr
   catOp' k op tys = onDict (Var op `mkTyApps` (k : tys))
   catOp :: Cat -> Var -> CoreExpr
   catOp k op = catOp' k op []
   mkCcc :: Unop CoreExpr  -- Any reason to parametrize over Cat?
   mkCcc e = varApps cccV [cat,a,b] [e]
    where
      (a,b) = splitFunTy (exprType e)
   -- TODO: replace composeV with mkCompose in CccEnv
   -- Maybe other variables as well
   mkId :: Cat -> Type -> CoreExpr
   mkId k ty = onDict (catOp k idV `App` Type ty)
   mkCompose :: Cat -> Binop CoreExpr
   -- (.) :: forall b c a. (b -> c) -> (a -> b) -> a -> c
   mkCompose k g f
     | Just (b,c) <- splitCatTy_maybe (exprType g)
     , Just (a,_) <- splitCatTy_maybe (exprType f)
     = mkCoreApps (onDict (catOp k composeV `mkTyApps` [b,c,a])) [g,f]
     | otherwise = pprPanic "mkCompose:" (pprWithType g <+> text ";" <+> pprWithType f)
   mkEx :: Cat -> Var -> Unop CoreExpr
   mkEx k ex z =
     -- -- For the class methods (exl, exr):
     -- pprTrace "mkEx" (pprWithType z) $
     -- pprTrace "mkEx" (pprWithType (Var ex)) $
     -- pprTrace "mkEx" (pprWithType (catOp k ex)) $
     -- pprTrace "mkEx" (pprWithType (catOp k ex `mkTyApps` [a,b])) $
     -- pprTrace "mkEx" (pprWithType (onDict (catOp k ex `mkTyApps` [a,b]))) $
     -- pprTrace "mkEx" (pprWithType (onDict (catOp k ex `mkTyApps` [a,b]) `App` z)) $
     -- -- pprPanic "mkEx" (text "bailing")
     -- onDict (catOp k ex `mkTyApps` [a,b]) `App` z

     -- -- For the class method aliases (exl', exr'):
     -- pprTrace "mkEx" (pprWithType z) $
     -- pprTrace "mkEx" (pprWithType (Var ex)) $
     -- pprTrace "mkEx" (pprWithType (catOp' k ex [a,b])) $
     -- pprTrace "mkEx" (pprWithType (onDict (catOp' k ex [a,b]))) $
     -- pprTrace "mkEx" (pprWithType (onDict (catOp' k ex [a,b]) `App` z)) $
     -- -- pprPanic "mkEx" (text "bailing")
     onDict (catOp' k ex [a,b]) `App` z
    where
      -- TODO: Replace splitAppTys uses by splitCatTy. Pass in k to confirm.
      (_,[a,b])  = splitAppTys (exprType z)
   mkFork :: Cat -> Binop CoreExpr
   mkFork k f g =
     -- (&&&) :: forall {k :: * -> * -> *} {a} {c} {d}.
     --          (ProductCat k, Ok k d, Ok k c, Ok k a)
     --       => k a c -> k a d -> k a (Prod k c d)
     onDict (catOp k forkV `mkTyApps` [a,c,d]) `mkCoreApps` [f,g]
    where
      (_,[a,c]) = splitAppTys (exprType f)
      (_,[_,d]) = splitAppTys (exprType g)
   mkApply :: Cat -> Type -> Type -> CoreExpr
   mkApply k a b =
     -- apply :: forall {k :: * -> * -> *} {a} {b}. (ClosedCat k, Ok k b, Ok k a)
     --       => k (Prod k (Exp k a b) a) b
     onDict (catOp k applyV `mkTyApps` [a,b])
   mkCurry :: Cat -> Unop CoreExpr
   mkCurry k e =
     -- curry :: forall {k :: * -> * -> *} {a} {b} {c}.
     --          (ClosedCat k, Ok k c, Ok k b, Ok k a)
     --       => k (Prod k a b) c -> k a (Exp k b c)
     onDict (catOp k curryV `mkTyApps` [a,b,c]) `App` e
    where
      (splitAppTys -> (_,[splitAppTys -> (_,[a,b]),c])) = exprType e
   mkUncurry :: Cat -> Unop CoreExpr
   mkUncurry k e =
   -- uncurry :: forall {k :: * -> * -> *} {a} {b} {c}.
   --            (ClosedCat k, Ok k c, Ok k b, C1 (Ok k) a)
   --         => k a (Exp k b c) -> k (Prod k a b) c
     onDict (catOp k uncurryV `mkTyApps` [a,b,c]) `App` e
     -- varApps uncurryV [a,b,c] [e]
    where
      (splitCatTy -> (a, splitCatTy -> (b,c))) = exprType e
   mkConst :: Cat -> Type -> Unop CoreExpr
   mkConst k dom e =
     -- const :: forall (k :: * -> * -> *) b. ConstCat k b => forall dom.
     --          Ok k dom => b -> k dom (ConstObj k b)
     onDict (catOp' k constV [exprType e] `App` Type dom) `App` e
   mkConstFun :: Cat -> Type -> Unop CoreExpr
   mkConstFun k dom e =
     -- constFun :: forall k p a b. (ClosedCat k, Oks k '[p, a, b])
     --          => k a b -> k p (Exp k a b)
     onDict (catOp' k constFunV [dom,a,b]) `App` e
    where
      (a,b) = splitCatTy (exprType e)
   -- Split k a b into a & b.
   -- TODO: check that k == cat
   splitCatTy_maybe :: Type -> Maybe (Type,Type)
   splitCatTy_maybe (splitAppTys -> (_,(a:b:_))) = Just (a,b)
   splitCatTy_maybe _ = Nothing
   splitCatTy :: Type -> (Type,Type)
   splitCatTy (splitCatTy_maybe -> Just ab) = ab
   splitCatTy ty = pprPanic "splitCatTy" (ppr ty)
   traceRewrite :: (Outputable a, Outputable (f b)) =>
                   String -> Unop (a -> f b)
   traceRewrite str f a = pprTrans str a (f a)
   pprTrans :: (Outputable a, Outputable b) => String -> a -> b -> b
   pprTrans str a b = dtrace str (ppr a $$ "-->" $$ ppr b) b
   lintReExpr :: Unop ReExpr
   lintReExpr rew before =
     do after <- rew before
        let before' = mkCcc before
            oops str doc = pprPanic ("ccc post-transfo check. " ++ str)
                             (doc $$ ppr before' $$ "-->" $$ ppr after)
            beforeTy = exprType before'
            afterTy  = exprType after
        maybe (if beforeTy `eqType` afterTy then
                 return after
               else
                 oops "type change"
                  (ppr beforeTy <+> "vs" <+> ppr afterTy <+> "in"))
              (oops "Lint")
          (lintExpr dflags (varSetElems (exprFreeVars before)) before)
   catFun :: Cat -> Var -> Maybe CoreExpr
   catFun k v =
     -- pprTrace "catFun" (text fullName <+> dcolon <+> ppr ty) $
     do (op,tys) <- M.lookup fullName ops
        -- Apply to types and dictionaries, and possibly curry.
        return $ (if twoArgs ty then mkCurry k else id) (catOp' k op tys)
    where
      ty      = varType v
      fullName = fqVarName v
      twoArgs (splitCatTy_maybe -> Just (_,splitCatTy_maybe -> Just _)) = True
      twoArgs _ = False
   transCatOp :: CoreExpr -> Maybe CoreExpr
   -- transCatOp e | pprTrace "transCatOp" (ppr e) False = undefined
   transCatOp (collectArgs -> (Var v, Type _wasCat : rest))
     -- pprTrace "transCatOp (v,_wasCat,rest)" (ppr (v,_wasCat,rest)) True
     | Just arity <- M.lookup (fqVarName v) catOpArities
     -- , pprTrace "transCatOp arity" (ppr arity) True
     , length (filter (not . isTyCoDictArg) rest) == arity
     -- , pprTrace "transCatOp" (text "arity match") True
     = Just (foldl addArg (Var v `App` Type cat) rest)
    where
      addArg :: Binop CoreExpr
      addArg e arg | isTyCoArg arg = -- pprTrace "addArg isTyCoArg" (ppr arg)
                                     e `App` arg
                   | isPred    arg = -- pprTrace "addArg isPred" (ppr arg)
                                     onDict e
                   | otherwise     = -- pprTrace "addArg otherwise" (ppr arg)
                                     e `App` mkCcc arg
   transCatOp _ = -- pprTrace "transCatOp" (text "fail") $
                  Nothing

catOpArities :: Map String Int
catOpArities = M.fromList $ map (first ("ConCat.Category." ++)) $
  [ ("exl'",0), ("exr'",0) ]

-- collectArgsPred :: (CoreExpr -> Bool) -> CoreExpr -> (CoreExpr,[CoreExpr])

-- TODO: replace idV, composeV, etc with class objects from which I can extract
-- those variables. Better, module objects, since I sometimes want functions
-- that aren't methods.

-- TODO: consider a mkCoreApps variant that automatically inserts dictionaries.

pprWithType :: CoreExpr -> SDoc
pprWithType e = ppr e <+> dcolon <+> ppr (exprType e)

cccRule :: CccEnv -> ModGuts -> CoreRule
cccRule env guts =
  BuiltinRule { ru_name  = fsLit "ccc"
              , ru_fn    = varName (cccV env)
              , ru_nargs = 4  -- including type args
              , ru_try   = \ dflags inScope _fn [Type k, Type _a,Type _b,arg] ->
                               ccc env guts dflags inScope k arg
              }

plugin :: Plugin
plugin = defaultPlugin { installCoreToDos = install }

install :: [CommandLineOption] -> [CoreToDo] -> CoreM [CoreToDo]
install opts todos =
  do -- pprTrace ("CCC install " ++ show opts) empty (return ())
     dflags <- getDynFlags
     -- Unfortunately, the plugin doesn't work in GHCi. Until I can fix it,
     -- disable under GHCi, so we can at least type-check conveniently.
     if hscTarget dflags == HscInterpreted then
        return todos
      else
       do reinitializeGlobals
          env <- mkCccEnv opts
          -- Add the rule after existing ones, so that automatically generated
          -- specialized ccc rules are tried first.
          let addRule guts = pure (on_mg_rules (++ [cccRule env guts]) guts)
          return $   CoreDoPluginPass "Ccc insert rule" addRule
                   : CoreDoSimplify 2 mode
                   : todos
                   ++ [CoreDoPluginPass "Flag remaining ccc calls" (flagCcc env)]
 where
   flagCcc :: CccEnv -> PluginPass
   flagCcc (CccEnv {..}) guts
     -- | pprTrace "ccc residuals:" (ppr (toList remaining)) False = undefined
     -- | pprTrace "ccc final:" (ppr (mg_binds guts)) False = undefined
     | S.null remaining = return guts
     | otherwise = pprPanic "ccc residuals:" (ppr (toList remaining))
    where
      remaining :: Seq CoreExpr
      remaining = collect cccArgs (mg_binds guts)
      cccArgs :: CoreExpr -> Seq CoreExpr
      -- unVarApps :: CoreExpr -> Maybe (Id,[Type],[CoreExpr])
      -- ccc :: forall k a b. (a -> b) -> k a b
      cccArgs c@(unVarApps -> Just (v,_tys,[_])) | v == cccV = S.singleton c
      cccArgs _                                              = mempty
      -- cccArgs = const mempty  -- for now
      collect :: (Data a, Monoid m) => (a -> m) -> GenericQ m
      collect f = everything mappend (mkQ mempty f)
   -- Extra simplifier pass
   mode = SimplMode { sm_names      = ["Ccc simplifier pass"]
                    , sm_phase      = InitialPhase
                    , sm_rules      = True  -- important
                    , sm_inline     = False -- important
                    , sm_eta_expand = False -- ??
                    , sm_case_case  = True  -- important
                    }

mkCccEnv :: [CommandLineOption] -> CoreM CccEnv
mkCccEnv opts = do
  -- liftIO $ putStrLn ("Options: " ++ show opts)
  hsc_env <- getHscEnv
  let tracing = "trace" `elem` opts
      dtrace :: String -> SDoc -> a -> a
      dtrace str doc | tracing   = pprTrace str doc
                     | otherwise = id
      lookupRdr :: ModuleName -> (String -> OccName) -> (Name -> CoreM a) -> String -> CoreM a
      lookupRdr modu mkOcc mkThing str =
        maybe (panic err) mkThing =<<
          liftIO (lookupRdrNameInModuleForPlugins hsc_env modu (Unqual (mkOcc str)))
       where
         err = "reify installation: couldn't find "
               ++ str ++ " in " ++ moduleNameString modu
      lookupTh mkOcc mk modu = lookupRdr (mkModuleName modu) mkOcc mk
      findId      = lookupTh mkVarOcc  lookupId
      findTc      = lookupTh mkTcOcc   lookupTyCon
      findCatId   = findId "ConCat.Category"
      -- findMiscId  = findId "ConCat.Misc"
      -- findTupleId = findId "Data.Tuple"
      -- findRepTc   = findTc "ConCat.Rep"
      -- findBaseId  = findId "GHC.Base"
      -- findCatTc   = findTc "ConCat.Category"
  -- ruleBase <- getRuleBase
  -- catTc       <- findCatTc "Category"
  -- prodTc      <- findCatTc "ProductCat"
  -- closedTc    <- findCatTc "ClosedCat"
  -- constTc     <- findCatTc "ConstCat"
  -- okTc        <- findCatTc "Ok"
  -- dtrace "mkReifyEnv: getRuleBase ==" (ppr ruleBase) (return ())
  -- idV      <- findMiscId  "ident"
  idV         <- findCatId  "id"
  constV      <- findCatId  "const"
  -- constV      <- findMiscId  "konst"
  -- composeV <- findMiscId  "comp"
  composeV    <- findCatId  "."
--   exlV        <- findTupleId "fst"
--   exrV        <- findTupleId "snd"
--   forkV       <- findMiscId  "fork"
  exlV        <- findCatId "exl'"  -- Experiment: NOINLINE version
  exrV        <- findCatId "exr'"
  forkV       <- findCatId "&&&"
  applyV      <- findCatId "apply"
  curryV      <- findCatId "curry"
  uncurryV    <- findCatId "uncurry"
  constFunV   <- findCatId "constFun"
  -- notV <- findCatId "notC"
  cccV        <- findCatId  "ccc"
  let mkOp :: (String,(String,String,[Type])) -> CoreM (String,(Var,[Type]))
      mkOp (stdName,(cmod,cop,tyArgs)) =
        do cv <- findId cmod cop
           return (stdName, (cv,tyArgs))
  ops <- M.fromList <$> mapM mkOp opsInfo
  -- Experiment: force loading of numeric instances for Float and Double.
  -- Doesn't help.
  floatTc <- findTc "GHC.Float" "Float"
  liftIO (forceLoadNameModuleInterface hsc_env (text "mkCccEnv")
           (getName floatTc))
  -- fiddleV <- findMiscId "fiddle"
  -- rationalToFloatV <- findId "GHC.Float" "rationalToFloat"  -- experiment
  return (CccEnv { .. })

-- Association list 
opsInfo :: [(String,(String,String,[Type]))]
opsInfo = [ (hop,("ConCat.Category",cop,tyArgs))
          | (cop,ps) <- monoInfo
          , (hop,tyArgs) <- ps
          ]

monoInfo :: [(String, [([Char], [Type])])]
monoInfo = 
  [ ("notC",boolOp "not"), ("andC",boolOp "&&"), ("orC",boolOp "||")
  , ("equal", eqOp "==" <$> ifd) 
  , ("notEqual", eqOp "/=" <$> ifd) 
  , ("lessThan", compOps "lt" "<")
  , ("greaterThan", compOps "gt" ">")
  , ("lessThanOrEqual", compOps "le" "<=")
  , ("greaterThanOrEqual", compOps "ge" ">=")
  , ("negateC",numOps "negate"), ("addC",numOps "+")
  , ("subC",numOps "-"), ("mulC",numOps "*")
    -- powIC
  , ("recipC", fracOp "recip" <$> fd)
  , ("divideC", fracOp "/" <$> fd)
  , ("expC", floatingOp "exp" <$> fd)
  , ("cosC", floatingOp "cos" <$> fd)
  , ("sinC", floatingOp "sin" <$> fd)
  --
  , ("succC",[("GHC.Enum.$fEnumInt_$csucc",[intTy])])
  , ("predC",[("GHC.Enum.$fEnumInt_$cpred",[intTy])])
  ]
 where
   ifd = intTy : fd
   fd = [floatTy,doubleTy]
   boolOp op = [("GHC.Classes."++op,[])]
   -- eqOp ty = ("GHC.Classes.eq"++pp ty,[ty])
   eqOp op ty = ("GHC.Classes."++clsOp,[ty])
    where
      tyName = pp ty
      clsOp =
        case (op,ty) of
          ("==",_) -> "eq"++tyName
          ("/=",isIntTy -> True) -> "ne"++tyName
          _ -> "$fEq"++tyName++"_$c"++op
   compOps opI opFD = compOp <$> ifd
    where
      compOp ty = ("GHC.Classes."++clsOp,[ty])
       where
         clsOp | isIntTy ty = opI ++ tyName
               | otherwise  = "$fOrd" ++ tyName ++ "_$c" ++ opFD
         tyName = pp ty
   numOps op = numOp <$> ifd
    where
      numOp ty = ("GHC."++modu++".$fNum"++tyName++"_$c"++op,[ty])
       where
         tyName = pp ty
         modu | isIntTy ty = "Num"
              | otherwise = "Float"
   fdOp cls op ty = ("GHC.Float.$f"++cls++pp ty++"_$c"++op,[ty])
   fracOp = fdOp "Fractional"
   floatingOp = fdOp "Floating"

--    fracOp op ty = ("GHC.Float.$fFractional"++pp ty++"_$c"++op,[ty])
--    floatingOp op ty = ("GHC.Float.$fFloating"++pp ty++"_$c"++op,[ty])

-- (==): eqInt, eqFloat, eqDouble
-- (/=): neInt, $fEqFloat_$c/=, $fEqDouble_$c/=
-- (<):  ltI, $fOrdFloat_$c<

-- -- An orphan instance to help me debug
-- instance Show Type where show = pp

pp :: Outputable a => a -> String
pp = showPpr unsafeGlobalDynFlags


{--------------------------------------------------------------------
    Misc
--------------------------------------------------------------------}

on_mg_rules :: Unop [CoreRule] -> Unop ModGuts
on_mg_rules f mg = mg { mg_rules = f (mg_rules mg) }

fqVarName :: Var -> String
fqVarName = qualifiedName . varName

uqVarName :: Var -> String
uqVarName = getOccString . varName

varModuleName :: Var -> Maybe String
varModuleName = nameModuleName_maybe . varName

-- With dot
nameModuleName_maybe :: Name -> Maybe String
nameModuleName_maybe =
  fmap (moduleNameString . moduleName) . nameModule_maybe

-- Keep consistent with stripName in Exp.
uniqVarName :: Var -> String
uniqVarName v = uqVarName v ++ "_" ++ show (varUnique v)

-- Adapted from HERMIT.GHC
-- | Get the fully qualified name from a 'Name'.
qualifiedName :: Name -> String
qualifiedName nm =
  maybe "" (++ ".") (nameModuleName_maybe nm) ++ getOccString nm

-- | Substitute new subexpressions for variables in an expression
subst :: [(Id,CoreExpr)] -> Unop CoreExpr
subst ps = substExpr "subst" (foldr add emptySubst ps)
 where
   add (v,new) sub = extendIdSubst sub v new

subst1 :: Id -> CoreExpr -> Unop CoreExpr
subst1 v e = subst [(v,e)]

onHead :: Unop a -> Unop [a]
onHead f (c:cs) = f c : cs
onHead _ []     = []

collectTyArgs :: CoreExpr -> (CoreExpr,[Type])
collectTyArgs = go []
 where
   go tys (App e (Type ty)) = go (ty:tys) e
   go tys e                 = (e,tys)

collectTysDictsArgs :: CoreExpr -> (CoreExpr,[Type],[CoreExpr])
collectTysDictsArgs e = (h,tys,dicts)
 where
   (e',dicts) = collectArgsPred isPred e
   (h,tys)    = collectTyArgs e'

collectArgsPred :: (CoreExpr -> Bool) -> CoreExpr -> (CoreExpr,[CoreExpr])
collectArgsPred p = go []
 where
   go args (App fun arg) | p arg = go (arg:args) fun
   go args e                     = (e,args)

collectTyCoDictArgs :: CoreExpr -> (CoreExpr,[CoreExpr])
collectTyCoDictArgs = collectArgsPred isTyCoDictArg

isTyCoDictArg :: CoreExpr -> Bool
isTyCoDictArg e = isTyCoArg e || isPredTy (exprType e)

-- isConApp :: CoreExpr -> Bool
-- isConApp (collectArgs -> (Var (isDataConId_maybe -> Just _), _)) = True
-- isConApp _ = False

-- TODO: More efficient isConApp, discarding args early.

isPred :: CoreExpr -> Bool
isPred e  = not (isTyCoArg e) && isPredTy (exprType e)

stringExpr :: String -> CoreExpr
stringExpr = Lit . mkMachString

varNameExpr :: Id -> CoreExpr
varNameExpr = stringExpr . uniqVarName

pattern FunTy :: Type -> Type -> Type
pattern FunTy dom ran <- (splitFunTy_maybe -> Just (dom,ran))
 where FunTy = mkFunTy

-- TODO: Replace explicit uses of splitFunTy_maybe

-- TODO: Look for other useful pattern synonyms

pattern FunCo :: Role -> Coercion -> Coercion -> Coercion
pattern FunCo r dom ran <- TyConAppCo r (isFunTyCon -> True) [dom,ran]
 where FunCo = mkFunCo

onCaseRhs :: Type -> Unop (Unop CoreExpr)
onCaseRhs altsTy' f (Case scrut v _ alts) =
  Case scrut v altsTy' (onAltRhs f <$> alts)
onCaseRhs _ _ e = pprPanic "onCaseRhs. Not a case: " (ppr e)

onAltRhs :: Unop CoreExpr -> Unop CoreAlt
onAltRhs f (con,bs,rhs) = (con,bs,f rhs)

-- To help debug. Sometimes I'm unsure what constructor goes with what ppr.
coercionTag :: Coercion -> String
coercionTag Refl        {} = "Refl"
coercionTag TyConAppCo  {} = "TyConAppCo"
coercionTag AppCo       {} = "AppCo"
coercionTag ForAllCo    {} = "ForAllCo"
coercionTag CoVarCo     {} = "CoVarCo"
coercionTag AxiomInstCo {} = "AxiomInstCo"
coercionTag UnivCo      {} = "UnivCo"
coercionTag SymCo       {} = "SymCo"
coercionTag TransCo     {} = "TransCo"
coercionTag AxiomRuleCo {} = "AxiomRuleCo"
coercionTag NthCo       {} = "NthCo"
coercionTag LRCo        {} = "LRCo"
coercionTag InstCo      {} = "InstCo"
coercionTag CoherenceCo {} = "CoherenceCo"
coercionTag KindCo      {} = "KindCo"
coercionTag SubCo       {} = "SubCo"

-- TODO: Should I unfold (inline application head) earlier? Doing so might
-- result in much simpler generated code by avoiding many beta-redexes. If I
-- do, take care not to inline "primitives". I think it'd be fairly easy.

-- Try to inline an identifier.
-- TODO: Also class ops
inlineId :: Id -> Maybe CoreExpr
inlineId v = maybeUnfoldingTemplate (realIdUnfolding v)

-- Adapted from Andrew Farmer's getUnfoldingsT in HERMIT.Dictionary.Inline:
inlineClassOp :: Id -> Maybe CoreExpr
inlineClassOp v =
  case idDetails v of
    ClassOpId cls -> mkDictSelRhs cls <$> elemIndex v (classAllSelIds cls)
    _             -> Nothing

onExprHead :: (Id -> Maybe CoreExpr) -> ReExpr
onExprHead h = (fmap.fmap) simpleOptExpr $
               go id
 where
   go cont (Var v)       = cont <$> h v
   go cont (App fun arg) = go (cont . (`App` arg)) fun
   go cont (Cast e co)   = go (cont . (`Cast` co)) e
   go _ _                = Nothing

-- The simpleOptExpr here helps keep simplification going.

-- Identifier not occurring in a given variable set
freshId :: VarSet -> String -> Type -> Id
freshId used nm ty =
  uniqAway (mkInScopeSet used) $
  mkSysLocal (fsLit nm) (mkBuiltinUnique 17) ty

infixl 3 <+
(<+) :: Binop (a -> Maybe b)
(<+) = liftA2 (<|>)

apps :: CoreExpr -> [Type] -> [CoreExpr] -> CoreExpr
apps e tys es = mkApps e (map Type tys ++ es)

varApps :: Id -> [Type] -> [CoreExpr] -> CoreExpr
varApps = apps . Var

conApps :: DataCon -> [Type] -> [CoreExpr] -> CoreExpr
conApps = varApps . dataConWorkId

-- Split into Var head, type arguments, and other arguments (breaking at first
-- non-type).
unVarApps :: CoreExpr -> Maybe (Id,[Type],[CoreExpr])
unVarApps (collectArgs -> (Var v,allArgs)) = Just (v,tys,others)
 where
   (tys,others) = first (map unType) (span isTypeArg allArgs)
   unType (Type t) = t
   unType e        = pprPanic "unVarApps - unType" (ppr e)
unVarApps _ = Nothing

isFreeIn :: Var -> CoreExpr -> Bool
v `isFreeIn` e = v `elemVarSet` (exprFreeVars e)

-- exprFreeVars :: CoreExpr -> VarSet
-- elemVarSet      :: Var -> VarSet -> Bool

pairTy :: Binop Type
pairTy a b = mkBoxedTupleTy [a,b]

etaReduce1 :: Unop CoreExpr
etaReduce1 (Lam x (App e (Var y))) | x == y && not (isFreeIn x e) = e
etaReduce1 e = e

etaReduceN :: Unop CoreExpr
etaReduceN (Lam x (etaReduceN -> body')) = etaReduce1 (Lam x body')
etaReduceN e = e

-- etaReduce :: ReExpr
-- etaReduce (collectTyAndValBinders -> ( []
--                                      , vs@(_:_)
--                                      , collectArgs -> (f,args@(_:_))) )
--   | Just rest <- matchArgs vs args = 

-- The function category
funCat :: Cat
funCat = mkTyConTy funTyCon

