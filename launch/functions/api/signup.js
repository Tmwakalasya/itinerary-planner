// POST /api/signup: adds someone to the beta list.
//
// Settings → Variables and Secrets on the Cloudflare Pages project. At least
// one of the two destinations has to be set up:
//
// Supabase, where the list lives (run supabase/beta_signups.sql first):
//   SUPABASE_URL    https://<project>.supabase.co
//   SUPABASE_KEY    (secret) the project's publishable (anon) key. The table's
//                   policy lets it insert an email and a name, nothing else.
//
// Resend, an email to you for each sign-up:
//   RESEND_API_KEY  (secret) an API key from resend.com
//   SIGNUP_TO       where sign-ups are sent. With Resend's shared
//                   onboarding@resend.dev sender, it must be the Resend
//                   account's own email.
//   SIGNUP_FROM     optional, e.g. "City Tourist <beta@yourdomain.com>" once
//                   a domain is verified with Resend
//
// Bindings → KV namespace bound as SIGNUPS (recommended): limits each IP
// address to a few sign-ups an hour and stops repeats emailing you twice.

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_BODY_BYTES = 2048;
const MAX_NAME = 80;
const PER_IP_PER_HOUR = 5;

export async function onRequestPost({ request, env }) {
  // Only this site's own form. Anyone can forge the header with curl, but it
  // keeps other pages from posting into the list from people's browsers.
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return json({ error: "Sign up from the City Tourist page." }, 403);
  }
  if (!(request.headers.get("content-type") || "").includes("application/json")) {
    return json({ error: "Send the form as JSON." }, 415);
  }

  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "That's too long." }, 413);
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "Send the form as JSON." }, 400);
  }
  if (!body || typeof body !== "object") return json({ error: "Send the form as JSON." }, 400);

  // People never see this field; bots fill every field they find.
  if (body.company) return json({ ok: true });

  const email = String(body.email || "").trim().toLowerCase();
  if (email.length > 254 || !EMAIL.test(email)) {
    return json({ error: "Check your email address. It should look like you@email.com." }, 400);
  }
  // Control characters out, so a name can't break a header or a line.
  const name = String(body.name || "").replace(/[\u0000-\u001f\u007f]/g, "").trim();
  if (name.length > MAX_NAME) return json({ error: "That name is too long." }, 400);

  const canStore = Boolean(env.SUPABASE_URL && env.SUPABASE_KEY);
  const canEmail = Boolean(env.RESEND_API_KEY && env.SIGNUP_TO);
  if (!canStore && !canEmail) {
    return json({ error: "Signups aren't switched on yet. Try again soon." }, 503);
  }

  let isRepeat = false;
  if (env.SIGNUPS) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const ipKey = `ip:${ip}`;
    const tries = Number(await env.SIGNUPS.get(ipKey)) || 0;
    if (tries >= PER_IP_PER_HOUR) {
      return json({ error: "Too many signups from here. Try again in an hour." }, 429);
    }
    await env.SIGNUPS.put(ipKey, String(tries + 1), { expirationTtl: 3600 });
    isRepeat = Boolean(await env.SIGNUPS.get(`email:${email}`));
  }

  if (canStore) {
    const stored = await fetch(`${env.SUPABASE_URL.replace(/\/+$/, "")}/rest/v1/beta_signups`, {
      method: "POST",
      headers: supabaseHeaders(env.SUPABASE_KEY),
      body: JSON.stringify({ email, name: name || null }),
    });
    // 409 is the unique email: they're already on the list, which is fine.
    if (stored.status === 409) isRepeat = true;
    else if (!stored.ok) return json({ error: "That didn't go through. Try again in a minute." }, 502);
  }

  if (canEmail && !isRepeat) {
    const sent = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: env.SIGNUP_FROM || "City Tourist <onboarding@resend.dev>",
        to: [env.SIGNUP_TO],
        reply_to: email,
        subject: `Beta signup: ${name ? `${name} (${email})` : email}`,
        text: `${name || "Someone"} <${email}> wants the City Tourist beta.\n\nSigned up ${new Date().toUTCString()}.\nReply to this email to write to them.`,
      }),
    });
    // With the list in Supabase, a missed notification isn't a failed sign-up.
    if (!sent.ok && !canStore) return json({ error: "That didn't go through. Try again in a minute." }, 502);
  }

  if (env.SIGNUPS && !isRepeat) {
    await env.SIGNUPS.put(`email:${email}`, "1");
  }
  return json({ ok: true });
}

export function onRequest() {
  return json({ error: "Use POST." }, 405);
}

/** Legacy anon keys are JWTs and go as a bearer token too; new publishable keys don't. */
function supabaseHeaders(key) {
  const headers = {
    apikey: key,
    "Content-Type": "application/json",
    // Return nothing: the key isn't allowed to read the table back.
    Prefer: "return=minimal",
  };
  if (key.startsWith("eyJ")) headers.Authorization = `Bearer ${key}`;
  return headers;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
