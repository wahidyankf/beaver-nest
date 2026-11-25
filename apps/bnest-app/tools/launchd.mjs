import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { slots } from "./caddy-config.mjs";
import {
  output,
  paths,
  repositoryRoot,
  run,
  state,
  writeAtomic,
  fail,
} from "./deployment-support.mjs";

// macOS service adapter: the Caddy and slot LaunchAgents, driven by
// launchctl. The functions below were moved from deployment.mjs unchanged.
const label = "com.bnest.caddy";

export function caddyBinary() {
  try {
    return `${output("brew", ["--prefix", "caddy"])}/bin/caddy`;
  } catch {
    return "/opt/homebrew/bin/caddy";
  }
}

export function ensureCaddy() {
  if (!existsSync(caddyBinary())) run("brew", ["install", "caddy"]);
}

function caddyLaunchAgent() {
  const binary = caddyBinary();
  const plistPath = join(paths.launchAgents, `${label}.plist`);

  return {
    path: plistPath,
    contents: `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array>
    <string>${binary}</string><string>run</string><string>--config</string><string>${paths.config}</string><string>--adapter</string><string>caddyfile</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${join(paths.logs, "caddy.log")}</string>
  <key>StandardErrorPath</key><string>${join(paths.logs, "caddy.error.log")}</string>
</dict></plist>
`,
  };
}

function slotLabel(slot) {
  return `com.bnest.app.${slot}`;
}

function launchAgent(
  slot,
  release,
  runtimeRoot,
  cookieFile,
  secretKeyBaseFile,
  webPushPublicKeyFile,
  webPushPrivateKeyFile,
  webPushSubject,
  productionHost,
  revision,
  logPath,
  errorPath,
) {
  const variables = {
    PATH: process.env.PATH || "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    PHX_SERVER: "true",
    PORT: String(slots[slot]),
    BNEST_STABLE: "true",
    BNEST_RUNTIME_ROOT: runtimeRoot,
    BNEST_REPOSITORY_ROOT: repositoryRoot,
    BNEST_CODEX_WORKING_DIRECTORY: repositoryRoot,
    BNEST_COOKIE_SECURE: "true",
    BNEST_IDENTITY_CUTOVER: "true",
    BNEST_RELEASE_REVISION: revision,
    BNEST_DEPLOY_SLOT: slot,
    PHX_HOST: productionHost,
    RELEASE_DISTRIBUTION: "none",
    RELEASE_COOKIE: readFileSync(cookieFile, "utf8").trim(),
    SECRET_KEY_BASE: readFileSync(secretKeyBaseFile, "utf8").trim(),
    // Deployment passes the existing runtime VAPID values to both slots
    // unconditionally -- `runtime.exs` fails closed on boot when these are
    // absent, in every slot, on every revision.
    BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE: webPushPublicKeyFile,
    BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE: webPushPrivateKeyFile,
    BNEST_WEB_PUSH_SUBJECT: webPushSubject,
  };
  const environment = Object.entries(variables)
    .map(
      ([key, value]) => `<key>${key}</key><string>${escapeXml(value)}</string>`,
    )
    .join("");

  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${slotLabel(slot)}</string>
  <key>ProgramArguments</key><array><string>${release}/bin/bnest_app</string><string>start</string></array>
  <key>EnvironmentVariables</key><dict>${environment}</dict>
  <key>SoftResourceLimits</key><dict><key>NumberOfFiles</key><integer>4096</integer></dict>
  <key>HardResourceLimits</key><dict><key>NumberOfFiles</key><integer>8192</integer></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${logPath}</string><key>StandardErrorPath</key><string>${errorPath}</string>
</dict></plist>
`;
}

export function retireSlot(slot) {
  if (state().activeSlot === slot) fail("Refuse to retire the active slot.");
  spawnSync(
    "launchctl",
    ["bootout", `gui/${process.getuid()}/${slotLabel(slot)}`],
    { stdio: "ignore" },
  );
}

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

export function installCaddyService() {
  const agent = caddyLaunchAgent();
  writeAtomic(agent.path, agent.contents);
  const domain = `gui/${process.getuid()}`;

  const installed = spawnSync("launchctl", ["print", `${domain}/${label}`], {
    stdio: "ignore",
  });
  if (installed.status !== 0) {
    run("launchctl", ["bootstrap", domain, agent.path]);
  } else {
    run(caddyBinary(), [
      "reload",
      "--config",
      paths.config,
      "--adapter",
      "caddyfile",
    ]);
  }
}

export function installSlotService(slot, options) {
  const plistPath = join(paths.launchAgents, `${slotLabel(slot)}.plist`);
  writeAtomic(
    plistPath,
    launchAgent(
      slot,
      options.release,
      options.runtimeRoot,
      options.cookieFile,
      options.secretKeyBaseFile,
      options.webPushPublicKeyFile,
      options.webPushPrivateKeyFile,
      options.webPushSubject,
      options.productionHost,
      options.revision,
      options.logPath,
      options.errorPath,
    ),
  );

  const domain = `gui/${process.getuid()}`;
  spawnSync("launchctl", ["bootout", `${domain}/${slotLabel(slot)}`], {
    stdio: "ignore",
  });
  run("launchctl", ["bootstrap", domain, plistPath]);
}

// ditto exists only on macOS; the Linux adapter uses cp.
export function copyRelease(source, destination) {
  run("ditto", [source, destination]);
}
