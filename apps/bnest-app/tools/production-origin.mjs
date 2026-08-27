export function normalizeProductionOrigin(value) {
  let origin;
  try {
    origin = new URL(value);
  } catch {
    throw new Error("Production origin must be a valid HTTPS origin");
  }
  if (
    origin.protocol !== "https:" ||
    origin.username ||
    origin.password ||
    origin.pathname !== "/" ||
    origin.search ||
    origin.hash
  )
    throw new Error("Production origin must be a bare HTTPS origin");
  return { host: origin.hostname, origin: origin.origin };
}
