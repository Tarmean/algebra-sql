module Ferry.Core.Render.Dot where


import Ferry.Common.Render.Dot    
import Ferry.Core.Data.Core
import Ferry.Front.Data.Base
import Ferry.Core.Render.Pretty

import qualified Data.List as L



-- type Dot = ErrorT FerryError (WriterT [Node] (WriterT [Edge] (State Int)))

toDot :: CoreExpr -> Dot Id
toDot (BinOp o e1 e2) = do
                          nId <- getFreshId
                          id1 <- toDot e1
                          id2 <- toDot e2
                          let o' = (\(Op o) -> o) o
                          addNode $ Node nId [Label $ SLabel o', Color Green, Shape Circle]
                          addEdge $ Edge nId [id1, id2]
                          return nId
toDot (UnaOp o e) = do
                      nId <- getFreshId
                      eId <- toDot e
                      let o' = (\(Op o) -> o) o
                      addNode $ Node nId [Label $ SLabel o', Color Green, Shape Circle]
                      addEdge $ Edge nId [eId]
                      return nId
toDot (Constant c) = do
                      nId <- getFreshId
                      let s = toString c
                      addNode $ Node nId [Label $ SLabel s, Color Yellow, Shape Triangle]
                      return nId
toDot (Var i) = do
                    nId <- getFreshId
                    addNode $ Node nId [Label $ SLabel i, Color Red, Shape Triangle]
                    return nId
toDot (App c ps) = do
                     nId <- getFreshId
                     fId <- toDot c
                     pIds <- paramToDot ps
                     addNode $ Node nId [Label $ SLabel "$", Color Green, Shape Circle]
                     addEdge $ Edge nId [fId, pIds]
                     return nId
toDot (Let s e1 e2) = do
                       nId <- getFreshId
                       id0 <- getFreshId
                       id1 <- toDot e1
                       id2 <- toDot e2
                       addNode $ Node nId [Label $ SLabel s, Color Black, Shape Rect, TextColor Black]
                       addNode $ Node nId [Label $ SLabel "Let", Color Blue, Shape Rect]
                       addEdge $ Edge nId [id0, id1, id2]
                       return nId
toDot (Rec es) = do
                  nId <- getFreshId
                  eIds <- mapM recToDot es
                  addNode $ Node nId [Label $ SLabel "Rec", Color Blue, Shape Oval]
                  addEdge $ Edge nId eIds
                  return nId
toDot (Cons e1 e2) = do
                     nId <- getFreshId
                     eIdh <- toDot e1
                     eIdt <- toDot e2
                     addNode $ Node nId [Label $ SLabel "Cons", Color Blue, Shape Oval]
                     addEdge $ Edge nId [eIdh, eIdt]
                     return nId
toDot (Nil)      = do
                    nId <- getFreshId
                    addNode $ Node nId [Label $ SLabel "Nil", Color Blue, Shape Oval]
                    return nId
toDot (Elem c s) = do
                    nId <- getFreshId
                    sId <- getFreshId
                    addNode $ Node nId [Label $ SLabel ".", Color Green, Shape Circle]
                    addNode $ Node sId [Label $ SLabel s, Color Red, Shape Triangle]
                    cId <- toDot c
                    addEdge $ Edge nId [cId, sId]
                    return nId
toDot (Table n cs ks) = do
                         nId <- getFreshId
                         let label = VLabel $ ((HLabel [SLabel "Table:", SLabel n])
                                            : [HLabel [SLabel $ n ++ "::", SLabel $ prettyTy t ] | (Column n t) <- cs])
                                            ++ [SLabel  $ show k | Key k <- ks]
                         addNode $ Node nId [Label label, Color Yellow, Shape Rect]
                         return nId
toDot (If e1 e2 e3) = do
                        nId <- getFreshId
                        eId1 <- toDot e1
                        eId2 <- toDot e2
                        eId3 <- toDot e3
                        addNode $ Node nId [Label $ SLabel "If", Color Blue, Shape Circle]
                        addEdge $ Edge nId [eId1, eId2, eId2]
                        return nId
                        

paramToDot :: Param -> Dot Id
paramToDot (ParExpr e) = toDot e
paramToDot (ParAbstr p e) = do
                             nId <- getFreshId
                             pId <- patToDot p
                             eId <- toDot e
                             addNode $ Node nId [Label $ SLabel "\\   ->", Color Blue, Shape Circle]
                             addEdge $ Edge nId [pId, eId]
                             return nId
                             
patToDot :: Pattern -> Dot Id
patToDot (PVar s) = do
                     nId <- getFreshId
                     addNode $ Node nId [Label $ SLabel s, Color Red, Shape Triangle]
                     return nId
patToDot (Pattern s) = do
                        nId <- getFreshId
                        addNode $ Node nId [Label $ SLabel $  "(" ++ (concat $ L.intersperse ", " s) ++ ")", Color Red, Shape Triangle]
                        return nId
                        
recToDot (RecElem s e) = do
                          nId <- getFreshId
                          eId <- toDot e
                          addNode $ Node nId [Label $ SLabel s, Color Red, Shape Oval]
                          addEdge $ Edge nId [eId]
                          return nId