const models = [
  ["gpt-5.6-sol", "GPT-5.6-Sol", "low", true],
  ["gpt-5.6-terra", "GPT-5.6-Terra", "medium", false],
  ["gpt-5.6-luna", "GPT-5.6-Luna", "medium", false],
  ["gpt-5.5", "GPT-5.5", "medium", false],
  ["gpt-5.4", "GPT-5.4", "medium", false],
  ["gpt-5.4-mini", "GPT-5.4-Mini", "medium", false],
  ["gpt-5.3-codex-spark", "GPT-5.3-Codex-Spark", "high", false],
].map(([id, display_name, default_reasoning_effort, is_default]) => ({
  id,
  display_name,
  default_reasoning_effort,
  supported_reasoning_efforts: [
    "low",
    "medium",
    "high",
    "xhigh",
    "max",
    "ultra",
  ],
  is_default,
}));

process.stdout.write(`${JSON.stringify(models)}\n`);
