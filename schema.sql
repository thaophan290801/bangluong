-- Chạy toàn bộ file này trong Supabase > SQL Editor
create table profiles(
  id uuid primary key references auth.users on delete cascade,
  full_name text default '', role text default 'employee' check (role in ('manager','employee')),
  base_salary numeric default 0, fuel_allowance numeric default 0, dependents int default 0,
  std_mode text default '26' check (std_mode in ('26','weekdays')),
  period_start_day int default 1 check (period_start_day in (1,24)),
  weekly_off int[] default '{0}', shifts jsonb default '[]');
create table work_days(
  user_id uuid references profiles on delete cascade, work_date date,
  status text, shift text, start_t text, end_t text, primary key(user_id, work_date));
create table holidays(d date primary key);
create table tax_brackets(id bigint generated always as identity primary key, upper numeric, rate numeric not null);
create table adjustments(user_id uuid references profiles on delete cascade, ym text, amount numeric default 0, note text default '', primary key(user_id, ym));
create table schedules(id bigint generated always as identity primary key, user_id uuid references profiles on delete cascade, path text, created_at timestamptz default now());

create function is_manager() returns boolean language sql security definer stable
as $$ select exists(select 1 from profiles where id = auth.uid() and role = 'manager') $$;

-- Tự tạo hồ sơ khi quản lý thêm user trong Authentication
create function new_user() returns trigger language plpgsql security definer as $$
begin insert into profiles(id, full_name) values (new.id, coalesce(new.email,'')); return new; end $$;
create trigger on_auth_user after insert on auth.users for each row execute function new_user();

alter table profiles enable row level security; alter table work_days enable row level security;
alter table holidays enable row level security; alter table tax_brackets enable row level security;
alter table adjustments enable row level security; alter table schedules enable row level security;

create policy p_sel on profiles for select using (id = auth.uid() or is_manager());
create policy p_upd on profiles for update using (is_manager());
create policy w_all on work_days for all using (user_id = auth.uid() or is_manager()) with check (user_id = auth.uid() or is_manager());
create policy s_all on schedules for all using (user_id = auth.uid() or is_manager()) with check (user_id = auth.uid() or is_manager());
create policy a_sel on adjustments for select using (user_id = auth.uid() or is_manager());
create policy a_w on adjustments for all using (is_manager()) with check (is_manager());
create policy h_sel on holidays for select using (auth.uid() is not null);
create policy h_w on holidays for all using (is_manager()) with check (is_manager());
create policy t_sel on tax_brackets for select using (auth.uid() is not null);
create policy t_w on tax_brackets for all using (is_manager()) with check (is_manager());

insert into storage.buckets(id, name, public) values ('schedules','schedules',false);
create policy st_all on storage.objects for all
  using (bucket_id = 'schedules' and (is_manager() or (storage.foldername(name))[1] = auth.uid()::text))
  with check (bucket_id = 'schedules' and (is_manager() or (storage.foldername(name))[1] = auth.uid()::text));

-- Sau khi tạo tài khoản quản lý trong Authentication, chạy (thay email):
-- update profiles set role='manager' where full_name='email-cua-ban@vd.com';
