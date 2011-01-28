#!/usr/bin/env runhaskell


import Data.List
import Data.Char
import Data.Maybe

import Text.Parsec

import System.FilePath
import System.Directory
import System.Process

import Utils


executables = "dist" </> "build"

deploymentDir = "nikki"

nikkiExe = executables </> "nikki" </> "nikki"
coreExe = executables </> "core" </> "core"


main = do
    prepareDeploymentDir
    copy nikkiExe
    copy coreExe
    copy (".." </> "data")
    mapM_ copy =<< getDynamicDependencies

-- | ensure that an empty deploymentDir exists
prepareDeploymentDir = do
    e <- doesDirectoryExist deploymentDir
    when e $
        removeDirectoryRecursive deploymentDir
    createDirectory deploymentDir

-- | return all dynamically linked dependencies for both executables
getDynamicDependencies :: IO [FilePath]
getDynamicDependencies = do
    a <- getDeps nikkiExe
    b <- getDeps coreExe
    return $ nub (a ++ b)

-- | copy the given file to the deploymentDir
copy :: FilePath -> IO ()
copy path = do
    putStrLn ("copying " ++ path)
    isFile <- doesFileExist path
    isDir <- doesDirectoryExist path
    if isFile then
        copyFile path (deploymentDir </> takeFileName path)
      else if isDir then
        copyDirectory path (deploymentDir </> takeFileName path)
      else
        error ("not found: " ++ path)


-- * ldd output parsing

data LDDDep = LDDDep {dep :: FilePath, location :: Maybe FilePath}
  deriving Show

-- | return the dynamically linked dependencies for the given executables
getDeps :: FilePath -> IO [FilePath]
getDeps exe = do
    lddOutput <- readProcess "ldd" [exe] ""
    return $ case parse lddParser ("ldd-output: " ++ lddOutput) lddOutput of
        Left x -> error $ show x
        Right x -> filterWantedDeps x
  where
    -- filter for all the dependency we really want to deploy
    filterWantedDeps :: [LDDDep] -> [FilePath]
    filterWantedDeps = catMaybes . map convert
    convert :: LDDDep -> Maybe FilePath
    convert (LDDDep dep (Just location)) = Just location
    convert (LDDDep dep Nothing) = Nothing

lddParser :: Parsec String () [LDDDep]
lddParser = do
    r <- endBy dep newline
    eof
    return r
  where
    dep = spaces >> (absoluteDep <|> relativeDep)

    absoluteDep = do
        lookAhead (char '/')
        path <- token
        hex
        return $ LDDDep path Nothing

    relativeDep = do
        lookAhead (noneOf ['/'])
        path <- token
        spaces
        string "=>"
        spaces
        loc <- location
        hex
        return $ LDDDep path loc

    location :: Parsec String () (Maybe FilePath)
    location = optionMaybe $ do
        lookAhead $ noneOf ['(']
        token

    -- parses the hex number at the end of each entry
    hex = do
        spaces
        char '('
        many1 alphaNum
        char ')'

    -- parses any string till the next whitespace character
    token :: Parsec String () String
    token = many1 (satisfy (not . isSpace))