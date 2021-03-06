{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- This file determines the semantics of the 'Query' data structure and all of
-- its sub structures.
module Database.Algebra.SQL.Render.Query
    ( renderQuery
    , renderSelectStmt
    ) where

import           Data.Scientific
import qualified Data.Text                          as T
import qualified Data.Time.Calendar                 as C
import           Text.PrettyPrint.ANSI.Leijen       (Doc, align, bold, char,
                                                     comma, double, empty,
                                                     fillSep, hang, hsep,
                                                     indent, int, integer,
                                                     linebreak, lparen,
                                                     ondullblue, parens,
                                                     punctuate, red, rparen,
                                                     sep, squotes, text, vcat,
                                                     (<$>), (<+>), (</>), (<>))

import           Database.Algebra.SQL.Dialect
import           Database.Algebra.SQL.Query
import           Prelude                            hiding ((<$>))

enlist :: [Doc] -> Doc
enlist = fillSep . punctuate comma

-- Does the same as enlist but does not break the line.
enlistOnLine :: [Doc] -> Doc
enlistOnLine = hsep . punctuate comma

-- | A keyword.
kw :: String -> Doc
kw = red . text

-- | A single character keyword.
op :: Char -> Doc
op = red . char

-- | Terminate a SQL query.
terminate :: Doc -> Doc
terminate = (<> op ';')

renderQuery :: Dialect -> Query -> Doc
renderQuery c query = terminate $ case query of
    QValueQuery q      -> renderValueQuery c q
    QDefinitionQuery q -> renderDefinitionQuery c q

renderDefinitionQuery :: Dialect -> DefinitionQuery -> Doc
renderDefinitionQuery compat (DQMatView query name)        =
    kw "CREATE MATERIALIZED VIEW"
    <+> text name
    <+> kw "AS"
    </> renderValueQuery compat query

renderDefinitionQuery compat (DQTemporaryTable query name) =
    createStmt
    <+>
    case compat of
        PostgreSQL ->
            -- PostgreSQL does not accept the default syntax. In order to
            -- achieve the same behaviour, the SQL code is rendered differently.
            kw "ON COMMIT DROP"
            <+> as
            <$> indentedQuery

        -- Default implementation for SQL:1999 compliant DBMS.
        _          ->
            as
            <$> indentedQuery
            -- Create the table with the result of the given value query.
            <$> kw "WITH DATA ON COMMIT DROP"
  where
    createStmt    = kw "CREATE LOCAL TEMPORARY TABLE" <+> text name
    as            = kw "AS"
    indentedQuery = indent 4 $ renderValueQuery compat query

renderValueQuery :: Dialect -> ValueQuery -> Doc
renderValueQuery compat (VQSelect stmt)    = renderSelectStmt compat stmt
renderValueQuery compat (VQLiteral vals)   =
    kw "VALUES" <+> align (sep . punctuate comma $ map renderRow vals)
  where renderRow row = parens . enlistOnLine $ map (renderColumnExpr compat) row

renderValueQuery compat (VQWith bindings body)                 =
    hang 4 (kw "WITH" </> enlist (map renderBinding bindings))
    <$> renderValueQuery compat body
  where renderBinding :: (String, Maybe [String], ValueQuery) -> Doc
        renderBinding (name, optCols, query) =
            text name
            <> renderOptColDefs optCols
            <+> kw "AS"
            <+> lparen
            <$> indent 4 (renderValueQuery compat query)
            <$> rparen

renderValueQuery compat (VQBinarySetOperation left right o)    =
    renderValueQuery compat left
    <> linebreak
    <$> renderSetOperation o
    <> linebreak
    <$> renderValueQuery compat right

renderSetOperation :: SetOperation -> Doc
renderSetOperation SOUnionAll  = kw "UNION ALL"
renderSetOperation SOExceptAll = kw "EXCEPT ALL"

-- | Render a conjunction list, renders the neutral element, when given the
-- empty list.
renderAndList :: Dialect -> [ColumnExpr] -> Doc
renderAndList compat l = case l of
    [] -> kw "TRUE"
    _  -> align $ hsep $ punctuate (linebreak <> kw "AND")
                         $ map (renderColumnExpr compat) l

renderSelectStmt :: Dialect -> SelectStmt -> Doc
renderSelectStmt compat stmt =
    kw "SELECT"
    <+> align ( let sC = enlist $ map (renderSelectColumn compat) $ selectClause stmt
                in if distinct stmt
                   then kw "DISTINCT" <+> sC
                   else sC
              )

    <> case fromClause stmt of
           []        -> empty
           fromParts ->
               linebreak
               <> kw "FROM"
               <+> align ( vcat . punctuate comma
                                $ map (renderFromPart compat) fromParts
                         )
    <> case whereClause stmt of
           []             -> empty
           l              -> linebreak
                             <> kw "WHERE"
                             <+> renderAndList compat l
    <> case groupByClause stmt of
           []      -> empty
           valExpr -> linebreak
                      <> kw "GROUP BY"
                      <+> align (enlist $ map (renderColumnExpr compat) valExpr)
    <> case orderByClause stmt of
           []    -> empty
           order -> linebreak
                    <> kw "ORDER BY"
                    <+> align ( renderGenericOrderByList renderOrderExpr
                                                         compat
                                                         order
                              )


renderOrderExpr :: Dialect -> OrderExpr -> Doc
renderOrderExpr compat (OE ee dir) =
    renderExtendedExpr compat ee
    <+> renderSortDirection dir

renderWindowOrderExpr :: Dialect -> WindowOrderExpr -> Doc
renderWindowOrderExpr compat (WOE ae dir) =
    renderAggrExpr compat ae
    <+> renderSortDirection dir

-- | Render a list of generic order expressions.
renderGenericOrderByList :: (Dialect -> o -> Doc) -> Dialect -> [o] -> Doc
renderGenericOrderByList renderGenericOrderExpr compat =
    enlistOnLine . map (renderGenericOrderExpr compat)

renderWindowOrderByList :: Dialect -> [WindowOrderExpr] -> Doc
renderWindowOrderByList compat wos =
    kw "ORDER BY" <+> renderGenericOrderByList renderWindowOrderExpr compat wos

renderFrameSpec :: FrameSpec -> Doc
renderFrameSpec (FHalfOpen fs)  = kw "ROWS" <+> renderFrameStart fs
renderFrameSpec (FClosed fs fe) = kw "ROWS BETWEEN"
                                  <+> renderFrameStart fs
                                  <+> kw "AND"
                                  <+> renderFrameEnd fe

renderFrameStart :: FrameStart -> Doc
renderFrameStart FSUnboundPrec = text "UNBOUNDED PRECEDING"
renderFrameStart (FSValPrec i) = int i <+> text "PRECEDING"
renderFrameStart FSCurrRow     = text "CURRENT ROW"

renderFrameEnd :: FrameEnd -> Doc
renderFrameEnd FEUnboundFol = text "UNBOUNDED FOLLOWING"
renderFrameEnd (FEValFol i) = int i <+> text "FOLLOWING"
renderFrameEnd FECurrRow    = text "CURRENT ROW"

renderSortDirection :: SortDirection -> Doc
renderSortDirection Ascending  = kw "ASC"
renderSortDirection Descending = kw "DESC"

-- | Render a list of columns as definition within a from clause or within
-- a common table expression.
renderOptColDefs :: Maybe [String] -> Doc
renderOptColDefs = maybe empty colDoc
  where colDoc = parens . enlistOnLine . map text

renderFromPart :: Dialect -> FromPart -> Doc
renderFromPart _ (FPAlias (FETableReference n) alias _) =
    -- Don't use positional mapping on table references, since they are mapped
    -- by their name.
    text n
    <+> kw "AS"
    <+> text alias

renderFromPart compat (FPAlias expr alias optCols)      =
    renderFromExpr compat expr
    <+> kw "AS"
    <+> text alias
    <> renderOptColDefs optCols

renderSubQuery :: Dialect -> ValueQuery -> Doc
renderSubQuery compat q = lparen <+> align (renderValueQuery compat q) <$> rparen

renderFromExpr :: Dialect -> FromExpr -> Doc
renderFromExpr compat (FESubQuery q)           = renderSubQuery compat q
renderFromExpr _      (FEVariable v)           = ondullblue $ int v
renderFromExpr _      (FETableReference n)     = text n
renderFromExpr compat (FEExplicitJoin jop l r) = renderJoinOp compat jop l r

renderJoinOp :: Dialect -> JoinOperator -> FromPart -> FromPart -> Doc
renderJoinOp MonetDB (LeftOuterJoin e) l r = parens $
    kw "SELECT" <$> kw "*" <$> kw "FROM" <$> parens
        (renderFromPart MonetDB l
    <$> kw "LEFT OUTER JOIN"
    <$> renderFromPart MonetDB r
    <$> kw "ON" <+> renderColumnExpr MonetDB e)
renderJoinOp compat (LeftOuterJoin e) l r = parens $
        renderFromPart compat l
    <$> kw "LEFT OUTER JOIN"
    <$> renderFromPart compat r
    <$> kw "ON" <+> renderColumnExpr compat e

-- | Renders an optional prefix.
renderOptPrefix :: Maybe String -> Doc
renderOptPrefix = maybe empty $ (<> char '.') . text


renderSelectColumn :: Dialect -> SelectColumn -> Doc
renderSelectColumn compat (SCAlias e@(EEBase (VEColumn n1 _)) n2)
    | n1 == n2 = renderExtendedExpr compat e
    | n1 /= n2 = renderExtendedExpr compat e <+> kw "AS" <+> text n2
renderSelectColumn compat (SCAlias expr name)
    = renderExtendedExpr compat expr <+> kw "AS" <+> text name
renderSelectColumn compat (SCExpr expr)
    = renderExtendedExpr compat expr


renderExtendedExpr :: Dialect -> ExtendedExpr -> Doc
renderExtendedExpr compat (EEBase v)                  = renderExtendedExprBase compat v
renderExtendedExpr compat (EEWinFun wfun partExprs order mFrameSpec) =
    renderWindowFunction compat wfun
    <+> kw "OVER"
    <+> parens (partitionByDoc <> orderByDoc <> frameSpecDoc)

  where
    partitionByDoc = case partExprs of
                         [] -> empty
                         _  -> kw "PARTITION BY"
                               </> enlist (map (renderAggrExpr compat) partExprs)
                               <> linebreak

    orderByDoc = case order of
                     [] -> empty
                     _  -> renderWindowOrderByList compat order <> linebreak

    frameSpecDoc = maybe empty (\fs -> renderFrameSpec fs) mFrameSpec

renderExtendedExpr compat (EEAggrExpr ae)             =
    renderAggrExpr compat ae

renderAggrExpr :: Dialect -> AggrExpr -> Doc
renderAggrExpr compat e = case e of
    AEBase ve              ->
        renderValueExprTemplate renderAggrExpr compat ve

    AEAggregate aggr ->
        renderAggregateFunction compat aggr

-- | Generic 'ValueExprTemplate' renderer.
renderValueExprTemplate :: (Dialect -> a -> Doc)
                        -> Dialect
                        -> ValueExprTemplate a
                        -> Doc
renderValueExprTemplate renderRec compat ve = case ve of
    VEValue v            -> renderValue compat v
    VEColumn n optPrefix -> renderOptPrefix optPrefix
                            <> text n
    VEBinApp BFCoalesce a b -> kw "COALESCE"
                               <> parens (renderRec compat a
                                          <> comma
                                          <+> renderRec compat b)
    VEBinApp f a b       -> parens $ renderRec compat a
                            <+> renderBinaryFunction f
                            <+> renderRec compat b

    VEUnApp f a          ->
        parens $ renderUnaryFunction renderRec compat f a

    VEExists q           -> kw "EXISTS" <+> renderSubQuery compat q

    VEIn v q             -> parens $ renderRec compat v
                            <+> kw "IN"
                            <+> renderSubQuery compat q
    VECase c t e         ->
        kw "CASE WHEN" <+> renderRec compat c
                         <+> kw "THEN"
                         <+> renderRec compat t
                         <+> kw "ELSE"
                         <+> renderRec compat e
                         <+> kw "END"
    VEBetween e1 e2 e3   ->
        parens (renderRec compat e1) <+> kw "BETWEEN"
                                     <+> parens (renderRec compat e2)
                                     <+> kw "AND"
                                     <+> parens (renderRec compat e3)


-- | Render a 'ExtendedExprBase' with the generic renderer.
renderExtendedExprBase :: Dialect -> ExtendedExprBase -> Doc
renderExtendedExprBase = renderValueExprTemplate renderExtendedExpr


-- | Render a 'ColumnExprBase' with the generic renderer.
renderColumnExprBase :: Dialect -> ColumnExprBase -> Doc
renderColumnExprBase = renderValueExprTemplate renderColumnExpr

renderAggregateFunction :: Dialect -> AggregateFunction -> Doc
renderAggregateFunction c          (AFAvg e)           = renderFunCall "AVG" (renderColumnExpr c e)
renderAggregateFunction c          (AFMax e)           = renderFunCall "MAX" (renderColumnExpr c e)
renderAggregateFunction c          (AFMin e)           = renderFunCall "MIN" (renderColumnExpr c e)
renderAggregateFunction c          (AFSum e)           = renderFunCall "SUM" (renderColumnExpr c e)
renderAggregateFunction c          (AFCount e)         = renderFunCall "COUNT" (renderColumnExpr c e)
renderAggregateFunction c          (AFCountDistinct e) = kw "COUNT" <> parens (kw "DISTINCT" <+> renderColumnExpr c e)
renderAggregateFunction _          AFCountStar         = renderFunCall "COUNT" (kw "*")
renderAggregateFunction PostgreSQL (AFAll e)           = renderFunCall "BOOL_AND" (renderColumnExpr PostgreSQL e)
renderAggregateFunction SQL99      (AFAll e)           = renderFunCall "EVERY" (renderColumnExpr SQL99 e)
renderAggregateFunction MonetDB    (AFAll e)           = renderFunCall "MIN" (renderColumnExpr MonetDB e)
renderAggregateFunction PostgreSQL (AFAny e)           = renderFunCall "BOOL_OR" (renderColumnExpr PostgreSQL e)
renderAggregateFunction SQL99      (AFAny e)           = renderFunCall "SOME" (renderColumnExpr SQL99 e)
renderAggregateFunction MonetDB    (AFAny e)           = renderFunCall "MAX" (renderColumnExpr MonetDB e)

renderFunCall :: String -> Doc -> Doc
renderFunCall funName funArg = kw funName <> parens funArg

renderWindowFunction :: Dialect -> WindowFunction -> Doc
renderWindowFunction _          WFRowNumber      = renderFunCall "ROW_NUMBER" empty
renderWindowFunction _          WFDenseRank      = renderFunCall "DENSE_RANK" empty
renderWindowFunction _          WFRank           = renderFunCall "RANK" empty
renderWindowFunction MonetDB    _                = error "MonetDB does not support window aggregates"
renderWindowFunction c          (WFAvg a)        = renderFunCall "AVG" (renderColumnExpr c a)
renderWindowFunction c          (WFMax a)        = renderFunCall "MAX" (renderColumnExpr c a)
renderWindowFunction c          (WFMin a)        = renderFunCall "MIN" (renderColumnExpr c a)
renderWindowFunction c          (WFSum a)        = renderFunCall "SUM" (renderColumnExpr c a)
renderWindowFunction c          (WFFirstValue a) = renderFunCall "first_value" (renderColumnExpr c a)
renderWindowFunction c          (WFLastValue a)  = renderFunCall "last_value" (renderColumnExpr c a)
renderWindowFunction _          WFCount          = renderFunCall "COUNT" (text "*")
renderWindowFunction PostgreSQL (WFAll a)        = renderFunCall "bool_and"
                                                                 (renderColumnExpr PostgreSQL a)
renderWindowFunction SQL99      (WFAll a)        = renderFunCall "EVERY"
                                                                 (renderColumnExpr SQL99 a)
renderWindowFunction PostgreSQL (WFAny a)        = renderFunCall "bool_or"
                                                                 (renderColumnExpr PostgreSQL a)
renderWindowFunction SQL99      (WFAny a)        = renderFunCall "SOME"
                                                                 (renderColumnExpr SQL99 a)

renderColumnExpr :: Dialect -> ColumnExpr -> Doc
renderColumnExpr compat (CEBase e) = renderColumnExprBase compat e


renderBinaryFunction :: BinaryFunction -> Doc
renderBinaryFunction BFPlus         = op '+'
renderBinaryFunction BFMinus        = op '-'
renderBinaryFunction BFTimes        = op '*'
renderBinaryFunction BFDiv          = op '/'
renderBinaryFunction BFModulo       = op '%'
renderBinaryFunction BFContains     = op '~'
renderBinaryFunction BFSimilarTo    = kw "SIMILAR TO"
renderBinaryFunction BFLike         = kw "LIKE"
renderBinaryFunction BFConcat       = kw "||"
renderBinaryFunction BFGreaterThan  = op '>'
renderBinaryFunction BFGreaterEqual = kw ">="
renderBinaryFunction BFLowerThan    = op '<'
renderBinaryFunction BFLowerEqual   = kw "<="
renderBinaryFunction BFEqual        = op '='
renderBinaryFunction BFNotEqual     = kw "<>"
renderBinaryFunction BFAnd          = kw "AND"
renderBinaryFunction BFOr           = kw "OR"
renderBinaryFunction BFCoalesce     = kw "COALESCE"

renderRegularUnary :: String -> Doc -> Doc
renderRegularUnary f a = kw f <> parens a

renderSubString :: Dialect -> Integer -> Integer -> Doc -> Doc
renderSubString compat from to ra =
    case compat of
        SQL99      -> kw "substring" <> parens (ra
                                                <+> text "from" <+> integer from
                                                <+> text "for" <+> integer to)
        PostgreSQL -> kw "substr" <> parens (hsep $ punctuate comma [ ra
                                                                    , integer from
                                                                    , integer to
                                                                    ])
        MonetDB    -> kw "substring" <> parens (hsep $ punctuate comma [ ra
                                                                       , integer from
                                                                       , integer to
                                                                       ])

-- | Render a type cast on an expression
renderCast :: Doc -> Doc -> Doc
renderCast expr ty = kw "CAST" <> parens (expr <+> kw "AS" <+> ty)

renderUnaryFunction :: (Dialect -> a -> Doc)
                    -> Dialect
                    -> UnaryFunction
                    -> a
                    -> Doc
renderUnaryFunction renderRec compat fun argExpr =
    case fun of
        UFSin             -> renderRegularUnary "sin" ra
        UFCos             -> renderRegularUnary "cos" ra
        UFTan             -> renderRegularUnary "tan" ra
        UFLog             -> renderRegularUnary "log" ra
        UFLn              -> renderRegularUnary "ln" ra
        UFSqrt            -> renderRegularUnary "sqrt" ra
        UFExp             -> renderRegularUnary "exp" ra
        UFASin            -> renderRegularUnary "asin" ra
        UFACos            -> renderRegularUnary "acos" ra
        UFATan            -> renderRegularUnary "atan" ra
        (UFExtract field) ->
            kw "EXTRACT" <> parens (renderExtractField field <+> kw "FROM" <+> ra)
        -- The substring combinator is rendered special
        UFSubString f t   -> renderSubString compat f t ra
        UFCast ty         -> renderCast ra (renderDataType ty)
        UFNot             -> parens $ kw "NOT" <+> ra
        UFIsNull          -> parens ra <+> kw "IS NULL"

  where
    ra = renderRec compat argExpr


renderExtractField :: ExtractField -> Doc
renderExtractField ExtractDay   = kw "day"
renderExtractField ExtractMonth = kw "month"
renderExtractField ExtractYear  = kw "year"

renderDataType :: DataType -> Doc
renderDataType DTInteger            = kw "INTEGER"
renderDataType DTDecimal            = kw "DECIMAL"
renderDataType (DTDecimalFixed p s) = kw "DECIMAL" <> parens (int p <> comma <> int s)
renderDataType DTDoublePrecision    = kw "DOUBLE PRECISION"
renderDataType DTText               = kw "TEXT"
renderDataType DTBoolean            = kw "BOOLEAN"
renderDataType DTDate               = kw "DATE"

literal :: Doc -> Doc
literal = bold

-- | Escape a string literal.
-- FIXME no idea if the PostgreSQL mode works for other systems.
escape :: Dialect -> T.Text -> T.Text
escape _ t = escapePostgreSQL t

-- | With PostgreSQL, single quotes can be escaped by doubling them.
escapePostgreSQL :: T.Text -> T.Text
escapePostgreSQL t = T.concatMap f t
  where
    -- Filter out null ('\0') characters
    f '\0' = T.empty
    f '\'' = "''"
    f c    = T.singleton c

renderValue :: Dialect -> Value -> Doc
renderValue c v = case v of
    VInteger i         -> literal $ integer i
    VDecimal d         -> renderCast (literal rendered) sqlType
      where
        rendered        = text $ formatScientific Fixed Nothing d
        (digits, exp10) = toDecimalDigits d
        len             = length digits
        precision       = negPrecision exp10 len digits $ computePrecision len exp10
        scale           = computeScale len exp10
        sqlType         = renderDataType $ DTDecimalFixed precision scale
    VDoublePrecision d -> literal $ double d
    VText str          -> literal $ squotes $ text $ T.unpack $ escape c str
    VBoolean b         -> kw $ if b then "TRUE" else "FALSE"
    VNull              -> literal $ text "NULL"
    VDate d            -> literal $ text "DATE"
                                         <+>
                                         (squotes $ text $ C.showGregorian d)

-- | Compute precision for the SQL decimal type
computePrecision :: Int -> Int -> Int
computePrecision l e
    | e == 0         = l
    | e > 0 && l < e = l + (e - l)
    | e > 0          = l
    | otherwise      = l + (negate e)

-- | Fix precision for negative values
negPrecision :: Int -> Int -> [Int] -> Int -> Int
negPrecision e l ds p
    | e >= l && all (< 0) ds = p + 1
    | otherwise              = p

-- | Compute scale for the SQL decimal type
computeScale :: Int -> Int -> Int
computeScale l e
    | e == 0 = l
    | e > 0 && l > e = l - e
    | e > 0          = 0
    | otherwise      = l + negate e
