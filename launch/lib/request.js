// What the Pages Functions share: reading a small JSON form from this site
// only, talking to Supabase with the insert-only key, and a per-IP limit.

export const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

/**
 * The request's JSON body as an object, or `{ error }` with the response to
 * send instead. Only this site's own pages: anyone can forge `Origin` with
 * curl, but it keeps other pages from posting from people's browsers.
 */
export async function readJSON(request, { maxBytes, wrongOrigin }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return { error: json({ error: wrongOrigin }, 403) };
  }
  if (!(request.headers.get("content-type") || "").includes("application/json")) {
    return { error: json({ error: "Send the form as JSON." }, 415) };
  }
  const raw = await request.text();
  if (raw.length > maxBytes) return { error: json({ error: "That's too long." }, 413) };
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return { error: json({ error: "Send the form as JSON." }, 400) };
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: json({ error: "Send the form as JSON." }, 400) };
  }
  return { body };
}

/** Legacy anon keys are JWTs and go as a bearer token too; new publishable keys don't. */
export function supabaseHeaders(key) {
  const headers = {
    apikey: key,
    "Content-Type": "application/json",
    // Return nothing: the key isn't allowed to read tables back.
    Prefer: "return=minimal",
  };
  if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`;
  return headers;
}

/** Inserts one row; the Response from Supabase. */
export function insertRow(env, table, row) {
  return fetch(`${env.SUPABASE_URL.replace(/\/+$/, "")}/rest/v1/${table}`, {
    method: "POST",
    headers: supabaseHeaders(env.SUPABASE_KEY),
    body: JSON.stringify(row),
  });
}

/**
 * Counts this request against its IP's hourly allowance under `prefix`.
 * False when the allowance is used up. Without a KV binding there's no limit.
 */
export async function underIPLimit(env, request, prefix, perHour) {
  if (!env.SIGNUPS) return true;
  const key = `${prefix}:${request.headers.get("cf-connecting-ip") || "unknown"}`;
  const tries = Number(await env.SIGNUPS.get(key)) || 0;
  if (tries >= perHour) return false;
  await env.SIGNUPS.put(key, String(tries + 1), { expirationTtl: 3600 });
  return true;
}
