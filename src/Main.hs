{-
 - Copyright 2011-2014 Per Magnus Therning
 -
 - Licensed under the Apache License, Version 2.0 (the "License");
 - you may not use this file except in compliance with the License.
 - You may obtain a copy of the License at
 -
 -     http://www.apache.org/licenses/LICENSE-2.0
 -
 - Unless required by applicable law or agreed to in writing, software
 - distributed under the License is distributed on an "AS IS" BASIS,
 - WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 - See the License for the specific language governing permissions and
 - limitations under the License.
 -}

module Main where

-- {{{1 imports
import Add
import BuildPkgs
import BumpPkgs
import Sync
import Versions
import ListPkgs
import Updates
import Util.Misc
import PkgBuild
import ConvertDB
import Remove
import Extract

import Paths_cblrepo

import Distribution.Text
import System.Directory
import Options.Applicative as OA

-- -- {{{1 command line arguments
argAppDir, argDbFile :: Parser String
argAppDir = strOption (long "appdir" <> value "" <> help "Path to application data directory")
argDbFile = strOption (long "db" <> value "cblrepo.db" <> help "Path to package database")
argDryRun :: Parser Bool
argDryRun = switch (short 'n' <> help "Make no changes, (dry run)")

cmdAddPkgOpts :: Parser Cmds
cmdAddPkgOpts = CmdAdd
    <$> strOption (long "patchdir" <> value "patches" <> help "Location of patches (patches)")
    <*> option ghcVersionArgReader (long "ghc-version" <> value ghcDefVersion <> help "GHC version to use")
    <*> many (option ghcPkgArgReader (short 'g' <> long "ghc-pkg" <> metavar "PKG,VER" <> help "GHC base package (multiple)"))
    <*> many (option distroPkgArgReader (short 'd' <> long "distro-pkg" <> metavar "PKG,VER,REL" <> help "Distro package (multiple)"))
    <*> many (option strCblFileArgReader (short 'f' <> long "cbl-file" <> metavar "FILE[:flag,-flag]" <> help "CABAL file (multiple)"))
    <*> many (argument strCblPkgArgReader (metavar "PKGNAME,VERSION[:flag,-flag] ..."))

cmdAddPkgCmd = command "add" (info (helper <*> cmdAddPkgOpts)
    (fullDesc <> progDesc "Add a package to the database"))

cmdBumpPkgsOpts = CmdBumpPkgs
    <$> switch (long "inclusive" <> help "Include the listed packages")
    <*> some (strArgument (metavar "PKGNAME ..."))
cmdBumpPkgsCmd = command "bump" (info (helper <*> cmdBumpPkgsOpts)
    (fullDesc <> progDesc "Bump packages that need it after updating the named packages"))

cmdBuildPkgsOpts = CmdBuildPkgs
    <$> some (strArgument (metavar "PKGNAME ..."))
cmdBuildPkgsCmd = command "build" (info (helper <*> cmdBuildPkgsOpts)
    (fullDesc <> progDesc "Re-order packages into a good build order"))

cmdSyncOpts = CmdSync <$> switch (internal <> hidden)
cmdSyncCmd = command "sync" (info (helper <*> cmdSyncOpts)
    (fullDesc <> progDesc "Update the index"))

cmdVersionsOpts = CmdVersions
    <$> switch (short 'l' <> long "latest" <> help "List only the latest version of packages")
    <*> some (strArgument (metavar "PKGNAME ..."))
cmdVersionsCmd = command "versions" (info (helper <*> cmdVersionsOpts)
    (fullDesc <> progDesc "List available versions of packages"))

cmdUpdatesOpts = CmdUpdates
    <$> switch (short 's' <> help "A shorter output suitable for scripting")
cmdUpdatesCmd = command "updates" (info (helper <*> cmdUpdatesOpts)
    (fullDesc <> progDesc "Check for available updates"))

cmdListPkgsOpts = CmdListPkgs
    <$> switch (short 'g' <> long "ghc" <> help "List ghc packages")
    <*> switch (short 'd' <> long "distro" <> help "List distro packages")
    <*> switch (long "no-repo" <> help "Do not list repo packages")
    <*> switch (long "hackage" <> help "List in hackage format")
    <*> many (argument str (metavar "PKGNAME ..."))
cmdListPkgsCmd = command "list" (info (helper <*> cmdListPkgsOpts)
    (fullDesc <> progDesc "List packages in repo"))

cmdPkgBuildOpts = CmdPkgBuild
    <$> option ghcVersionArgReader (long "ghc-version" <> value ghcDefVersion <> help "GHC version to use in PKGBUILD")
    <*> option auto (long "ghc-release" <> value 1 <> help "GHC release to use in PKGBUILD")
    <*> strOption (long "patchdir" <> value "patches" <> help "Location of patches (patches)")
    <*> some (strArgument (metavar "PKGNAME ..."))
cmdPkgBuildCmd = command "pkgbuild" (info (helper <*> cmdPkgBuildOpts)
    (fullDesc <> progDesc "Create PKGBUILD other files necessary for an Arch package"))

cmdConvertDbOpts = CmdConvertDb
    <$> strOption (short 'i' <> long "indb" <> value "cblrepo.db" <> help "Old database")
    <*> strOption (short 'o' <> long "outdb" <> value "new-cblrepo.db" <> help "New database")
cmdConvertDbCmd = command "convertdb" (info (helper <*> cmdConvertDbOpts)
    (fullDesc <> progDesc "Convert an old database to the new format"))

cmdRemovePkgOpts = CmdRemovePkg
    <$> some (strArgument (metavar "PKGNAME ..."))
cmdRemovePkgCmd = command "rm" (info (helper <*> cmdRemovePkgOpts)
    (fullDesc <> progDesc "Remove packages"))

cmdExtractOpts = CmdExtract
    <$> many (argument pkgNVersionArgReader (metavar "PKGNAME,VERSION"))
cmdExtractCmd = command "extract" (info (helper <*> cmdExtractOpts) (fullDesc <> progDesc "Extract Cabal file from index"))

argParser = info (helper <*> opts) (fullDesc <> header (progName ++ " v" ++ display version) <> progDesc "Maintain a datatbase of dependencies of CABAL packages")
    where
        opts = Opts <$> argAppDir <*> argDbFile <*> argDryRun
            <*> subparser ( cmdAddPkgCmd
                <> cmdBumpPkgsCmd <> cmdBuildPkgsCmd <> cmdSyncCmd <> cmdVersionsCmd <> cmdUpdatesCmd
                <> cmdListPkgsCmd <> cmdPkgBuildCmd <> cmdConvertDbCmd <> cmdRemovePkgCmd <> cmdExtractCmd
                )

-- {{{1 main
main :: IO ()
main = do
    defAppDir <- getAppUserDataDirectory progName
    execParser argParser >>= \ o -> do
        let aD = if null (appDir o) then defAppDir else appDir o
        let o' = o { appDir = aD }
        createDirectoryIfMissing True aD
        case optsCmd o' of
            CmdAdd {} -> runCommand o' add
            CmdBuildPkgs {} -> runCommand o' buildPkgs
            CmdBumpPkgs {} -> runCommand o' bumpPkgs
            CmdSync {} -> runCommand o' sync
            CmdVersions {} -> runCommand o' versions
            CmdListPkgs {} -> runCommand o' listPkgs
            CmdUpdates {} -> runCommand o' updates
            CmdPkgBuild {} -> runCommand o' pkgBuild
            CmdConvertDb {} -> runCommand o' convertDb
            CmdRemovePkg {} -> runCommand o' remove
            CmdExtract {} -> runCommand o' extract
