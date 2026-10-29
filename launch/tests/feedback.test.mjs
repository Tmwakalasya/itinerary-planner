// node --test 'launch/tests/*.test.mjs'
// The survey function against a stubbed fetch and an in-memory KV.
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { onRequestPost, onRequest } from "../functions/api/feedback.js";

const SITE = "https://citytourist.pages.dev";
let calls;

beforeEach(() => {
  calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init, body: init.body ? JSON.parse(init.body) : null });
    return (globalThis.fetch.respond || (() => new Response(null, { status: 201 })))(String(url));
  };
  globalThis.fetch.respond = null;
});

const env = () => ({ SUPABASE_URL: "https://abc.supabase.co", SUPABASE_KEY: "sb_publishable_test" });

function kv() {
  const store = new Map();
  return { get: async (k) => store.get(k) ?? null, put: async (k, v) => { store.set(k, v); }, delete: async (k) => { store.delete(k); } };
}

async function call(body, environment = env(), { origin = SITE, ip = "203.0.113.9" } = {}) {
  const request = new Request(`${SITE}/api/feedback`, {
    method: "POST",
    headers: { "content-type": "application/json", origin, "cf-connecting-ip": ip },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  const response = await onRequestPost({ request, env: environment });
  return { status: response.status, body: await response.json() };
}

const full = {
  app_version: "1.0 (2)",
  city: "Lisbon",
  planned_day: "yes",
  used_today: "often",
  leave_by_accuracy: 4,
  plan_broke: "The castle was shut on Monday.\nIt said so, though.",
  confusing: "",
  next_trip: "maybe",
  one_thing: "Let me share a trip.",
  email: " Ana@Example.com ",
};

test("a full set of answers is stored, with the email lowercased and blanks left out", async () => {
  const result = await call(full);
  assert.equal(result.status, 200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://abc.supabase.co/rest/v1/beta_feedback");
  assert.deepEqual(calls[0].body, {
    app_version: "1.0 (2)",
    city: "Lisbon",
    planned_day: "yes",
    used_today: "often",
    leave_by_accuracy: 4,
    plan_broke: "The castle was shut on Monday.\nIt said so, though.",
    next_trip: "maybe",
    one_thing: "Let me share a trip.",
    email: "ana@example.com",
  });
  assert.equal(calls[0].init.headers.Prefer, "return=minimal");
});

test("one answer is enough, but the city and version alone aren't", async () => {
  assert.equal((await call({ used_today: "no" })).status, 200);
  assert.equal((await call({ city: "Lisbon", app_version: "1.0 (2)" })).status, 400);
  assert.equal((await call({})).status, 400);
  assert.equal(calls.length, 1);
});

test("only the form's own options and ratings get through", async () => {
  for (const bad of [{ used_today: "sometimes" }, { next_trip: true }, { leave_by_accuracy: 6 },
                     { leave_by_accuracy: 2.5 }, { leave_by_accuracy: "lots" }]) {
    assert.equal((await call(bad)).status, 400, JSON.stringify(bad));
  }
  assert.equal(calls.length, 0);
});

test("long answers and bad emails are refused; control characters are dropped but line breaks kept", async () => {
  assert.equal((await call({ one_thing: "x".repeat(2001) })).status, 400);
  assert.equal((await call({ used_today: "no", email: "not an email" })).status, 400);
  await call({ confusing: "Line one\nline\u0007 two\u0000" });
  assert.equal(calls.at(-1).body.confusing, "Line one\nline two");
});

test("the bot trap, other sites and oversized bodies are turned away", async () => {
  assert.equal((await call({ ...full, company: "Acme" })).status, 200);
  assert.equal((await call(full, env(), { origin: "https://evil.example" })).status, 403);
  assert.equal((await call({ one_thing: "x".repeat(13_000) })).status, 413);
  assert.equal(calls.length, 0);
});

test("without Supabase it says the survey isn't on, and a Supabase failure is reported", async () => {
  assert.equal((await call(full, {})).status, 503);
  globalThis.fetch.respond = () => new Response(null, { status: 500 });
  assert.equal((await call(full)).status, 502);
});

test("each IP can answer five times an hour", async () => {
  const environment = { ...env(), SIGNUPS: kv() };
  for (let i = 0; i < 5; i++) assert.equal((await call({ used_today: "once" }, environment)).status, 200);
  assert.equal((await call({ used_today: "once" }, environment)).status, 429);
  assert.equal((await call({ used_today: "once" }, environment, { ip: "198.51.100.2" })).status, 200);
});

test("anything but POST is refused", () => {
  assert.equal(onRequest().status, 405);
});
