// The reverse-proxy configuration the deployment tool writes and reloads into Caddy.
// Side-effect free, so tests can generate the real configuration the deployment tool
// writes without running any deployment command.

export const slots = { blue: 4000, green: 4001 };

export function caddyfile(slot, healthChecked) {
  const healthCheck = healthChecked ? "\t\thealth_uri /health/ready\n" : "";

  return `{
\tadmin 127.0.0.1:2019
\tgrace_period 5m
}

:4100 {
\tbind 127.0.0.1
\treverse_proxy 127.0.0.1:${slots[slot]} {
\t\theader_up X-Forwarded-Proto https
${healthCheck}
\t}
}
`;
}
