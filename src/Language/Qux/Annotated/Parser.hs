
{-|
Module      : Language.Qux.Annotated.Parser
Description : A Parsec indentation-based parser for generating a program.

Copyright   : (c) Henry J. Wylde, 2015
License     : BSD3
Maintainer  : public@hjwylde.com

A "Text.Parsec" indentation-based parser for generating a 'Program'.
-}

module Language.Qux.Annotated.Parser (
    -- * Types
    Parser, ParseError, SourcePos,
    sourceName, sourceLine, sourceColumn,

    -- ** Parsing
    parse,

    -- ** Parsers
    program, decl, stmt, expr, value, type_
) where

import Control.Monad.State
import Control.Monad.Trans.Except

import Language.Qux.Annotated.Syntax
import Language.Qux.Lexer

import Text.Parsec hiding (State, parse)
import Text.Parsec.Expr
import Text.Parsec.Indent


-- | A 'ParsecT' that retains indentation information.
type Parser a = ParsecT String () (State SourcePos) a


-- |    @parse parser sourceName input@ parses @input@ using @parser@.
--      Returns either a 'ParseError' or @a@.
--      This method wraps 'runParserT' by running the indentation resolver over the parser's state.
parse :: Parser a -> SourceName -> String -> Except ParseError a
parse parser sourceName input = except $ runIndent sourceName (runParserT parser () sourceName input)


-- | 'Id' parser.
id_ :: Parser (Id SourcePos)
id_ = Id <$> getPosition <*> identifier <?> "identifier"

-- | 'Program' parser.
program :: Parser (Program SourcePos)
program = do
    pos <- getPosition
    whiteSpace
    checkIndent
    decls <- block decl
    eof
    return $ Program pos decls

-- | 'Decl' parser.
decl :: Parser (Decl SourcePos)
decl = do
    pos <- getPosition
    name <- id_
    symbol "::"
    parameters <- (try $ (,) <$> type_ <*> id_) `endBy` rightArrow
    returnType <- type_
    colon
    indented
    stmts <- block stmt
    return $ FunctionDecl pos name (parameters ++ [(returnType, Id pos "@")]) stmts
    <?> "function declaration"

-- | 'Stmt' parser.
stmt :: Parser (Stmt SourcePos)
stmt = choice [
    ifStmt,
    returnStmt,
    whileStmt
    ] <?> "statement"
    where
        ifStmt      = do
            pos <- getPosition
            reserved "if"
            condition <- expr
            colon
            indented
            trueStmts <- block stmt
            falseStmts <- option [] (checkIndent >> withBlock' (do { reserved "else"; colon }) stmt)
            return $ IfStmt pos condition trueStmts falseStmts
        returnStmt  = ReturnStmt <$> getPosition <* reserved "return" <*> expr
        whileStmt   = do
            pos <- getPosition
            withBlock (WhileStmt pos) (reserved "while" *> expr <* colon) stmt

-- | 'Expr' parser.
expr :: Parser (Expr SourcePos)
expr = buildExpressionParser table (try application <|> term) <?> "expression"

application :: Parser (Expr SourcePos)
application = ApplicationExpr <$> getPosition <*> id_ <*> many (sameOrIndented >> term)

term :: Parser (Expr SourcePos)
term = getPosition >>= \pos -> choice [
    parens expr,
    ApplicationExpr pos <$> id_ <*> return [],
    ListExpr  pos       <$> brackets (expr `sepEndBy` comma),
    UnaryExpr pos Len   <$> pipes expr,
    ValueExpr pos       <$> value
    ]

table :: OperatorTable String () (State SourcePos) (Expr SourcePos)
table = [
    [
        Prefix (unaryExpr Neg "-")
    ],
    [
        Infix (binaryExpr Acc "!!") AssocLeft
    ],
    [
        Infix (binaryExpr Mul "*") AssocLeft,
        Infix (binaryExpr Div "/") AssocLeft,
        Infix (binaryExpr Mod "%") AssocLeft
    ],
    [
        Infix (binaryExpr Add "+") AssocLeft,
        Infix (binaryExpr Sub "-") AssocLeft
    ],
    [
        Infix (binaryExpr Lte "<=") AssocLeft,
        Infix (binaryExpr Lt "<") AssocLeft,
        Infix (binaryExpr Gte ">=") AssocLeft,
        Infix (binaryExpr Gt ">") AssocLeft
    ],
    [
        Infix (binaryExpr Eq "==") AssocLeft,
        Infix (binaryExpr Neq "!=") AssocLeft
    ]
    ]

binaryExpr :: BinaryOp -> String -> Parser ((Expr SourcePos) -> (Expr SourcePos) -> (Expr SourcePos))
binaryExpr op sym = getPosition >>= \pos -> BinaryExpr pos op <$ operator sym

unaryExpr :: UnaryOp -> String -> Parser ((Expr SourcePos) -> (Expr SourcePos))
unaryExpr op sym = getPosition >>= \pos -> UnaryExpr pos op <$ operator sym

-- | 'Value' parser.
value :: Parser Value
value = choice [
    BoolValue False <$  reserved "false",
    BoolValue True  <$  reserved "true",
    IntValue        <$> natural,
    NilValue        <$  reserved "nil"
    ] <?> "value"

-- | 'Type' parser.
type_ :: Parser (Type SourcePos)
type_ = getPosition >>= \pos -> choice [
    BoolType pos <$  reserved "Bool",
    IntType  pos <$  reserved "Int",
    ListType pos <$> brackets type_,
    NilType  pos <$  reserved "Nil"
    ] <?> "type"

