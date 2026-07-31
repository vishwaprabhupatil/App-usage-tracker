# Supabase Migration Instructions

I have successfully updated the code to use **Supabase** for Auth and Database. Follow these steps to complete the setup:

## 1. Get your Supabase Keys
Go to your [Supabase Dashboard](https://supabase.com/dashboard/projects) -> Project Settings -> API:
1.  **Project URL**: Copy and paste into `lib/supabase_config.dart`.
2.  **Anon Key**: Copy and paste into `lib/supabase_config.dart`.

## 2. Setup your Database
Go to the **SQL Editor** in your Supabase dashboard and run the following script to create the necessary tables:

```sql
-- Parents table
create table parents (
  id uuid references auth.users not null primary key,
  email text,
  name text,
  pairing_code text unique,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Children table
create table children (
  id uuid references auth.users not null primary key,
  parent_id uuid references parents(id),
  child_name text,
  device_name text,
  installed_apps jsonb default '[]'::jsonb,
  blocked_apps jsonb default '[]'::jsonb,
  app_limits jsonb default '{}'::jsonb,
  shared_parent_ids uuid[] default '{}'::uuid[],
  linked_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Real-time Screentime status
create table screentime (
  id uuid references auth.users not null primary key,
  total_time text default '0m',
  apps jsonb default '[]'::jsonb,
  last_updated timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Daily History
create table daily_usage (
  id bigserial primary key,
  child_id uuid references auth.users not null,
  date date not null,
  total_minutes integer default 0,
  apps jsonb default '[]'::jsonb,
  unique(child_id, date)
);

-- Enable Realtime for these tables
alter publication supabase_realtime add table children;
alter publication supabase_realtime add table screentime;
```

## 3. Configure Authentication
In the Supabase Dashboard:
1.  Go to **Authentication** -> **Providers**.
2.  Enable **Email** (Confirm Email optional).

## 4. Run the project
After updating the keys in `lib/supabase_config.dart`, run:
```bash
flutter pub get
flutter run
```
