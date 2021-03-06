-- | Datatypes and functions which determine termination of SQL fragments.
module Database.Algebra.SQL.Termination
    ( FeatureSet
    , terminatesOver
    , noneF
    , colProjectF
    , exprProjectF
    , filterF
    , tableF
    , dupElimF
    , sortF
    , windowFunctionF
    , aggrAndGroupingF
    , module Data.Monoid
    ) where

import           Data.List                    (intercalate)
import           Data.Monoid
import qualified Data.Set                     as S
import Data.Semigroup as Sem

import           Database.Algebra.SQL.Dialect

-- | Specifies a part in a SQL statement which is currently in use.
data Feature = ColumnProjectF   -- ^ Projection of columns.
             | ExprProjectF     -- ^ Projection with arbitrary expressions
             | TableF              -- ^ Physical or virtual table.
             | FilterF             -- ^ Filtering of rows.
             | DupElimF
             | SortF
             | WindowFunctionF
             | AggrAndGroupingF
             deriving (Eq, Ord, Show)

-- TODO maybe use just list, since we usually have so few
newtype FeatureSet = F { unF :: S.Set Feature }

wrap :: Feature -> FeatureSet
wrap = F . S.singleton

noneF, colProjectF, exprProjectF, filterF, tableF, dupElimF, sortF, windowFunctionF, aggrAndGroupingF :: FeatureSet
noneF = F S.empty
colProjectF = wrap ColumnProjectF
exprProjectF = wrap ExprProjectF
filterF = wrap FilterF
tableF = wrap TableF
dupElimF = wrap DupElimF
sortF = wrap SortF
windowFunctionF = wrap WindowFunctionF
aggrAndGroupingF = wrap AggrAndGroupingF

instance Sem.Semigroup FeatureSet where
    (<>) (F l) (F r) = F $ l `S.union` r
instance Monoid FeatureSet where
    mempty              = noneF
    mconcat fs          = F $ S.unions $ map unF fs
    mappend = (<>)

instance Show FeatureSet where
    show (F s) = "<" ++ intercalate ", " (map show $ S.toList s) ++ ">"

-- | Lists all features which lead to a termination, for a given feature
-- coming from an operator placed below.
terminatingFeatures :: Dialect -> Feature -> FeatureSet
terminatingFeatures PostgreSQL = terminatingFeaturesPg
terminatingFeatures MonetDB    = terminatingFeaturesM5
terminatingFeatures SQL99      = undefined

-- | Lists all features which lead to a termination on MonetDB5/SQL, for a given
-- feature coming from an operator placed below.
terminatingFeaturesM5 :: Feature -> FeatureSet
terminatingFeaturesM5 bottomF = F $ case bottomF of
    -- MonetDB/SQL allows only column references in partitioning specifications
    -- for window clauses as well as in grouping specifications.
    ExprProjectF   -> S.fromList [AggrAndGroupingF, WindowFunctionF]
    ColumnProjectF -> S.empty
    TableF         -> S.empty
    FilterF        -> S.empty
    -- Distinction has to occur before:
    --
    --     * Projection of columns: Because there exist cases where to much gets
    --       removed.
    --
    --     * Aggregation: Because the previous result set influences the value
    --       of aggregate functions, including duplicates.
    --
    --     * Grouping: Grouping could project away columns, which are needed for
    --       duplicate elimination.
    --
    DupElimF         -> S.fromList [ExprProjectF, ColumnProjectF, AggrAndGroupingF]
    -- The ORDER BY clause will only be used on top.
    SortF            -> S.empty
    -- Problematic cases:
    --
    --     * Filtering: May change the intermediate result set.
    --
    --     * Duplicate removal with DISTINCT has another semantic meaning.
    --
    --     * Stacked window functions can possibly have other windows and window
    --       functions can not be nested.
    --
    --     * Aggregates of window functions can not be built.
    --
    WindowFunctionF  ->
        S.fromList [FilterF, DupElimF, WindowFunctionF, AggrAndGroupingF]
    -- Problematic cases:
    --
    --     * Filtering: May change intermediate result set.
    --
    --     * Aggregate functions can not be stacked.
    --
    --     * Is there a case, where OLAP functions using windows with aggregates
    --       makes sense? It is possible, and inlining works, therefore it is
    --       enabled.
    --
    AggrAndGroupingF -> S.fromList [FilterF, AggrAndGroupingF]

-- | Lists all features which lead to a termination on PostgreSQL, for a given
-- feature coming from an operator placed below.
terminatingFeaturesPg :: Feature -> FeatureSet
terminatingFeaturesPg bottomF = F $ case bottomF of
    ExprProjectF   -> S.empty
    ColumnProjectF -> S.empty
    TableF         -> S.empty
    FilterF        -> S.empty
    -- Distinction has to occur before:
    --
    --     * Projection of columns: Because there exist cases where to much gets
    --       removed.
    --
    --     * Aggregation: Because the previous result set influences the value
    --       of aggregate functions, including duplicates.
    --
    --     * Grouping: Grouping could project away columns, which are needed for
    --       duplicate elimination.
    --
    DupElimF         -> S.fromList [ColumnProjectF, ExprProjectF, AggrAndGroupingF]
    -- The ORDER BY clause will only be used on top.
    SortF            -> S.empty
    -- Problematic cases:
    --
    --     * Filtering: May change the intermediate result set.
    --
    --     * Duplicate removal with DISTINCT has another semantic meaning.
    --
    --     * Stacked window functions can possibly have other windows and window
    --       functions can not be nested.
    --
    --     * Aggregates of window functions can not be built.
    --
    WindowFunctionF  ->
        S.fromList [FilterF, DupElimF, WindowFunctionF, AggrAndGroupingF]
    -- Problematic cases:
    --
    --     * Filtering: May change intermediate result set.
    --
    --     * Aggregate functions can not be stacked.
    --
    --     * Is there a case, where OLAP functions using windows with aggregates
    --       makes sense? It is possible, and inlining works, therefore it is
    --       enabled.
    --
    AggrAndGroupingF -> S.fromList [FilterF, AggrAndGroupingF]

-- | Determines whether two feature sets collide and therefore whether we should
-- terminate a SQL fragment. Returns 'True' iff the feature sets collide.
terminatesOver :: Dialect -> FeatureSet -> FeatureSet -> Bool
terminatesOver dialect (F topFs) (F bottomFs) =
    not $ S.null $ conflictingFs `S.intersection` topFs
  where
    (F conflictingFs) = foldr (\feature conflictSet -> conflictSet <> terminatingFeatures dialect feature)
                              mempty
                              bottomFs

