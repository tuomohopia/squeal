
{-# LANGUAGE
    AllowAmbiguousTypes
  , DeriveFoldable
  , DeriveFunctor
  , DeriveGeneric
  , DeriveTraversable
  , DefaultSignatures
  , FlexibleContexts
  , FlexibleInstances
  , FunctionalDependencies
  , GADTs
  , LambdaCase
  , OverloadedStrings
  , MultiParamTypeClasses
  , ScopedTypeVariables
  , TypeApplications
  , TypeFamilies
  , TypeInType
  , TypeOperators
  , UndecidableInstances
  , UndecidableSuperClasses
#-}

module Squeal.PostgreSQL.PG
  ( PG
  , NullPG
  , TuplePG
  , RowPG
  , Entity
  , SOP.P (..)
  , LabelsPG
  , DimPG
  , FixPG
  , TupleOf
  , TupleCodeOf
  , ConstructorsOf
  , ConstructorNameOf
  , ConstructorNamesOf
  ) where

import Data.Aeson (Value)
import Data.Kind (Type)
import Data.Int (Int16, Int32, Int64)
import Data.Scientific (Scientific)
import Data.Time (Day, DiffTime, LocalTime, TimeOfDay, TimeZone, UTCTime)
import Data.Word (Word16, Word32, Word64)
import Data.UUID.Types (UUID)
import GHC.TypeLits
import Network.IP.Addr (NetAddr, IP)

import qualified Data.ByteString.Lazy as Lazy (ByteString)
import qualified Data.ByteString as Strict (ByteString)
import qualified Data.Text.Lazy as Lazy (Text)
import qualified Data.Text as Strict (Text)
import qualified Generics.SOP as SOP
import qualified Generics.SOP.Record as SOP
import qualified Generics.SOP.Type.Metadata as Type

import Squeal.PostgreSQL.Alias
import Squeal.PostgreSQL.List
import Squeal.PostgreSQL.Schema

{- | The `PG` type family embeds a subset of Haskell types
as Postgres types. As an open type family, `PG` is extensible.

>>> :kind! PG LocalTime
PG LocalTime :: PGType
= 'PGtimestamp

>>> newtype MyDouble = My Double
>>> :set -XTypeFamilies
>>> type instance PG MyDouble = 'PGfloat8
-}
type family PG (hask :: Type) :: PGType
type instance PG Bool = 'PGbool
type instance PG Int16 = 'PGint2
type instance PG Int32 = 'PGint4
type instance PG Int64 = 'PGint8
type instance PG Word16 = 'PGint2
type instance PG Word32 = 'PGint4
type instance PG Word64 = 'PGint8
type instance PG Scientific = 'PGnumeric
type instance PG Float = 'PGfloat4
type instance PG Double = 'PGfloat8
type instance PG Char = 'PGchar 1
type instance PG Strict.Text = 'PGtext
type instance PG Lazy.Text = 'PGtext
type instance PG String = 'PGtext
type instance PG Strict.ByteString = 'PGbytea
type instance PG Lazy.ByteString = 'PGbytea
type instance PG LocalTime = 'PGtimestamp
type instance PG UTCTime = 'PGtimestamptz
type instance PG Day = 'PGdate
type instance PG TimeOfDay = 'PGtime
type instance PG (TimeOfDay, TimeZone) = 'PGtimetz
type instance PG DiffTime = 'PGinterval
type instance PG UUID = 'PGuuid
type instance PG (NetAddr IP) = 'PGinet
type instance PG Value = 'PGjson

{-| The `LabelsPG` type family calculates the constructors of a
Haskell enum type.

>>> data Schwarma = Beef | Lamb | Chicken deriving GHC.Generic
>>> instance Generic Schwarma
>>> instance HasDatatypeInfo Schwarma
>>> :kind! LabelsPG Schwarma
LabelsPG Schwarma :: [Type.ConstructorName]
= '["Beef", "Lamb", "Chicken"]
-}
type family LabelsPG (hask :: Type) :: [Type.ConstructorName] where
  LabelsPG hask =
    ConstructorNamesOf (ConstructorsOf (SOP.DatatypeInfoOf hask))

{- |
`RowPG` turns a Haskell `Type` into a `RowType`.

`RowPG` may be applied to normal Haskell record types provided they
have the `Generic` and `HasDatatypeInfo` instances;

>>> data Person = Person { name :: Text, age :: Int32 } deriving GHC.Generic
>>> instance Generic Person
>>> instance HasDatatypeInfo Person
>>> :kind! RowPG Person
RowPG Person :: [(Symbol, NullityType)]
= '["name" ::: 'NotNull 'PGtext, "age" ::: 'NotNull 'PGint4]

Or to tuples of `P` types;

>>> :kind! RowPG (P ("id" ::: Int32), P ("foreign_id" ::: Int32))
RowPG (P ("id" ::: Int32), P ("foreign_id" ::: Int32)) :: [(Symbol,
                                                            NullityType)]
= '[ '("id", 'NotNull 'PGint4), "foreign_id" ::: 'NotNull 'PGint4]

Or to tuples which mix `P` types and record types.

>>> :kind! RowPG (P ("id" ::: Int32), Person, P ("foreign_id" ::: Int32))
RowPG (P ("id" ::: Int32), Person, P ("foreign_id" ::: Int32)) :: [(Symbol,
                                                                    NullityType)]
= '[ '("id", 'NotNull 'PGint4), '("name", 'NotNull 'PGtext),
     '("age", 'NotNull 'PGint4), "foreign_id" ::: 'NotNull 'PGint4]
-}
type family RowPG (hask :: Type) :: RowType where
  RowPG (hask1, hask2) = Join (RowPG hask1) (RowPG hask2)
  RowPG (hask1, hask2, hask3) =
    Join (RowPG hask1) (RowPG (hask2, hask3))
  RowPG (hask1, hask2, hask3, hask4) =
    Join (RowPG hask1) (RowPG (hask2, hask3, hask4))
  RowPG (hask1, hask2, hask3, hask4, hask5) =
    Join (RowPG hask1) (RowPG (hask2, hask3, hask4, hask5))
  RowPG (SOP.P (col ::: head)) = '[col ::: NullPG head]
  RowPG hask = RowOf (SOP.RecordCodeOf hask)

type family RowOf (record :: [(Symbol, Type)]) :: RowType where
  RowOf '[] = '[]
  RowOf (col ::: ty ': record) = col ::: NullPG ty ': RowOf record

type family ColumnsOf (record :: [(Symbol, Type)]) :: ColumnsType where
  ColumnsOf '[] = '[]
  ColumnsOf (col ::: ty ': record) =
    col ::: 'NoDef :=> NullPG ty ': ColumnsOf record

{- |
`Entity` turns a Haskell `Type` into a `ColumnsType`.

`Entity` may be applied to normal Haskell record types provided they
have the `Generic` and `HasDatatypeInfo` instances;

>>> data Person = Person { name :: Text, age :: Int32 } deriving GHC.Generic
>>> instance Generic Person
>>> instance HasDatatypeInfo Person
>>> :kind! Entity Person
Entity Person :: [(Symbol, (ColumnConstraint, NullityType))]
= '["name" ::: ('NoDef :=> 'NotNull 'PGtext),
    "age" ::: ('NoDef :=> 'NotNull 'PGint4)]

Or to tuples of `P` types;

>>> :kind! Entity (P ("id" ::: Int32), P ("foreign_id" ::: Int32))
Entity (P ("id" ::: Int32), P ("foreign_id" ::: Int32)) :: [(Symbol,
                                                             ColumnType)]
= '[ '("id", 'Def :=> 'NotNull 'PGint4),
     "foreign_id" ::: ('Def :=> 'NotNull 'PGint4)]

Or to tuples which mix `P` types and record types.

>>> :kind! Entity (P ("id" ::: Int32), Person, P ("foreign_id" ::: Int32))
Entity (P ("id" ::: Int32), Person, P ("foreign_id" ::: Int32)) :: [(Symbol,
                                                                     ColumnType)]
= '[ '("id", 'Def :=> 'NotNull 'PGint4),
     '("name", 'NoDef :=> 'NotNull 'PGtext),
     '("age", 'NoDef :=> 'NotNull 'PGint4),
     "foreign_id" ::: ('Def :=> 'NotNull 'PGint4)]
-}
type family Entity (hask :: Type) :: ColumnsType where
  Entity (hask1, hask2) = Join (Entity hask1) (Entity hask2)
  Entity (hask1, hask2, hask3) =
    Join (Entity hask1) (Entity (hask2, hask3))
  Entity (hask1, hask2, hask3, hask4) =
    Join (Entity hask1) (Entity (hask2, hask3, hask4))
  Entity (hask1, hask2, hask3, hask4, hask5) =
    Join (Entity hask1) (Entity (hask2, hask3, hask4, hask5))
  Entity (SOP.P (col ::: head)) = '[col ::: 'Def :=> NullPG head]
  Entity hask = ColumnsOf (SOP.RecordCodeOf hask)

{- | `NullPG` turns a Haskell type into a `NullityType`.

>>> :kind! NullPG Double
NullPG Double :: NullityType
= 'NotNull 'PGfloat8
>>> :kind! NullPG (Maybe Double)
NullPG (Maybe Double) :: NullityType
= 'Null 'PGfloat8
-}
type family NullPG (hask :: Type) :: NullityType where
  NullPG (Maybe hask) = 'Null (PG hask)
  NullPG hask = 'NotNull (PG hask)

{- | `TuplePG` turns a Haskell tuple type (including record types) into
the corresponding list of `NullityType`s.

>>> :kind! TuplePG (Double, Maybe Char)
TuplePG (Double, Maybe Char) :: [NullityType]
= '[ 'NotNull 'PGfloat8, 'Null ('PGchar 1)]
-}
type family TuplePG (hask :: Type) :: [NullityType] where
  TuplePG hask = TupleOf (TupleCodeOf hask (SOP.Code hask))

type family TupleOf (tuple :: [Type]) :: [NullityType] where
  TupleOf '[] = '[]
  TupleOf (hask ': tuple) = NullPG hask ': TupleOf tuple

type family TupleCodeOf (hask :: Type) (code :: [[Type]]) :: [Type] where
  TupleCodeOf hask '[tuple] = tuple
  TupleCodeOf hask '[] =
    TypeError
      (    'Text "The type `" ':<>: 'ShowType hask ':<>: 'Text "' is not a tuple type."
      ':$$: 'Text "It is a void type with no constructors."
      )
  TupleCodeOf hask (_ ': _ ': _) =
    TypeError
      (    'Text "The type `" ':<>: 'ShowType hask ':<>: 'Text "' is not a tuple type."
      ':$$: 'Text "It is a sum type with more than one constructor."
      )

-- | Calculates constructors of a datatype.
type family ConstructorsOf (datatype :: Type.DatatypeInfo)
  :: [Type.ConstructorInfo] where
    ConstructorsOf ('Type.ADT _module _datatype constructors) =
      constructors
    ConstructorsOf ('Type.Newtype _module _datatype constructor) =
      '[constructor]

-- | Calculates the name of a nullary constructor, otherwise
-- generates a type error.
type family ConstructorNameOf (constructor :: Type.ConstructorInfo)
  :: Type.ConstructorName where
    ConstructorNameOf ('Type.Constructor name) = name
    ConstructorNameOf ('Type.Infix name _assoc _fix) = TypeError
      ('Text "ConstructorNameOf error: non-nullary constructor "
        ':<>: 'Text name)
    ConstructorNameOf ('Type.Record name _fields) = TypeError
      ('Text "ConstructorNameOf error: non-nullary constructor "
        ':<>: 'Text name)

-- | Calculate the names of nullary constructors.
type family ConstructorNamesOf (constructors :: [Type.ConstructorInfo])
  :: [Type.ConstructorName] where
    ConstructorNamesOf '[] = '[]
    ConstructorNamesOf (constructor ': constructors) =
      ConstructorNameOf constructor ': ConstructorNamesOf constructors

type family DimPG (hask :: Type) :: [Nat] where
  DimPG (x,x) = 2 ': DimPG x
  DimPG (x,x,x) = 3 ': DimPG x
  DimPG (x,x,x,x) = 4 ': DimPG x
  DimPG (x,x,x,x,x) = 5 ': DimPG x
  DimPG (x,x,x,x,x,x) = 6 ': DimPG x
  DimPG (x,x,x,x,x,x,x) = 7 ': DimPG x
  DimPG (x,x,x,x,x,x,x,x) = 8 ': DimPG x
  DimPG (x,x,x,x,x,x,x,x,x) = 9 ': DimPG x
  DimPG (x,x,x,x,x,x,x,x,x,x) = 10 ': DimPG x
  DimPG x = '[]

type family FixPG (hask :: Type) :: NullityType where
  FixPG (x,x) = FixPG x
  FixPG (x,x,x) = FixPG x
  FixPG (x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x,x,x,x,x) = FixPG x
  FixPG (x,x,x,x,x,x,x,x,x,x,x) = FixPG x
  FixPG x = NullPG x
