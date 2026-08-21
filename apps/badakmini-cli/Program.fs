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
            let inspection = Governance.inspectRepository root

            if List.isEmpty inspection.Violations then
                printfn
                    "Checked %d governed Markdown file(s), %d governance directory map(s), and %d compatible Mermaid diagram(s); all governance checks passed."
                    inspection.MarkdownFiles.Length
                    inspection.GovernanceDirectoryCount
                    inspection.MermaidDiagramCount

                0
            else
                for violation in inspection.Violations do
                    eprintfn "%s" (Governance.formatViolation violation)

                eprintfn "Found %d governance violation(s)." inspection.Violations.Length

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
