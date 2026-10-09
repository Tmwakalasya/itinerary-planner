// node --test 'launch/tests/*.test.mjs'
// The sign-up function against a stubbed fetch and an in-memory KV.
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { onRequestPost, onRequest } from "../functions/api/signup.js";

const SITE = "https://citytourist.pages.dev";
let calls;

beforeEach(() => {
  calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init, body: init.body ? JSON.parse(init.body) : null });
    const handler = globalThis.fetch.respond || (() => new Response(null, { status: 201 }));
    return handler(String(url));
  };
  globalThis.fetch.respond = null;
});

function kv() {
  const store = new Map();
  return {
    store,
    get: async (k) => (store.has(k) ? store.get(k) : null),
    put: async (k, v) => { store.set(k, v); },
    delete: async (k) => { store.delete(k); },
  };
}

const supabaseEnv = () => ({ SUPABASE_URL: "https://abc.supabase.co/", SUPABASE_KEY: "sb_publishable_test" });
const resendEnv = () => ({ RESEND_API_KEY: "re_test", SIGNUP_TO: "owner@example.com" });

function post(body, { origin = SITE, type = "application/json", ip = "203.0.113.7" } = {}) {
  const headers = { "content-type": type, "cf-connecting-ip": ip };
  if (origin) headers.origin = origin;
  return new Request(`${SITE}/api/signup`, {
    method: "POST",
    headers,
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

async function call(body, env, options) {
  const response = await onRequestPost({ request: post(body, options), env });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

test("a sign-up is stored in Supabase, lowercased, with only the publishable key", async () => {
  const result = await call({ email: "  Tuntu@Example.COM ", name: "Tuntu" }, supabaseEnv());

  assert.equal(result.status, 200);
  assert.deepEqual(result.body, { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://abc.supabase.co/rest/v1/beta_signups");
  assert.deepEqual(calls[0].body, { email: "tuntu@example.com", name: "Tuntu" });
  assert.equal(calls[0].init.headers.apikey, "sb_publishable_test");
  assert.equal(calls[0].init.headers.Authorization, undefined, "new keys aren't bearer tokens");
  assert.equal(calls[0].init.headers.Prefer, "return=minimal", "the key can't read rows back");
  assert.equal(result.headers.get("cache-control"), "no-store");
});

test("a legacy anon key also goes as a bearer token", async () => {
  await call({ email: "a@b.co" }, { ...supabaseEnv(), SUPABASE_KEY: "eyJhbGciOiJIUzI1NiJ9.x.y" });
  assert.equal(calls[0].init.headers.Authorization, "Bearer eyJhbGciOiJIUzI1NiJ9.x.y");
});

test("no name is stored as null", async () => {
  await call({ email: "a@b.co" }, supabaseEnv());
  assert.deepEqual(calls[0].body, { email: "a@b.co", name: null });
});

test("bad addresses are refused before anything is sent", async () => {
  for (const email of ["", "nope", "a@b", "a b@c.de", "x".repeat(250) + "@b.co"]) {
    const result = await call({ email }, supabaseEnv());
    assert.equal(result.status, 400, email);
  }
  assert.equal(calls.length, 0);
});

test("control characters are stripped from a name, and long names refused", async () => {
  await call({ email: "a@b.co", name: "Tun\r\ntu\u0007" }, supabaseEnv());
  assert.equal(calls[0].body.name, "Tuntu");

  const long = await call({ email: "c@d.co", name: "x".repeat(81) }, supabaseEnv());
  assert.equal(long.status, 400);
  assert.equal(calls.length, 1);
});

test("the bot trap answers ok and sends nothing", async () => {
  const result = await call({ email: "bot@spam.co", company: "Acme" }, supabaseEnv());
  assert.equal(result.status, 200);
  assert.equal(calls.length, 0);
});

test("other sites' pages can't post into the list", async () => {
  const result = await call({ email: "a@b.co" }, supabaseEnv(), { origin: "https://evil.example" });
  assert.equal(result.status, 403);
  assert.equal(calls.length, 0);
});

test("only JSON, and only small bodies", async () => {
  assert.equal((await call("email=a@b.co", supabaseEnv(), { type: "application/x-www-form-urlencoded" })).status, 415);
  assert.equal((await call("{not json", supabaseEnv())).status, 400);
  assert.equal((await call("[1]", supabaseEnv())).status, 400, "an array isn't a form");
  assert.equal((await call({ email: "a@b.co", pad: "x".repeat(3000) }, supabaseEnv())).status, 413);
  assert.equal(calls.length, 0);
});

test("with nowhere to put sign-ups, it says so", async () => {
  const result = await call({ email: "a@b.co" }, {});
  assert.equal(result.status, 503);
});

test("someone already on the list is told it worked, and you aren't emailed again", async () => {
  globalThis.fetch.respond = (url) => new Response(null, { status: url.includes("supabase") ? 409 : 200 });
  const result = await call({ email: "a@b.co" }, { ...supabaseEnv(), ...resendEnv() });
  assert.equal(result.status, 200);
  assert.equal(calls.filter((c) => c.url.includes("resend")).length, 0);
});

test("a Supabase failure is reported", async () => {
  globalThis.fetch.respond = () => new Response(null, { status: 500 });
  const result = await call({ email: "a@b.co" }, supabaseEnv());
  assert.equal(result.status, 502);
});

test("each sign-up is emailed to you, with their address to reply to", async () => {
  await call({ email: "a@b.co", name: "Ana" }, { ...supabaseEnv(), ...resendEnv() });
  const mail = calls.find((c) => c.url === "https://api.resend.com/emails");
  assert.ok(mail);
  assert.deepEqual(mail.body.to, ["owner@example.com"]);
  assert.equal(mail.body.reply_to, "a@b.co");
  assert.equal(mail.body.subject, "Beta signup: Ana (a@b.co)");
});

test("a failed notification only fails the sign-up when there's no Supabase list", async () => {
  globalThis.fetch.respond = (url) => new Response(null, { status: url.includes("resend") ? 500 : 201 });
  assert.equal((await call({ email: "a@b.co" }, { ...supabaseEnv(), ...resendEnv() })).status, 200);
  assert.equal((await call({ email: "c@d.co" }, resendEnv())).status, 502);
});

test("each IP gets five tries an hour", async () => {
  const env = { ...supabaseEnv(), SIGNUPS: kv() };
  for (let i = 0; i < 5; i++) {
    assert.equal((await call({ email: `p${i}@b.co` }, env)).status, 200);
  }
  const sixth = await call({ email: "p5@b.co" }, env);
  assert.equal(sixth.status, 429);
  assert.equal((await call({ email: "q@b.co" }, env, { ip: "198.51.100.1" })).status, 200, "another IP isn't affected");
});

test("with KV, a repeat sign-up doesn't email you twice", async () => {
  const env = { ...resendEnv(), SIGNUPS: kv() };
  await call({ email: "a@b.co" }, env);
  await call({ email: "a@b.co" }, env);
  assert.equal(calls.filter((c) => c.url.includes("resend")).length, 1);
});

test("anything but POST is refused", async () => {
  const response = onRequest();
  assert.equal(response.status, 405);
});
