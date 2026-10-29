-- The beta survey's answers. Run once in the City Tourist project's SQL
-- editor, like beta_signups.sql.
--
-- As with sign-ups, the site's publishable key can add an answer and nothing
-- else: it can't read, change or delete any. Read them in the dashboard.

create table if not exists public.beta_feedback (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  app_version text check (app_version is null or char_length(app_version) <= 40),
  city text check (city is null or char_length(city) <= 80),
  planned_day text check (planned_day is null or planned_day in ('yes', 'started', 'no')),
  used_today text check (used_today is null or used_today in ('often', 'once', 'no')),
  leave_by_accuracy smallint check (leave_by_accuracy is null or leave_by_accuracy between 1 and 5),
  plan_broke text check (plan_broke is null or char_length(plan_broke) <= 2000),
  confusing text check (confusing is null or char_length(confusing) <= 2000),
  next_trip text check (next_trip is null or next_trip in ('yes', 'maybe', 'no')),
  one_thing text check (one_thing is null or char_length(one_thing) <= 2000),
  email text check (email is null or (char_length(email) <= 254 and email = lower(email)
                                      and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$'))
);

alter table public.beta_feedback enable row level security;

revoke all on public.beta_feedback from anon, authenticated;
grant insert (app_version, city, planned_day, used_today, leave_by_accuracy,
              plan_broke, confusing, next_trip, one_thing, email)
  on public.beta_feedback to anon;

drop policy if exists "Anyone can answer the beta survey" on public.beta_feedback;
create policy "Anyone can answer the beta survey"
  on public.beta_feedback for insert to anon
  with check (true);

-- Reading the answers:
--   select created_at, city, used_today, leave_by_accuracy, plan_broke, confusing, next_trip, one_thing, email
--   from beta_feedback order by created_at desc;
--   select used_today, count(*) from beta_feedback group by used_today;
