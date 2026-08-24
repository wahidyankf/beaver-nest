import { spawn } from "node:child_process";
import readline from "node:readline";

const child = spawn("codex", ["app-server"], {
  stdio: ["pipe", "pipe", "pipe"],
});
const lines = readline.createInterface({ input: child.stdout });
child.stderr.resume();
let settled = false;
let nextId = 1;
let pendingId;
let models = [];

const finish = (result) => {
  if (settled) return;
  settled = true;
  clearTimeout(timeout);
  child.kill();
  process.stdout.write(`${JSON.stringify(result)}\n`);
};

const fail = (message) => {
  if (settled) return;
  settled = true;
  clearTimeout(timeout);
  child.kill();
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
};

const send = (message) => child.stdin.write(`${JSON.stringify(message)}\n`);

const requestModels = (cursor) => {
  pendingId = ++nextId;
  const params = { includeHidden: false, limit: 100 };
  if (cursor) params.cursor = cursor;
  send({ id: pendingId, method: "model/list", params });
};

const timeout = setTimeout(
  () => fail("Codex model discovery timed out."),
  15_000,
);

child.once("error", () => fail("Codex could not be started."));
child.once("exit", (status) => {
  if (!settled) fail(`Codex model discovery exited with status ${status}.`);
});

send({
  id: nextId,
  method: "initialize",
  params: {
    clientInfo: { name: "beaver-nest", version: "0.1.0" },
    capabilities: { experimentalApi: true },
  },
});

for await (const line of lines) {
  let message;

  try {
    message = JSON.parse(line);
  } catch {
    continue;
  }

  if (message.id === 1 && message.result) {
    send({ method: "initialized", params: {} });
    requestModels();
  } else if (message.id === pendingId && message.result) {
    const page = Array.isArray(message.result.data) ? message.result.data : [];
    models = models.concat(
      page.map((model) => ({
        id: model.id,
        display_name: model.displayName,
        default_reasoning_effort: model.defaultReasoningEffort,
        supported_reasoning_efforts: Array.isArray(
          model.supportedReasoningEfforts,
        )
          ? model.supportedReasoningEfforts.map(
              (effort) => effort.reasoningEffort,
            )
          : [],
        is_default: model.isDefault === true,
      })),
    );

    if (message.result.nextCursor) requestModels(message.result.nextCursor);
    else finish(models);
  } else if (message.id && message.error) {
    fail("Codex rejected model discovery.");
  }
}
