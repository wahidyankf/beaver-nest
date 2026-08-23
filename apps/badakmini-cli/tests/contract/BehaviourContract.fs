namespace Badakmini.Cli.BehaviourTests

open System

type ViolationView =
    { Kind: string
      Path: string
      RelatedPath: string option
      Target: string option
      WordCount: int option
      Line: int option
      Diagnostic: string }

type CommandResult =
    { ExitCode: int
      StandardOutput: string
      StandardError: string }

type IBehaviourDriver =
    inherit IDisposable

    abstract Root: string
    abstract Write: relativePath: string * content: string -> unit
    abstract Lock: relativePath: string -> unit
    abstract CountWords: relativePath: string -> int
    abstract ScanGovernedMarkdown: unit -> string list
    abstract FindWordLimitViolations: unit -> string list * ViolationView list
    abstract InspectWordBudget: unit -> string list * ViolationView list
    abstract InspectDirectoryMaps: unit -> int * ViolationView list
    abstract InspectDirectoryMapsAtInvalidLocation: location: string -> bool
    abstract InspectMermaidAccessibility: unit -> int * ViolationView list
    abstract RunValidator: validator: string -> CommandResult
    abstract RunDirectoryMapValidator: directory: string -> CommandResult
    abstract InvokeCli: arguments: string array -> CommandResult
    abstract InvokeCliFromRepository: arguments: string array -> CommandResult

type ScenarioContext(driver: IBehaviourDriver) =
    let mutable markdownPaths: string list = []
    let mutable violations: ViolationView list = []
    let mutable directoryCount: int option = None
    let mutable diagramCount: int option = None
    let mutable wordCount: int option = None
    let mutable argumentErrorRaised = false
    let mutable commandResult: CommandResult option = None

    member _.Driver = driver

    member _.MarkdownPaths
        with get () = markdownPaths
        and set value = markdownPaths <- value

    member _.Violations
        with get () = violations
        and set value = violations <- value

    member _.DirectoryCount
        with get () = directoryCount
        and set value = directoryCount <- value

    member _.DiagramCount
        with get () = diagramCount
        and set value = diagramCount <- value

    member _.WordCount
        with get () = wordCount
        and set value = wordCount <- value

    member _.ArgumentErrorRaised
        with get () = argumentErrorRaised
        and set value = argumentErrorRaised <- value

    member _.CommandResult
        with get () = commandResult
        and set value = commandResult <- value

    interface IDisposable with
        member _.Dispose() = driver.Dispose()
