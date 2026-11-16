defmodule BnestApp.CodexChat.ChatInstructionsTest do
  @moduledoc """
  Contract test for the Codex developer instruction in `priv/codex/chat_instructions.mjs`.

  It starts the CLI that `@openai/codex-sdk` runs, with `developer_instructions` set the way the SDK sets it, and
  reads the prompt that the CLI would send to the model. It makes no model call and writes only to a temporary
  `CODEX_HOME`, so the real `~/.codex` is never read or changed. It fails when an SDK or CLI upgrade stops
  delivering the instruction verbatim.
  """
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.CodexPortSession
  alias BnestAppWeb.ChatMarkdown

  @workspace Path.expand("../../../../../..", __DIR__)
  @instructions_module Path.join(@workspace, "apps/bnest-app/priv/codex/chat_instructions.mjs")
  # The npm entry point of the pinned `@openai/codex` package. It starts the native binary the SDK runs.
  @codex_entry Path.join(@workspace, "node_modules/@openai/codex/bin/codex.js")
  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  test "the developer instruction reaches the model as a verbatim developer message" do
    # A checkout without `npm ci` fails here, loudly, rather than skipping the contract.
    assert File.exists?(@codex_entry),
           "the pinned Codex CLI is not installed at #{@codex_entry}; run npm ci first"

    {instructions, override} = load_instruction()
    codex_home = temporary_codex_home()

    {output, status} =
      System.cmd(
        node!(),
        [@codex_entry, "debug", "prompt-input", "-c", override, "Contract probe"],
        env: [{"CODEX_HOME", codex_home}, {"HOME", codex_home}],
        stderr_to_stdout: false
      )

    assert status == 0, "codex debug prompt-input failed: #{output}"

    developer_texts =
      output
      |> Jason.decode!()
      |> Enum.filter(&match?(%{"role" => "developer"}, &1))
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.filter(&match?(%{"type" => "input_text"}, &1))
      |> Enum.map(& &1["text"])

    assert instructions in developer_texts
  end

  # The runner must pass the instruction to the SDK constructor as `config`, the way the SDK sends
  # it to the CLI. A stub SDK in a temporary directory records the constructor options, so the test
  # proves the wiring without a model call and without the real CLI.
  test "the runner passes the developer instruction to the Codex constructor as config" do
    {instructions, _override} = load_instruction()
    workspace = temporary_directory("bnest-codex-runner-stub")
    record = Path.join(workspace, "constructor.json")
    sdk_directory = Path.join(workspace, "node_modules/@openai/codex-sdk")

    File.mkdir_p!(Path.join(sdk_directory, "dist"))
    File.write!(Path.join(sdk_directory, "package.json"), ~s({"type": "module"}))
    File.write!(Path.join(sdk_directory, "dist/index.js"), stub_sdk())

    probe = """
    process.stdin.push(null);
    process.argv.splice(2, 0, #{inspect(workspace)}, "gpt-6.1-terra", "medium", "", "read-only");
    await import(process.argv[1]);
    """

    {output, status} =
      System.cmd(
        node!(),
        ["--input-type=module", "--eval", probe, CodexPortSession.bundled_runner()],
        env: [{"BNEST_STUB_RECORD", record}],
        stderr_to_stdout: true
      )

    assert status == 0, "the runner failed against the stub SDK: #{output}"

    assert %{"config" => %{"developer_instructions" => ^instructions}} =
             record |> File.read!() |> Jason.decode!()
  end

  # The runner must forward the system Codex binary path (argv index 7, after working
  # directory, model, effort, thread and sandbox) to the SDK constructor as
  # `codexPathOverride`, so a real turn runs against a CLI that knows the current models.
  # Omitting it leaves the override unset and the SDK uses its bundled binary.
  test "the runner forwards the system Codex path as codexPathOverride" do
    workspace = temporary_directory("bnest-codex-runner-stub")
    record = Path.join(workspace, "constructor.json")
    sdk_directory = Path.join(workspace, "node_modules/@openai/codex-sdk")

    File.mkdir_p!(Path.join(sdk_directory, "dist"))
    File.write!(Path.join(sdk_directory, "package.json"), ~s({"type": "module"}))
    File.write!(Path.join(sdk_directory, "dist/index.js"), stub_sdk())

    run_runner = fn extra_argv ->
      probe = """
      process.stdin.push(null);
      process.argv.splice(2, 0, #{inspect(workspace)}, "gpt-6.1-terra", "medium", "", "read-only"#{extra_argv});
      await import(process.argv[1]);
      """

      {output, status} =
        System.cmd(
          node!(),
          ["--input-type=module", "--eval", probe, CodexPortSession.bundled_runner()],
          env: [{"BNEST_STUB_RECORD", record}],
          stderr_to_stdout: true
        )

      assert status == 0, "the runner failed against the stub SDK: #{output}"
      record |> File.read!() |> Jason.decode!()
    end

    assert %{"codexPathOverride" => "/usr/bin/codex"} =
             run_runner.(~c', "/usr/bin/codex"')

    decoded = run_runner.("")
    assert %{"config" => _config} = decoded
    refute Map.has_key?(decoded, "codexPathOverride")
  end

  # ADR 003, Decision 4: repository raster images and https images are shown; an SVG at a data: address, absolute
  # paths and http addresses are not; no repository text, secret or visitor word goes into an image address; a large
  # image is a link.
  test "the instruction allows repository raster images and https images, and refuses the rest" do
    {text, _override} = load_instruction()

    assert text =~ "Markdown"
    assert text =~ "Never write raw HTML"
    assert text =~ "png, jpg, jpeg, gif or webp file that exists in this repository"
    assert text =~ "Check that a repository file exists before you point to it"
    assert text =~ "a public image at an https:// address"
    assert text =~ "Prefer png, jpg, jpeg, gif or webp"
    assert text =~ "Never use a data: address for SVG"
    assert text =~ "An SVG image at an https:// address is allowed, but some hosts may block it"
    assert text =~ "Never use absolute paths or http:// addresses"
    assert text =~ @logo
    assert File.regular?(Path.join(@workspace, @logo))
  end

  # ADR 007, Decision 3: the paragraph that tells the model to place a `codex-image:`
  # reference where each generated image belongs.
  test "the instruction tells the model to show each generated image with a codex-image: reference" do
    {text, _override} = load_instruction()

    assert text =~
             "When you generate an image, show it where it belongs in the answer with ![alt](codex-image:<dir>/<file>)"

    assert text =~ "using the last two segments of the saved path"

    assert text =~
             "codex-image:01a1caeb-9f2c-4d3e-8a1b-2c3d4e5f6071/exec-2b5e6589-1111-2222-3333-444455556666.png"

    assert text =~ "Write one reference per image, in place, in the middle of the text"
    assert text =~ "Never write absolute paths, ~/.codex paths, or file:// addresses"
  end

  test "the instruction forbids putting repository text, secrets or the user's words in an image address" do
    {text, _override} = load_instruction()

    assert text =~
             "Never put text from this repository, secrets, or the user's words into an image address"
  end

  test "the instruction suggests a link around a large image" do
    {text, _override} = load_instruction()

    assert text =~
             "If a large image should open at full size, write it as a link around the image"

    assert text =~ "[![alt](address)](address)"
  end

  # ADR 004, Decision 7: a mermaid fence is drawn as a diagram. The text names the types the server accepts and
  # the limits it enforces, so the model writes what the page can show.
  test "the instruction asks for a mermaid fence drawn as a diagram, of the types the server accepts" do
    {text, _override} = load_instruction()

    assert text =~ "A fenced code block tagged mermaid is drawn as a diagram"

    for type_line <- [
          "flowchart TD",
          "flowchart LR",
          "sequenceDiagram",
          "classDiagram",
          "stateDiagram-v2",
          "erDiagram",
          "pie",
          "gantt"
        ] do
      assert text =~ type_line, "the diagram instruction does not name #{type_line}"
    end
  end

  # The numbers in the text are the caps the server enforces (ChatMarkdown.diagram_limits/0) and the edge cap the
  # browser enforces (LIMITS.maxEdges in diagram_limits.js). A change to either must change this text too.
  test "the instruction states the diagram limits the server and the browser enforce" do
    {text, _override} = load_instruction()
    limits = ChatMarkdown.diagram_limits()

    assert text =~ "at most #{limits.max_source_bytes} bytes"
    assert text =~ "#{limits.max_lines} lines"
    assert text =~ "at most #{limits.max_per_message} diagrams in a reply"
    assert text =~ "#{max_edges_from_browser()} edges"
  end

  test "the instruction forbids HTML, click and link lines, directives and front matter in a diagram" do
    {text, _override} = load_instruction()

    assert text =~
             "Never use HTML, click or link lines, %%{init}%% directives or --- front matter inside a diagram"
  end

  test "the instruction asks for one sentence that describes every diagram" do
    {text, _override} = load_instruction()

    assert text =~ "Always add one sentence that describes the diagram"
    assert text =~ "because the diagram may not be shown"
  end

  # The browser's edge cap is the one number that is not a server cap. It is read from its source so this test and
  # the browser cannot drift apart.
  defp max_edges_from_browser do
    source =
      File.read!(Path.join(@workspace, "apps/bnest-app/assets/js/diagrams/diagram_limits.js"))

    [_whole, edges] = Regex.run(~r/maxEdges:\s*(\d+)/u, source)
    edges
  end

  # Loads the module with the same Node the chat runner uses. The `--config` value is built the way the SDK builds
  # it for `config: { developer_instructions: text }`: `key=` followed by the JSON string of the text.
  defp load_instruction do
    script = """
    import { pathToFileURL } from "node:url";
    const { developerInstructions } = await import(pathToFileURL(process.argv[1]).href);
    process.stdout.write(JSON.stringify({
      text: developerInstructions,
      override: `developer_instructions=${JSON.stringify(developerInstructions)}`,
    }));
    """

    {output, status} =
      System.cmd(node!(), ["--input-type=module", "-e", script, @instructions_module],
        stderr_to_stdout: true
      )

    assert status == 0, "could not load the developer instruction: #{output}"

    # Node may print warnings before the JSON line, so only the last line is the payload.
    %{"text" => text, "override" => override} =
      output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

    {text, override}
  end

  defp temporary_codex_home, do: temporary_directory("bnest-codex-contract")

  defp temporary_directory(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  # Records the options the runner gives the constructor, then ends the turn stream at once.
  defp stub_sdk do
    """
    import { writeFileSync } from "node:fs";

    export class Codex {
      constructor(options) {
        writeFileSync(process.env.BNEST_STUB_RECORD, JSON.stringify(options ?? {}));
      }

      startThread() {
        return { runStreamed: async () => ({ events: (async function* () {})() }) };
      }

      resumeThread() {
        return this.startThread();
      }
    }
    """
  end

  defp node! do
    System.find_executable("node") || raise "node is required to run the Codex contract test"
  end
end
