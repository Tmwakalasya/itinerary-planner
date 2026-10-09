-- The beta list. Run once in the Supabase SQL editor of the City Tourist
-- project (not the ENM one).
--
-- The launch page's function signs people up with the project's publishable
-- (anon) key. That key can add a row with an email and a name, and nothing
-- else: it can't read the list, change a row or delete one. Reading and the
-- blanket invite happen in the dashboard, or with the secret key, which never
-- leaves your machine.

create table if not exists public.beta_signups (
  id bigint generated always as identity primary key,
  email text not null unique
    check (char_length(email) <= 254 and email = lower(email)
           and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'),
  name text
    check (name is null or (char_length(name) between 1 and 80 and name !~ '[[:cntrl:]]')),
  created_at timestamptz not null default now(),
  -- Set when the TestFlight invite goes out, so a second send skips them.
  invited_at timestamptz
);

alter table public.beta_signups enable row level security;

-- Only these two columns, only inserts.
revoke all on public.beta_signups from anon, authenticated;
grant insert (email, name) on public.beta_signups to anon;

drop policy if exists "Anyone can join the beta list" on public.beta_signups;
create policy "Anyone can join the beta list"
  on public.beta_signups for insert to anon
  with check (true);

-- The blanket invite, later:
--   select email, name from public.beta_signups where invited_at is null order by created_at;
--   update public.beta_signups set invited_at = now() where invited_at is null;
