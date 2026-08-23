namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open global.Xunit
open Badakmini.Cli

type IntegrationApplicationTests() =
    [<Fact>]
    member _.``program entry point uses the concrete system runtime``() =
        let originalOutput = Console.Out
        let originalError = Console.Error
        use output = new StringWriter()
        use error = new StringWriter()

        try
            Console.SetOut output
            Console.SetError error
            Assert.Equal(0, Program.main [| "--help" |])
            Assert.Contains("Validate repository governance", output.ToString())
        finally
            Console.SetOut originalOutput
            Console.SetError originalError
