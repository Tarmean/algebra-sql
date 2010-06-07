{-# LANGUAGE TypeSynonymInstances #-}
module Ferry.TypedCore.Data.Instances where
    
import Ferry.TypedCore.Data.Base
import Ferry.TypedCore.Data.Type
import Ferry.TypedCore.Data.Substitution
import Ferry.TypedCore.Data.TypedCore

import qualified Data.Set as S
import qualified Data.Map as M

instance Substitutable FType where
  apply s (FList t)             = FList $ apply s t 
  apply s (FFn t1 t2)           = FFn (apply s t1) (apply s t2)
  apply s (FRec rs)             = FRec $ map (\(n, t) -> (n, apply s t)) rs
  apply s v@(FVar i) = case M.notMember v s of
                            True -> v
                            False -> s M.! v
  apply s v@(FGen i) = case M.notMember v s of
                            True -> v
                            False -> s M.! v
  apply _    t                  = t -- If the substitution is not applied to a container type or variable just stop primitives cannot be substituted

instance Substitutable t => Substitutable (Qual t) where
  apply s (preds:=> t) = (map (apply s) preds) :=> apply s t
  
instance Substitutable Pred where
  apply s (IsIn c t) = IsIn c $ apply s t
  apply s (Has r n t) = Has (apply s r) n (apply s t)  
                          
instance Substitutable TyScheme where
  apply s (Forall i t) = Forall i $ apply s t
    
instance Substitutable TyEnv where
  apply s m = M.map (apply s) m
  
instance Substitutable CoreExpr where
  apply s (BinOp t o c1 c2) = BinOp (apply s t) o (apply s c1) (apply s c2)
  apply s (UnaOp t o c)      = UnaOp (apply s t) o (apply s c)
  apply s (Constant t c)    = Constant (apply s t) c
  apply s (Var t x)         = Var (apply s t) x
  apply s (App t c a)       = App (apply s t) (apply s c) (apply s a)
  apply s (Let t x c1 c2)   = Let (apply s t) x (apply s c1) (apply s c2)
  apply s (Rec t es)        = Rec (apply s t) $ map (apply s) es
  apply s (Cons t c1 c2)    = Cons (apply s t) (apply s c1) (apply s c2)
  apply s (Nil t)           = Nil (apply s t)
  apply s (Elem t c f)      = Elem (apply s t) (apply s c) f
  apply s (Table t n c k)   = Table (apply s t) n c k
  apply s (If t c1 c2 c3)   = If (apply s t) (apply s c1) (apply s c2) (apply s c3)

instance Substitutable Param where
    apply s (ParExpr t c) = ParExpr (apply s t) (apply s c)
    apply s (ParAbstr t pa c) = ParAbstr (apply s t) pa (apply s c)
        
instance Substitutable RecElem where
    apply s (RecElem t x c) = RecElem (apply s t) x (apply s c)

{- | Instances of VarContainer class-}
  
instance VarContainer FType where
  ftv (FVar a)    = S.singleton a
  ftv (FList t)   = ftv t
  ftv (FRec s)    = S.unions $ map (ftv . snd) s
  ftv (FFn t1 t2) = ftv t1 `S.union` ftv t2
  ftv _           = S.empty

instance VarContainer TyScheme where
  ftv (Forall i t)  = ftv t 

instance VarContainer t => VarContainer (Qual t) where
  ftv (preds :=> t) = S.unions $ (ftv t):(map ftv preds)

instance VarContainer Pred where
  ftv (IsIn c t) = ftv t
  ftv (Has t _ t2) = ftv t `S.union` ftv t2

instance VarContainer TyEnv where
  ftv m = S.unions $ M.elems $ M.map ftv m
  
instance HasType CoreExpr where
  typeOf (BinOp t o c1 c2) = t
  typeOf (UnaOp t o c)     = t
  typeOf (Constant t c)    = t
  typeOf (Var t x)         = t
  typeOf (App t c a)       = t
  typeOf (Let t x c1 c2)   = t
  typeOf (Rec t es)        = t
  typeOf (Cons t c1 c2)    = t
  typeOf (Nil t)           = t
  typeOf (Elem t c f)      = t
  typeOf (Table t n c k)   = t
  typeOf (If t c1 c2 c3)   = t
  
instance HasType Param where
    typeOf (ParExpr t e) = t
    typeOf (ParAbstr t p e) = t