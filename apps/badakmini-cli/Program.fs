module Badakmini.Cli.Program

open System
open System.IO
open Badakmini.Cli

let private usage = "Usage: badakmini-cli [repository-root]"

let private checkRepository root =
    if not (Directory.Exists root) then
        eprintfn "badakmini-cli: repository root does not exist: %s" root
        2
    else
        try
            let files = Governance.scanRepository root
            let violations = Governance.findViolations files

            if List.isEmpty violations then
                printfn
                    "Checked %d Markdown file(s); all are within the %d-word limit."
                    files.Length
                    Governance.wordLimit

                0
            else
                for violation in violations do
                    eprintfn
                        "%s: %d words (maximum %d)"
                        violation.Path
                        violation.WordCount
                        Governance.wordLimit

                eprintfn
                    "Found %d Markdown file(s) over the %d-word limit."
                    violations.Length
                    Governance.wordLimit

                1
        with ex ->
            eprintfn "badakmini-cli: %s" ex.Message
            2

[<EntryPoint>]
let main args =
    match args with
    | [||] -> checkRepository (Directory.GetCurrentDirectory())
    | [| "-h" |]
    | [| "--help" |] ->
        printfn "%s" usage
        0
    | [| root |] -> checkRepository (Path.GetFullPath root)
    | _ ->
        eprintfn "%s" usage
        2
