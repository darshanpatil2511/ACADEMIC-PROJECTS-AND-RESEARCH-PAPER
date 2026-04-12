-- ==========================================================
--  CareLink Connect — Supabase PostgreSQL Schema
--  Run this in Supabase Dashboard → SQL Editor
-- ==========================================================

-- ── Profiles (all users: admin, volunteer, user/senior) ──
create table if not exists profiles (
  id            uuid        primary key default gen_random_uuid(),
  name          text        not null,
  email         text        not null unique,
  password_hash text        not null,
  role          text        not null default 'user'
                            check (role in ('admin', 'volunteer', 'user')),
  phone         text,
  availability  text        default 'part_time'
                            check (availability in ('full_time', 'part_time', 'occasional')),
  skills        text[]      default '{}',
  bio           text,
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── Tasks (admin-created work items / service events) ──
create table if not exists tasks (
  id                     uuid        primary key default gen_random_uuid(),
  title                  text        not null,
  description            text        not null,
  category               text        not null,
  status                 text        not null default 'available'
                                     check (status in ('available','in_progress','completed','cancelled')),
  priority               text        not null default 'medium'
                                     check (priority in ('low','medium','high')),
  due_date               date,
  assigned_volunteer_id  uuid        references profiles(id) on delete set null,
  created_by             uuid        not null references profiles(id) on delete cascade,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- ── Requests (seniors submit these, volunteers accept them) ──
create table if not exists requests (
  id                     uuid        primary key default gen_random_uuid(),
  user_id                uuid        not null references profiles(id) on delete cascade,
  service_type           text        not null,
  description            text,
  scheduled_date         date        not null,
  scheduled_time         time        not null,
  compensation_amount    integer     not null default 0, -- in dollars, shown to volunteers
  status                 text        not null default 'pending'
                                     check (status in ('pending','accepted','in_progress','completed','cancelled')),
  assigned_volunteer_id  uuid        references profiles(id) on delete set null,
  notes                  text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- If the table already exists, run this in Supabase SQL Editor to add the column:
-- alter table requests add column if not exists compensation_amount integer not null default 0;

-- ── Payments (membership tiers) ──
create table if not exists payments (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references profiles(id) on delete cascade,
  tier              text        not null check (tier in ('basic','premium','elite')),
  amount            integer     not null,   -- in cents (1000 = $10.00)
  stripe_payment_id text        unique,
  status            text        not null default 'pending'
                                check (status in ('pending','succeeded','failed')),
  created_at        timestamptz not null default now()
);

-- ── Contact form submissions ──
create table if not exists contacts (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null,
  email      text        not null,
  subject    text        not null,
  message    text        not null,
  created_at timestamptz not null default now()
);

-- ── Seed: default admin account (change password immediately!) ──
-- Password hash below = bcrypt hash of "admin123" (10 rounds)
-- Run: node -e "const b=require('bcryptjs');b.hash('admin123',10).then(console.log)"
-- then replace the hash below with your own.
insert into profiles (name, email, password_hash, role)
values (
  'Admin',
  'admin@carelinkconnect.com',
  '$2a$10$PLACEHOLDER_REPLACE_WITH_REAL_HASH',
  'admin'
) on conflict (email) do nothing;

-- ── Seed: sample tasks ──
-- (Only inserts if there are no tasks yet; admin id must exist first)
-- Add manually via Supabase Dashboard or via API after first login.
