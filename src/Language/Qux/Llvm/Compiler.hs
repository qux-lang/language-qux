{-|
Module      : Language.Qux.Llvm.Compiler
Description : Compiles a Qux program into LLVM IR.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : hjwylde@gmail.com

A compiler that takes a 'Program' and outputs an LLVM 'Module'.
-}

{-# LANGUAGE FlexibleContexts #-}

module Language.Qux.Llvm.Compiler (
    -- * Global context
    Context(..),
    baseContext, context, emptyContext,

    -- * Compilation
    compileProgram,
) where

import Control.Lens         hiding (Context)
import Control.Monad.Reader hiding (local)
import Control.Monad.State
import Control.Monad.Writer

import qualified Data.Map    as Map
import           Data.Maybe
import           Data.String

import Language.Qux.Context        hiding (local)
import Language.Qux.Llvm.Builder   as Builder
import Language.Qux.Llvm.Generator
import Language.Qux.Syntax         as Qux

import LLVM.AST                  as Llvm hiding (VoidType, function)
import LLVM.AST.Constant         as Constant hiding (exact, nsw, nuw, operand0, operand1)
import LLVM.AST.Global           as Global
import LLVM.AST.IntegerPredicate

import Prelude hiding (EQ)

-- | Compiles the program into an LLVM 'Module'.
--   Generally speaking, compilation is done using the defaults.
--   Any exceptions to this will be clearly noted.
compileProgram :: MonadReader Context m => Program -> m Module
compileProgram (Program module_ decls) = do
    importedFunctions' <- views (imported . functions) (map (\(id, type_) -> GlobalDefinition functionDefaults
        { Global.name       = mkName $ mangle id
        , Global.returnType = compileType $ fst (last type_)
        , Global.parameters = ([Parameter (compileType t) (mkName p) [] | (t, p) <- init type_], False)
        }) . Map.toList)

    let externalFunctions =
            [ GlobalDefinition functionDefaults
                { Global.name       = mkName $ mangle (module_ ++ [name])
                , Global.returnType = compileType $ fst (last type_)
                , Global.parameters = ([Parameter (compileType t) (mkName p) [] | (t, p) <- init type_], False)
                }
            | (FunctionDecl attrs name type_ _) <- decls, External `elem` attrs
            ]

    localFunctions <- mapM compileDecl
        [ decl
        | decl@(FunctionDecl attrs _ _ _) <- decls
        , External `notElem` attrs
        ]

    importedTypes' <- views (imported . types) (map $ \id -> TypeDefinition (mkName $ mangle id) Nothing)

    let externalTypes =
            [ TypeDefinition (mkName $ mangle (module_ ++ [name])) Nothing
            | (TypeDecl attrs name) <- decls
            , External `elem` attrs
            ]

    return $ defaultModule
        { moduleName        = fromString $ qualify module_
        , moduleDefinitions = concat
            [ importedFunctions'
            , externalFunctions
            , localFunctions
            , importedTypes'
            , externalTypes
            ]
        }

compileDecl :: MonadReader Context m => Decl -> m Definition
compileDecl (FunctionDecl _ name type_ stmts)   = do
    module_'    <- view module_
    builder     <- execStateT (mapM_ compileStmt stmts >> commitCurrentBlock) newFunctionBuilder

    let name' = mkName $ mangle (module_' ++ [name])
    let type_' = compileType $ fst (last type_)
    let parameters = [(compileType type_', mkName name) | (type_', name) <- init type_]
    let blocks' = builder ^. blocks

    return $ function name' type_' parameters blocks'
compileDecl (ImportDecl _)                      = error "internal error: cannot compile an import declaration"
compileDecl (TypeDecl _ _)                      = error "internal error: cannot compile a type declaration"

compileStmt :: (MonadReader Context m, MonadState FunctionBuilder m) => Stmt -> m ()
compileStmt (IfStmt condition trueStmts falseStmts) = do
    if_ (compileExpr condition)
        (mapM_ compileStmt trueStmts)
        (mapM_ compileStmt falseStmts)
compileStmt (CallStmt expr)                         = do
    invoke (compileExpr_ expr)
compileStmt (ReturnStmt mExpr)                      = do
    return_ (mapM compileExpr mExpr)
compileStmt (WhileStmt condition stmts)             = do
    while (compileExpr condition)
        (mapM_ compileStmt stmts)

compileExpr :: (MonadReader Context m, MonadState FunctionBuilder m, MonadWriter BlockBuilder m) => Expr -> m Operand
compileExpr (TypedExpr type_ (BinaryExpr op lhs rhs)) = do
    lhsOperand <- compileExpr lhs
    rhsOperand <- compileExpr rhs

    name <- freeUnName

    case op of
        Qux.Mul -> mul lhsOperand rhsOperand name
        Qux.Div -> sdiv lhsOperand rhsOperand name
        Qux.Mod -> srem lhsOperand rhsOperand name
        Qux.Add -> add lhsOperand rhsOperand name
        Qux.Sub -> sub lhsOperand rhsOperand name
        Qux.Lt  -> icmp SLT lhsOperand rhsOperand name
        Qux.Lte -> icmp SLE lhsOperand rhsOperand name
        Qux.Gt  -> icmp SGT lhsOperand rhsOperand name
        Qux.Gte -> icmp SGE lhsOperand rhsOperand name
        Qux.Eq  -> icmp EQ lhsOperand rhsOperand name
        Qux.Neq -> icmp NE lhsOperand rhsOperand name

    return $ local (compileType type_) name
compileExpr (TypedExpr type_ (CallExpr id arguments))       = do
    operands <- mapM compileExpr arguments

    name <- freeUnName

    call (compileType type_) (mkName $ mangle id) operands name

    return $ local (compileType type_) name
compileExpr (TypedExpr type_ (UnaryExpr op expr))           = do
    operand <- compileExpr expr

    name <- freeUnName

    case op of
        Neg -> mul operand (constant $ int (-1)) name

    return $ local (compileType type_) name
compileExpr (TypedExpr type_ (ValueExpr (StrValue s)))      = do
    let nullTerminatedStr = s ++ "\0"
    let strLength = length nullTerminatedStr

    let strArrayType = arrayType charType (fromIntegral $ strLength)
    let lengthOperand = constant . int $ fromIntegral strLength

    name <- freeUnName
    alloca strArrayType (Just lengthOperand) name

    let valueOperand = constant $ str nullTerminatedStr
    let strPtrArrayType = ptrType strArrayType

    store valueOperand (local strPtrArrayType name)

    let strPtrType = compileType type_

    name' <- freeUnName
    bitcast (local strPtrArrayType name) strPtrType name'

    return $ local strPtrType name'
compileExpr (TypedExpr _ (ValueExpr value))                 = return $ constant (compileValue value)
compileExpr (TypedExpr type_ (VariableExpr name))           = return $ local (compileType type_) (mkName name)
compileExpr _                                               = error "internal error: cannot compile a non-typed expression (try applying type resolution)"

compileExpr_ :: (MonadReader Context m, MonadState FunctionBuilder m, MonadWriter BlockBuilder m) => Expr -> m ()
compileExpr_ = void <$> compileExpr

compileValue :: Value -> Constant
compileValue (BoolValue True)   = true
compileValue (BoolValue False)  = false
compileValue (IntValue i)       = int i
compileValue (StrValue _)       = error "internal error: cannot compile a string as a constant"

compileType :: Qux.Type -> Llvm.Type
compileType AnyType     = error "internal error: cannot compile an any type"
compileType BoolType    = boolType
compileType IntType     = intType
compileType StrType     = strType
compileType VoidType    = voidType
