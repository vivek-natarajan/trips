-- Self-serve TDAC uploads — private bucket + RLS.
-- Idempotent: safe to re-run. Apply in Supabase SQL editor or via CLI.

-- 1) Private bucket
insert into storage.buckets (id, name, public)
values ('tdac', 'tdac', false)
on conflict (id) do update set public = false;

-- 2) Policies on storage.objects for bucket 'tdac'.
-- NOTE: compare auth.jwt() ->> 'sub' (text). Do NOT use auth.uid() — it casts
-- sub to uuid and would error on string ids like 'ruthu'.

drop policy if exists "tdac read own or organizer" on storage.objects;
create policy "tdac read own or organizer"
on storage.objects for select to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac insert own or organizer" on storage.objects;
create policy "tdac insert own or organizer"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac update own or organizer" on storage.objects;
create policy "tdac update own or organizer"
on storage.objects for update to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
)
with check (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);

drop policy if exists "tdac delete own or organizer" on storage.objects;
create policy "tdac delete own or organizer"
on storage.objects for delete to authenticated
using (
  bucket_id = 'tdac'
  and (
    (auth.jwt() ->> 'app_role') = 'organizer'
    or name = (auth.jwt() ->> 'sub') || '.pdf'
  )
);
