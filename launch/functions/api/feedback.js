// POST /api/feedback: one tester's answers to the beta survey.
//
// Stored in Supabase's beta_feedback table (supabase/beta_feedback.sql) with
// the same insert-only publishable key as sign-ups (SUPABASE_URL,
// SUPABASE_KEY). The SIGNUPS KV binding, when present, limits each IP to a
// few surveys an hour.

import { EMAIL, json, readJSON, insertRow, underIPLimit } from "../../lib/request.js";

const MAX_BODY_BYTES = 12_000;
const PER_IP_PER_HOUR = 5;

/** Questions answered by picking one option. */
const CHOICES = {
  planned_day: ["yes", "started", "no"],
  used_today: ["often", "once", "no"],
  next_trip: ["yes", "maybe", "no"],
};

/** Free-text answers and how long each may be. */
const TEXTS = {
  city: 80,
  app_version: 40,
  plan_broke: 2000,
  confusing: 2000,
  one_thing: 2000,
};

export async function onRequestPost({ request, env }) {
  const read = await readJSON(request, { maxBytes: MAX_BODY_BYTES, wrongOrigin: "Send the survey from the City Tourist page." });
  if (read.error) return read.error;
  const body = read.body;

  // People never see this field; bots fill every field they find.
  if (body.company) return json({ ok: true });

  const row = {};
  for (const [field, options] of Object.entries(CHOICES)) {
    const value = body[field];
    if (value === undefined || value === null || value === "") continue;
    if (!options.includes(value)) return json({ error: "One of the answers isn't an option on the form." }, 400);
    row[field] = value;
  }

  if (body.leave_by_accuracy !== undefined && body.leave_by_accuracy !== null && body.leave_by_accuracy !== "") {
    const rating = Number(body.leave_by_accuracy);
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      return json({ error: "One of the answers isn't an option on the form." }, 400);
    }
    row.leave_by_accuracy = rating;
  }

  for (const [field, max] of Object.entries(TEXTS)) {
    // Line breaks and tabs stay; other control characters go.
    const text = String(body[field] ?? "").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").trim();
    if (!text) continue;
    if (text.length > max) return json({ error: "One of the answers is too long." }, 400);
    row[field] = text;
  }

  const email = String(body.email ?? "").trim().toLowerCase();
  if (email) {
    if (email.length > 254 || !EMAIL.test(email)) {
      return json({ error: "Check your email address, or leave it blank." }, 400);
    }
    row.email = email;
  }

  const answered = Object.keys(row).filter((k) => k !== "app_version" && k !== "city");
  if (!answered.length) return json({ error: "Answer at least one question." }, 400);

  if (!env.SUPABASE_URL || !env.SUPABASE_KEY) {
    return json({ error: "The survey isn't switched on yet. Try again soon." }, 503);
  }
  if (!(await underIPLimit(env, request, "feedback-ip", PER_IP_PER_HOUR))) {
    return json({ error: "Too many answers from here. Try again in an hour." }, 429);
  }

  const stored = await insertRow(env, "beta_feedback", row);
  if (!stored.ok) return json({ error: "That didn't go through. Try again in a minute." }, 502);
  return json({ ok: true });
}

export function onRequest() {
  return json({ error: "Use POST." }, 405);
}
