# Launch page

The beta sign-up page: a static page (`index.html`, `app.js`) and one Cloudflare
Pages Function (`functions/api/signup.js`) that emails each sign-up to you.

## Deploy on Cloudflare Pages

1. **Pages → Create → Connect to Git**, pick this repository.
   - Root directory: `launch`
   - Framework preset: None. Leave the build command empty. Set the build output directory to `/`.
2. **Resend** ([resend.com](https://resend.com)): sign up with the address you want sign-ups sent to, and create an API key.
3. **Settings → Variables and Secrets** on the Pages project:
   - `RESEND_API_KEY` (type: secret)
   - `SIGNUP_TO`: your Resend account's email. The shared `onboarding@resend.dev` sender can only deliver to that address.
   - `SIGNUP_FROM` (optional): set it once you verify your own domain with Resend.
4. **Workers & Pages → KV**: create a namespace, then bind it to the project as `SIGNUPS` under Settings → Bindings. This step is recommended. It keeps the list, stops a repeat sign-up from emailing you twice, and limits each IP to 5 sign-ups an hour.
5. Redeploy so the variables and binding take effect.

Without `RESEND_API_KEY` and `SIGNUP_TO`, the form says sign-ups aren't switched on yet. It doesn't fail silently.

## Preview locally

`npx wrangler pages dev launch` serves the page and runs the function, using
variables from `launch/.dev.vars`. That file is gitignored, so it's never committed.
Any static server shows the page, but the form needs the function to submit.

## Security notes

- `_headers` sets a strict Content-Security-Policy. The only inline script is
  the one in `<head>` that decides whether the intro plays. It's allowed by its
  SHA-256 hash, so **if you edit that script, update the hash in `_headers`**,
  or browsers will block it.
- The function only accepts `POST` JSON up to 2 KB from the page's own origin.
  It drops sign-ups that fill the hidden `company` field (a trap for bots) and
  validates the address before anything is sent. It never echoes input back
  into HTML.
- For a harder limit than the per-IP KV counter, add a Cloudflare rate-limiting
  rule on `/api/signup`.
