// POST /api/signup: emails each beta signup to the owner.
//
// Settings → Variables and Secrets on the Cloudflare Pages project:
//   RESEND_API_KEY  (secret) an API key from resend.com
//   SIGNUP_TO       the address signups are sent to. With Resend's shared
//                   onboarding@resend.dev sender, it must be the Resend
//                   account's own email.
//   SIGNUP_FROM     optional, e.g. "City Tourist <beta@yourdomain.com>" once
//                   a domain is verified with Resend
// Bindings → KV namespace bound as SIGNUPS (recommended): keeps the list,
// stops a repeat signup from emailing twice, and limits each IP address.

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_BODY_BYTES = 2048;
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
  if (!env.RESEND_API_KEY || !env.SIGNUP_TO) {
    return json({ error: "Signups aren't switched on yet. Try again soon." }, 503);
  }

  if (env.SIGNUPS) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const ipKey = `ip:${ip}`;
    const tries = Number(await env.SIGNUPS.get(ipKey)) || 0;
    if (tries >= PER_IP_PER_HOUR) {
      return json({ error: "Too many signups from here. Try again in an hour." }, 429);
    }
    await env.SIGNUPS.put(ipKey, String(tries + 1), { expirationTtl: 3600 });

    if (await env.SIGNUPS.get(`email:${email}`)) return json({ ok: true });
    await env.SIGNUPS.put(`email:${email}`, JSON.stringify({ at: new Date().toISOString() }));
  }

  const sent = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.SIGNUP_FROM || "City Tourist <onboarding@resend.dev>",
      to: [env.SIGNUP_TO],
      reply_to: email,
      subject: `Beta signup: ${email}`,
      text: `${email} wants the City Tourist beta.\n\nSigned up ${new Date().toUTCString()}.\nReply to this email to write to them.`,
    }),
  });

  if (!sent.ok) {
    // Let them try again rather than be marked as done.
    if (env.SIGNUPS) await env.SIGNUPS.delete(`email:${email}`);
    return json({ error: "That didn't go through. Try again in a minute." }, 502);
  }
  return json({ ok: true });
}

export function onRequest() {
  return json({ error: "Use POST." }, 405);
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
