{-|
Module      : Language.Qux.Syntax
Description : Abstract syntax tree nodes.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : hjwylde@gmail.com

Abstract syntax tree nodes.

Instances of 'Pretty' are provided for pretty printing.
-}

module Language.Qux.Syntax (
    -- * Nodes
    Id, Program(..), Decl(..), Attribute(..), Stmt(..), Expr(..), BinaryOp(..),
    UnaryOp(..), Value(..), Type(..),

    -- * Extra functions

    -- ** Utility
    qualify, mangle,
) where

import Data.List.Extra

import Text.PrettyPrint
import Text.PrettyPrint.Extra
import Text.PrettyPrint.HughesPJClass

-- | An identifier. Identifiers should match '[a-z_][a-zA-Z0-9_']*'.
type Id = String

-- | A program is a module identifier (list of 'Id''s) and a list of declarations.
data Program = Program [Id] [Decl]
    deriving (Eq, Show)

instance Pretty Program where
    pPrint (Program module_ decls) = vcat . map ($+$ text "") $
        (text "module" <+> hcat (punctuate dot (map text module_))) : map pPrint decls

-- | A declaration.
data Decl   = FunctionDecl [Attribute] Id [(Type, Id)] [Stmt]   -- ^ A name, list of ('Type', 'Id') parameters and statements.
                                                                --   The return type is treated as a parameter with id '@'.
            | ImportDecl [Id]                                   -- ^ A module identifier to import.
            | TypeDecl [Attribute] Id                           -- ^ A type declaration.
    deriving (Eq, Show)

instance Pretty Decl where
    pPrint (FunctionDecl attrs name type_ [])       = declarationDoc attrs name type_
    pPrint (FunctionDecl attrs name type_ stmts)    = vcat
        [ declarationDoc attrs name type_ <> colon
        , block stmts
        ]
    pPrint (ImportDecl id)                          = text "import" <+> hcat (punctuate dot (map text id))
    pPrint (TypeDecl attrs name)                    = text "type" <+> hsep (map pPrint attrs) <+> text name

declarationDoc :: [Attribute] -> Id -> [(Type, Id)] -> Doc
declarationDoc attrs name type_ = hsep $ map pPrint attrs ++ [text name, dcolon, functionTypeDoc]
    where
        functionTypeDoc = fsep $ punctuate
            (space <> rarrow)
            [pPrint t <+> if p == "@" then empty else text p | (t, p) <- type_]

-- | A declaration attribute.
data Attribute = External
    deriving (Eq, Show)

instance Pretty Attribute where
    pPrint = text . lower . show

-- | A statement.
data Stmt   = IfStmt Expr [Stmt] [Stmt] -- ^ A condition, true block and false block of statements.
            | CallStmt Expr             -- ^ A call statement.
            | ReturnStmt (Maybe Expr)   -- ^ An expression.
            | WhileStmt Expr [Stmt]     -- ^ A condition and block of statements.
    deriving (Eq, Show)

instance Pretty Stmt where
    pPrint (IfStmt condition trueStmts falseStmts)  = vcat
        [ text "if" <+> pPrint condition <> colon
        , block trueStmts
        , if null falseStmts
            then empty
            else text "else" <> colon
        , block falseStmts
        ]
    pPrint (CallStmt expr)                          = pPrint expr
    pPrint (ReturnStmt mExpr)                       = hsep
        [ text "return"
        , maybe empty pPrint mExpr
        ]
    pPrint (WhileStmt condition stmts)              = vcat
        [ text "while" <+> pPrint condition <> colon
        , block stmts
        ]

-- | A complex expression.
data Expr   = ApplicationExpr Id [Expr]     -- ^ A function name (unresolved) to call and the
                                            --   arguments to pass as parameters.
            | BinaryExpr BinaryOp Expr Expr -- ^ A binary operation.
            | CallExpr [Id] [Expr]          -- ^ A function identifier (resolved) to call and the
                                            --   arguments to pass as parameters.
            | TypedExpr Type Expr           -- ^ A typed expression.
                                            --   See "Language.Qux.Annotated.TypeResolver".
            | UnaryExpr UnaryOp Expr        -- ^ A unary operation.
            | ValueExpr Value               -- ^ A raw value.
            | VariableExpr Id               -- ^ A local variable access.
    deriving (Eq, Show)

instance Pretty Expr where
    pPrint (ApplicationExpr name arguments) = text name <+> fsep (map pPrint arguments)
    pPrint (BinaryExpr op lhs rhs)          = parens $ fsep [pPrint lhs, pPrint op, pPrint rhs]
    pPrint (CallExpr id arguments)          = text (qualify id) <+> fsep (map pPrint arguments)
    pPrint (TypedExpr _ expr)               = pPrint expr
    pPrint (UnaryExpr op expr)              = pPrint op <> pPrint expr
    pPrint (ValueExpr value)                = pPrint value
    pPrint (VariableExpr name)              = text name

-- | A binary operator.
data BinaryOp   = Mul -- ^ Multiplicaiton.
                | Div -- ^ Division.
                | Mod -- ^ Modulus.
                | Add -- ^ Addition.
                | Sub -- ^ Subtraction.
                | Lt  -- ^ Less than.
                | Lte -- ^ Less than or equal to.
                | Gt  -- ^ Greater than.
                | Gte -- ^ Greater than or equal to.
                | Eq  -- ^ Equal to.
                | Neq -- ^ Not equal to.
    deriving (Eq, Show)

instance Pretty BinaryOp where
    pPrint Mul = asterisk
    pPrint Div = fslash
    pPrint Mod = percent
    pPrint Add = plus
    pPrint Sub = hyphen
    pPrint Lt  = langle
    pPrint Lte = langle <> equals
    pPrint Gt  = rangle
    pPrint Gte = rangle <> equals
    pPrint Eq  = dequals
    pPrint Neq = bang <> equals

-- | A unary operator.
data UnaryOp = Neg -- ^ Negation.
    deriving (Eq, Show)

instance Pretty UnaryOp where
    pPrint Neg = hyphen

-- | A value is considered to be in it's normal form.
data Value  = BoolValue Bool    -- ^ A boolean.
            | IntValue Integer  -- ^ An unbounded integer.
            | StrValue String   -- ^ A string.
    deriving (Eq, Show)

instance Pretty Value where
    pPrint (BoolValue bool) = text $ lower (show bool)
    pPrint (IntValue int)   = text $ show int
    pPrint (StrValue str)   = doubleQuotes $ text str

-- | A type.
data Type   = AnyType
            | BoolType
            | IntType
            | StrType
            | VoidType
    deriving (Eq, Show)

instance Pretty Type where
    pPrint AnyType  = text "Any"
    pPrint BoolType = text "Bool"
    pPrint IntType  = text "Int"
    pPrint StrType  = text "Str"
    pPrint VoidType = text "()"

-- | Qualifies the identifier into a single 'Id' joined with periods.
qualify :: [Id] -> Id
qualify = intercalate "."

-- | Mangles the identifier into a single 'Id' joined with underscores.
mangle :: [Id] -> Id
mangle = intercalate "_"

block :: [Stmt] -> Doc
block = nest 4 . vcat . map pPrint
