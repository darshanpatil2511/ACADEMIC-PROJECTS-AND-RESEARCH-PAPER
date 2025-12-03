# PatientConnect – Clear Lakes Dental Patient Portal Prototype

PatientConnect is a **patient-facing web portal prototype** built for a fictional deployment at **Clear Lakes Dental**.  
It focuses on streamlining the **patient journey before a dental visit** by allowing patients to:

- Create an account and sign in securely
- Schedule and review their appointments
- Submit a pre-visit questionnaire so the care team can prepare in advance

The project demonstrates a modern **TypeScript + Vue 3 + Supabase** full‑stack application aligned with the Clear Lakes Dental Software Engineer Intern role (full‑stack, TypeScript, Vue/Nuxt, APIs, and database-backed workflows).

---

## ✨ Core Features

### 1. Authentication & Patient Onboarding

- Email + password registration with:
  - **Full name** field
  - **Confirm password** validation
- Authentication backed by **Supabase Auth**
- User profile data stored in `auth.users` with `user_metadata.full_name`
- Navbar that:
  - Shows **Login / Register** when logged out
  - Shows **logged-in user state** and a **Log out** button when authenticated

### 2. Appointments (Full-Stack)

**View:** `AppointmentsView.vue`  

Patients can:

- See a list of **their own upcoming appointments**
- Create new appointments with:
  - Date
  - Time
  - Reason for visit
- Data is persisted in Supabase and scoped to the logged-in user via **Row-Level Security (RLS)**.

Backed by **`public.appointments`** table:

| Column      | Type        | Notes                                           |
|------------|-------------|-------------------------------------------------|
| id         | uuid        | Primary key (`gen_random_uuid()`)               |
| user_id    | uuid        | FK → `auth.users.id`, not null                  |
| date       | date        | Appointment date, not null                      |
| time       | text        | Appointment time (e.g., `"10:30 AM"`), not null |
| reason     | text        | Optional reason for visit                       |
| status     | text        | Defaults to `'Scheduled'`                       |
| created_at | timestamptz | Defaults to `now()`, audit/ordering field       |

**Frontend behavior:**

- On mount:
  - Fetches the current auth user from Supabase
  - Loads appointments with:
    ```ts
    select('*')
      .eq('user_id', currentUserId)
      .order('date', { ascending: true })
    ```
- On creating an appointment:
  - Inserts a new row into `public.appointments`
  - Optimistically updates or refetches the list
- Shows loading & error states:
  - “Checking your session…”
  - “Loading your appointments…”
  - Error banner if Supabase calls fail

### 3. Pre-Visit Questionnaire (Full-Stack)

**View:** `PreVisitFormView.vue`  

Patients can submit a **pre-visit questionnaire** to help clinicians prepare:

- Pain level (1–10)
- Area of concern
- Additional notes

Backed by **`public.previsit_forms`** table:

| Column      | Type        | Notes                                        |
|------------|-------------|----------------------------------------------|
| id         | uuid        | Primary key (`gen_random_uuid()`)            |
| user_id    | uuid        | FK → `auth.users.id`, not null               |
| pain_level | integer     | Required (1–10)                              |
| concern    | text        | Required, main concern/issue                 |
| notes      | text        | Optional and free-form                       |
| created_at | timestamptz | Defaults to `now()`, used for ordering/audit |

**Frontend behavior:**

- Requires a logged-in user (checks Supabase auth)
- Validates:
  - Pain level is present
  - Concern is non-empty
- Inserts into `public.previsit_forms` with `user_id = currentUserId`
- Shows:
  - Success banner after save
  - Error banner if Supabase insert fails
  - A “Last submitted pre-visit info” summary with timestamp

This models the workflow described in the JD: **“Intelligent automation tools to tackle complex and time-consuming dental-specific administrative or clinical support tasks.”**

### 4. UX & Layout

- Responsive layout using modern CSS:
  - Flexible cards
  - Stacked layouts on mobile
  - Two-column layout on larger screens (e.g., for Appointments)
- Theming:
  - Subtle **midnight / slate gradient** background
  - Accent colors inspired by healthcare + modern SaaS (teals & blues)
- Clear text hierarchy:
  - Page headers
  - Subtitles explaining context
  - Section labels for forms

---

## 🧱 Tech Stack

**Frontend**

- [Vue 3](https://vuejs.org/) (Composition API + `<script setup>`)
- [Vite](https://vitejs.dev/) as build tool / dev server
- [TypeScript](https://www.typescriptlang.org/)
- Vue Router for SPA navigation

**Backend / BaaS**

- [Supabase](https://supabase.com/)
  - Postgres database
  - Auth (email/password)
  - Row-Level Security (RLS) policies
  - Dashboard table editor used for schema

**Other**

- Plain CSS with custom layout and utilities
- npm as package manager
- Node.js (v20+ recommended)

---

## 📂 Project Structure (High-Level)

```bash
Patientconnect/
├─ src/
│  ├─ App.vue                 # Root layout, navbar, and router outlet
│  ├─ main.ts                 # App entry, router mounting
│  ├─ router/
│  │  └─ index.ts             # Routes: home, login, register, appointments, pre-visit
│  ├─ views/
│  │  ├─ HomeView.vue         # Landing page, explanation of flows
│  │  ├─ LoginView.vue        # Patient login
│  │  ├─ RegisterView.vue     # Patient registration (name + email + password + confirm)
│  │  ├─ AppointmentsView.vue # Full-stack appointments feature
│  │  └─ PreVisitFormView.vue # Full-stack pre-visit questionnaire
│  ├─ composables/
│  │  └─ useAuth.ts           # Small global auth composable (user, loading, logout, etc.)
│  ├─ supabaseClient.ts       # Supabase client initialization (URL + anon key)
│  └─ assets/                 # (Optional: icons, logos, etc.)
├─ index.html
├─ package.json
├─ tsconfig.json
└─ vite.config.ts
```

---

## 🔐 Supabase Setup

### 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project.
2. In the project:
   - Go to **Settings → API**
   - Note the **Project URL** and **anon public key**

Create `.env.local` in the project root:

```bash
VITE_SUPABASE_URL=your-project-url
VITE_SUPABASE_ANON_KEY=your-anon-public-key
```

(These are already consumed by `supabaseClient.ts`.)

---

### 2. Database Schema

#### `public.appointments`

You can create this table via SQL:

```sql
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  time text not null,
  reason text,
  status text not null default 'Scheduled',
  created_at timestamptz not null default now()
);
```

#### `public.previsit_forms`

```sql
create table public.previsit_forms (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  pain_level integer not null,
  concern text not null,
  notes text,
  created_at timestamptz not null default now()
);
```

---

### 3. Row-Level Security (RLS) Policies

Enable RLS for both tables in the Supabase dashboard:

```sql
alter table public.appointments enable row level security;
alter table public.previsit_forms enable row level security;
```

Then create policies for **“Users can manage their own rows”**:

#### Appointments

```sql
create policy "Users can manage their own appointments"
on public.appointments
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
```

#### Pre-Visit Forms

```sql
create policy "Users can manage their own previsit forms"
on public.previsit_forms
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
```

This ensures:

- Each authenticated user can only read/write their own appointments and forms.
- There is no cross-visibility between patient accounts.

---

## 🚀 Getting Started (Local Development)

### 1. Prerequisites

- **Node.js ≥ 20.19** (for Vite + ecosystem)
- npm (comes with Node)
- A Supabase project with:
  - `appointments` and `previsit_forms` tables
  - RLS policies as above

### 2. Install dependencies

```bash
npm install
```

### 3. Set environment variables

Create `.env.local` in the project root:

```bash
VITE_SUPABASE_URL=your-project-url
VITE_SUPABASE_ANON_KEY=your-anon-public-key
```

### 4. Run the dev server

```bash
npm run dev
```

The app will be available at:

- `http://localhost:5173` (default Vite port)

### 5. Build for production

```bash
npm run build
npm run preview
```

---

## 🧪 How to Use the App (Demo Flow)

1. **Register as a new patient**

   - Go to **Register**
   - Enter:
     - Full name
     - Email
     - Password + confirm password
   - Account is created in Supabase Auth with `user_metadata.full_name`.

2. **Log in**

   - Go to **Login**
   - Use the same email and password
   - Navbar will update to show logged-in state

3. **Create an appointment**

   - Navigate to **Appointments**
   - Select date, time, and optionally reason
   - Submit → a new row is stored in `public.appointments`
   - You should see the new appointment appear in the list

4. **Complete pre-visit form**

   - Go to **Pre-Visit Form**
   - Enter pain level, concern, and optional notes
   - Submit → a new row is stored in `public.previsit_forms`
   - The most recent submission is summarized on-screen

5. **Confirm in Supabase**

   - In the Supabase dashboard, open:
     - `public.appointments`
     - `public.previsit_forms`
   - Verify only your **user’s `user_id`** rows are used

---

## 💡 Future Enhancements

Some natural next steps that align with the original internship description:

- **Doctor / Admin Portal**
  - Separate admin route to view all appointments and pre-visit forms
  - Filtering by date, provider, or patient
  - Role-based access using Supabase `user_metadata.role = 'doctor'`

- **Reminders & Notifications**
  - Email or SMS reminders before appointments
  - Automatic outreach when pre-visit forms are missing

- **AI-Assisted Triage**
  - Use LLMs or rule-based engines to:
    - Flag urgent cases based on pain level/concern
    - Suggest preparation steps or follow-up questions for the dental team

- **Nuxt 3 / Nuxt 4 Migration**
  - Move to Nuxt for SSR / SEO
  - Add `Nuxt + Supabase` module integration

---

## 🧾 Why This Project is Relevant for Clear Lakes Dental

- Uses a **modern TypeScript + Vue 3 + Vite** stack, similar to a Nuxt 3 ecosystem.
- Demonstrates:
  - **Full-stack development** with a real database (Supabase/Postgres)
  - **Auth integration** and secure per-user data access (RLS)
  - **Patient-centric UX** that improves pre-visit workflows
  - Clean, maintainable code structure with small composables and clear views

This project can be shown live, walked through in an interview, and extended into an admin/doctor-facing view if deeper system design is requested.
