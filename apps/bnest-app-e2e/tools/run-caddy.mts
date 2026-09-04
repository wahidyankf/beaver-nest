import { spawn } from "node:child_process";

const publicPort = requiredPort("BNEST_E2E_PORT");
const backendPort = requiredPort("BNEST_E2E_BACKEND_PORT");
const adminPort = requiredPort("BNEST_E2E_CADDY_ADMIN_PORT");
const binary = process.env["BNEST_E2E_CADDY_BIN"] ?? "caddy";

const child = spawn(binary, ["run", "--config", "-", "--adapter", "caddyfile"], {
  stdio: ["pipe", "inherit", "inherit"],
});

child.stdin.end(caddyfile(publicPort, backendPort, adminPort));

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => child.kill(signal));
}

child.once("error", (error) => {
  throw error;
});

child.once("exit", (code, signal) => {
  if (signal === null) process.exit(code ?? 1);
  else process.kill(process.pid, signal);
});

function requiredPort(name: string): number {
  const value = Number(process.env[name]);
  if (!Number.isInteger(value) || value < 1 || value > 65_535) {
    throw new Error(`${name} must be a valid TCP port`);
  }
  return value;
}

function caddyfile(
  listenerPort: number,
  upstreamPort: number,
  controlPort: number,
): string {
  return `{
  admin 127.0.0.1:${controlPort}
  auto_https off
}

http://127.0.0.1:${listenerPort}, http://localhost:${listenerPort} {
  reverse_proxy 127.0.0.1:${upstreamPort} {
    stream_close_delay 1s
  }
}
`;
}
