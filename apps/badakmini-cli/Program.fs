module Badakmini.Cli.Program

open Badakmini.Cli

[<EntryPoint>]
let main args =
    Cli.invokeWith (CliRuntime.system ()) args
