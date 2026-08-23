namespace Badakmini.Cli

open System
open System.IO

type RepositoryFileSystem =
    { FileExists: string -> bool
      DirectoryExists: string -> bool
      ReadAllText: string -> string
      EnumerateFiles: string -> string seq
      EnumerateDirectories: string -> string seq
      EnumerateFileSystemEntries: string -> string seq
      GetAttributes: string -> FileAttributes
      CurrentDirectory: unit -> string }

module RepositoryFileSystem =
    let system =
        { FileExists = File.Exists
          DirectoryExists = Directory.Exists
          ReadAllText = File.ReadAllText
          EnumerateFiles = Directory.EnumerateFiles
          EnumerateDirectories = Directory.EnumerateDirectories
          EnumerateFileSystemEntries = Directory.EnumerateFileSystemEntries
          GetAttributes = File.GetAttributes
          CurrentDirectory = Directory.GetCurrentDirectory }

type CliRuntime =
    { FileSystem: RepositoryFileSystem
      Output: TextWriter
      Error: TextWriter }

module CliRuntime =
    let system () =
        { FileSystem = RepositoryFileSystem.system
          Output = Console.Out
          Error = Console.Error }
