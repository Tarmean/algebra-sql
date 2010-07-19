module Ferry.TypedCore.Convert.CoreToAlgebra where

import Ferry.Front.Data.Base
import Ferry.Algebra.Data.Algebra
import Ferry.Algebra.Data.Create
import Ferry.Algebra.Data.GraphBuilder

import Ferry.TypedCore.Data.TypedCore

import qualified Data.Map as M 

coreToAlgebra :: CoreExpr -> GraphM AlgRes
coreToAlgebra (Constant t (CInt i)) = do 
                                        loop <- getLoop
                                        n1 <- insertNode loop
                                        n2 <- insertNode (attach "item1" intT (int i) n1)
                                        n2 <- insertNode (attach "pos" intT (int 1) n2)
                                        return (n2, [Col "item1"], EmptySub)
coreToAlgebra (BinOp t (Op o) e1 e2) = do
                                         (q1, [Col "item1"], m1) <- coreToAlgebra e1
                                         (q2, [Col "item1"], m2) <- coreToAlgebra e2
                                         n1 <- insertNode $ proj [("iter'", "iter"), ("item1'", "item1")] q2
                                         n2 <- insertNode $ eqJoin "iter" "iter'" q1 n1
                                         n3 <- insertNode $ oper o "res" "item1" "item1'" n2
                                         n4 <- insertNode $ proj [("iter", "iter"), ("pos", "pos"), ("item1", "res")] n3
                                         return (n4, [Col "item1"], EmptySub)

{-
data CoreExpr where
    BinOp :: (Qual FType) -> Op -> CoreExpr -> CoreExpr -> CoreExpr
    UnaOp :: (Qual FType) -> Op -> CoreExpr -> CoreExpr
    Constant :: (Qual FType) -> Const -> CoreExpr
    Var  :: (Qual FType) -> String -> CoreExpr
    App :: (Qual FType) -> CoreExpr -> Param -> CoreExpr
    Let :: (Qual FType) -> String -> CoreExpr -> CoreExpr -> CoreExpr
    Rec :: (Qual FType) -> [RecElem] -> CoreExpr
    Cons :: (Qual FType) -> CoreExpr -> CoreExpr -> CoreExpr
    Nil :: (Qual FType) -> CoreExpr
    Elem :: (Qual FType) -> CoreExpr -> String -> CoreExpr
    Table :: (Qual FType) -> String -> [Column] -> [Key] -> CoreExpr
    If :: (Qual FType) -> CoreExpr -> CoreExpr -> CoreExpr -> CoreExpr
-}