module Ferry.Compiler.Transform (typedCoreToAlgebra) where
    
import Ferry.Compiler.Pipeline (backEndPipeline)
import Ferry.TypedCore.Data.TypedCore (CoreExpr)
import Ferry.Compiler.Types
import Ferry.Compiler.Error.Error

typedCoreToAlgebra :: CoreExpr -> String
typedCoreToAlgebra = compile defaultConfig 

-- | The compiler pipeline
--   Note that there should be a monadic style for handling all the steps in the pipeline
compile :: Config -> CoreExpr -> String
compile opts inp = do
                        let (r, _, f) = runPhase opts $ backEndPipeline inp   
                        case (r, f) of
                            (Right (), [(_, o)]) -> o
                            (Left ProcessComplete, [(_, o)]) -> o
                            (Left r, _)         -> error $ show r