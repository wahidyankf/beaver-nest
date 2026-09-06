namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open global.Xunit

type IntegrationPolicyTests() =
    // Badakmini is a network-free governance system by design; this asserts that product
    // invariant over its production sources. It is not the integration-layer boundary,
    // which permits a loopback socket the test owns.
    [<Fact>]
    member _.``badakmini runtime has no network dependency``() =
        let forbidden =
            [ "System.Net"
              "HttpClient"
              "WebRequest"
              "TcpClient"
              "UdpClient"
              "Socket("
              "localhost"
              "127.0.0.1"
              "http://"
              "https://"
              "curl "
              "wget " ]

        let sourcePaths =
            [ "IntegrationDriver.fs"
              "IntegrationApplicationTests.fs"
              "../contract/CliContractTests.fs"
              "../../Runtime.fs"
              "../../HarnessContract.fs"
              "../../Governance.fs"
              "../../Cli.fs"
              "../../Program.fs" ]
            |> List.map (fun path -> Path.GetFullPath(Path.Combine(__SOURCE_DIRECTORY__, path)))

        Assert.All(
            sourcePaths,
            fun sourcePath ->
                let source = File.ReadAllText sourcePath

                Assert.All(
                    forbidden,
                    fun token -> Assert.DoesNotContain(token, source, StringComparison.OrdinalIgnoreCase)
                )
        )
