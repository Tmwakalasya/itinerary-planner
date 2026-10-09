# Launch page

The beta sign-up page for Cloudflare Pages:

- `public/` is what's served: `index.html`, `app.js`, `_headers` and the icons.
- `functions/api/signup.js` is the one Pages Function. It adds each sign-up to a Supabase table and can also email you about it.
- `supabase/beta_signups.sql` creates the table.
- `tests/` has the function's tests: `node --test 'launch/tests/*.test.mjs'`.

## Deploy

1. **Supabase**: use a project for City Tourist, not the ENM one. Run `supabase/beta_signups.sql` in its SQL editor.
2. **Cloudflare**: the Pages project `citytourist` (https://citytourist.pages.dev) is set up from the command line with `wrangler.toml`, which binds the `SIGNUPS` KV namespace and holds `SUPABASE_URL`. Deploy from this folder:
   ```
   cd launch
   npx wrangler pages deploy --branch main
   ```
   This project uses direct upload, so it doesn't redeploy by itself when `main` changes. Run the command again after merging.
3. **Secrets** are kept out of `wrangler.toml`. Set them with:
   ```
   npx wrangler pages secret put SUPABASE_KEY --project-name citytourist
   ```
   Use the project's **publishable (anon)** key. Don't use the secret or service-role key: the table only lets this key add rows, which is all the page needs.

   Optional, an email for each sign-up through [Resend](https://resend.com):
   - `RESEND_API_KEY` as a secret.
   - `SIGNUP_TO` under `[vars]`. With Resend's shared sender, this has to be your Resend account's email.
   - `SIGNUP_FROM` once you've verified a domain with Resend.
4. **KV**: `SIGNUPS` is already bound. It limits each IP to 5 sign-ups an hour, and stops a repeat sign-up from emailing you twice.
5. Redeploy so the variables and binding take effect. Then sign up once yourself and check that the row appears.

With neither Supabase nor Resend set up, the form tells people sign-ups aren't switched on yet.

## The blanket invite

When the TestFlight link is ready, run these in the Supabase SQL editor:

```sql
select email, name from beta_signups where invited_at is null order by created_at;
-- after sending
update beta_signups set invited_at = now() where invited_at is null;
```

## Preview locally

`cd launch && npx wrangler pages dev public` serves the page and runs the
function. Put variables in `launch/.dev.vars`, which is gitignored. Any static
server pointed at `public/` shows the page, but the form needs the function.

## Security notes

- `public/_headers` sets a strict Content-Security-Policy. The only inline
  script is the one in `<head>` that decides whether the intro plays, and it's
  allowed by its SHA-256 hash. **If you edit that script, update the hash in
  `_headers`**, or browsers will block it.
- The function only accepts `POST` JSON up to 2 KB from the page's own origin.
  It drops anything that fills the hidden `company` field (a trap for bots),
  validates the email, and strips control characters from the name. It never
  echoes input back into HTML.
- The Supabase key it uses can insert an email and a name, and nothing else. It
  can't read the list, so if it leaked, the emails wouldn't. The table's own
  checks repeat the email and name rules for anything that bypasses the
  function.
- For a harder limit than the per-IP KV counter, add a Cloudflare rate-limiting
  rule on `/api/signup`.
