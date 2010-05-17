module Ferry.Compiler.Error.Error where

import Control.Monad.Error
import Text.ParserCombinators.Parsec (ParseError(..))

data FerryError = NoSuchFile String
                | ParserError ParseError
                | ProcessComplete
        deriving Show
                
 
instance Error FerryError where
    noMsg = error "This function should not be used Error.hs noMsg"
    strMsg = error "This function should not be used Error.hs strMsg"
    

     