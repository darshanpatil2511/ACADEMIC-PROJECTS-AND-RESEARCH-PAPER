# CareLink Connect

A full-stack web application that bridges the gap between elderly community members and volunteers. Seniors can request assistance for everyday tasks, volunteers can browse and accept requests, and administrators manage the platform end-to-end.

---

## Table of Contents

- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Features](#features)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Database Setup](#database-setup)
- [API Reference](#api-reference)
- [User Roles](#user-roles)
- [Pages](#pages)

---

## Overview

CareLink Connect is built for a community care scenario where:

- **Seniors (users)** pay a membership fee and submit assistance requests (grocery help, companionship visits, tech support, etc.)
- **Volunteers** browse open requests and admin-created tasks, see the compensation offered, and accept work
- **Admins** manage all tasks, requests, users, and volunteers from a central dashboard

---

## Tech Stack

| Layer      | Technology                              |
|------------|-----------------------------------------|
| Frontend   | React 18, React Router v6, Bootstrap 5  |
| Animations | Custom hooks — IntersectionObserver, requestAnimationFrame |
| Backend    | Node.js, Express                        |
| Database   | Supabase (PostgreSQL)                   |
| Auth       | JWT + bcryptjs                          |
| Payments   | Stripe (Elements + PaymentIntents API)  |

---

## Features

### Seniors
- Register and log in
- Pay a membership (Basic $10 / Premium $25 / Elite $50) via Stripe
- Submit assistance requests with a preferred date, time, and volunteer compensation amount
- Track request status (Pending → Accepted → In Progress → Completed)
- Cancel pending or accepted requests
- View membership status on dashboard

### Volunteers
- Register and log in (no membership required)
- Browse all available tasks and senior assistance requests in one place
- See compensation amount before accepting
- Accept requests and mark them as complete
- Track personal stats — completed tasks, active tasks, hours volunteered

### Admins
- Create, edit, and delete tasks
- View all users, volunteers, and requests
- Manage platform-wide activity from the admin dashboard

---

## Project Structure

```
Carelink connect/
├── client/                         # React frontend
│   ├── public/
│   └── src/
│       ├── components/
│       │   ├── common/             # Navbar, Footer, ChatWidget
│       │   └── chatbot/
│       ├── context/
│       │   └── AuthContext.js      # JWT auth state
│       ├── hooks/
│       │   └── useAnimation.js     # FadeIn, ZoomIn, SlideIn, PopIn, useInView, useCountUp
│       ├── pages/
│       │   ├── HomePage.js
│       │   ├── AboutPage.js
│       │   ├── ContactPage.js
│       │   ├── LoginPage.js
│       │   ├── SignupPage.js
│       │   ├── TasksPage.js
│       │   ├── TaskDetailPage.js
│       │   ├── RequestAssistancePage.js
│       │   ├── PaymentPage.js
│       │   ├── UserDashboardPage.js
│       │   ├── VolunteerDashboardPage.js
│       │   └── AdminDashboardPage.js
│       ├── services/
│       │   └── api.js              # Axios client + all API calls
│       └── styles/
│           └── global.css          # Design tokens, component classes
│
└── server/                         # Express backend
    ├── config/
    │   └── supabase.js             # Supabase client (service role)
    ├── middleware/
    │   └── authenticate.js         # JWT verify + requireRole guard
    ├── routes/
    │   ├── auth.js                 # /api/auth — signup, login, me
    │   ├── tasks.js                # /api/tasks — CRUD + accept/complete
    │   ├── requests.js             # /api/requests — CRUD + accept/complete/cancel
    │   ├── payments.js             # /api/payments — Stripe intents, confirm, status
    │   ├── volunteers.js           # /api/volunteers
    │   ├── users.js                # /api/users
    │   └── contact.js              # /api/contact
    ├── schema.sql                  # Full Supabase schema
    ├── seed-admin.js               # Seeds default admin account
    └── server.js                   # Express app entry point
```

---

## Getting Started

### Prerequisites

- Node.js 18+
- A [Supabase](https://supabase.com) project
- A [Stripe](https://stripe.com) account (test mode is fine)

### 1. Install dependencies

```bash
# Backend
cd server
npm install

# Frontend
cd ../client
npm install
```

### 2. Configure environment variables

Create `server/.env` and `client/.env` — see [Environment Variables](#environment-variables) below.

### 3. Set up the database

Run `server/schema.sql` in the **Supabase Dashboard → SQL Editor**.

```bash
# Then seed the admin account
cd server
node seed-admin.js
```

### 4. Run the app

```bash
# Terminal 1 — backend (port 5009)
cd server
npm run dev

# Terminal 2 — frontend (port 3000)
cd client
npm start
```

Open [http://localhost:3000](http://localhost:3000)

---

## Environment Variables

### `server/.env`

```env
PORT=5009
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
JWT_SECRET=your-random-secret-min-32-chars
STRIPE_SECRET_KEY=sk_test_your_stripe_secret_key
STRIPE_WEBHOOK_SECRET=whsec_optional_for_local_dev
```

### `client/.env`

```env
REACT_APP_API_URL=http://localhost:5009/api
REACT_APP_STRIPE_PUBLIC_KEY=pk_test_your_stripe_publishable_key
```

---

## Database Setup

Run the full schema in **Supabase → SQL Editor**:

```
server/schema.sql
```

### Tables

| Table      | Description                                      |
|------------|--------------------------------------------------|
| `profiles` | All users — admin, volunteer, user (senior)      |
| `tasks`    | Admin-created tasks for volunteers               |
| `requests` | Senior assistance requests                       |
| `payments` | Stripe membership payments                       |
| `contacts` | Contact form submissions                         |

### Adding columns after initial setup

```sql
-- Example: compensation column added to requests
alter table requests add column if not exists compensation_amount integer not null default 0;
```

---

## API Reference

### Auth — `/api/auth`

| Method | Endpoint       | Auth | Description        |
|--------|----------------|------|--------------------|
| POST   | `/signup`      | —    | Register new user  |
| POST   | `/login`       | —    | Login, returns JWT |
| GET    | `/me`          | JWT  | Get current user   |

### Tasks — `/api/tasks`

| Method | Endpoint            | Auth      | Description             |
|--------|---------------------|-----------|-------------------------|
| GET    | `/`                 | —         | List all tasks          |
| GET    | `/:id`              | —         | Get task by ID          |
| POST   | `/`                 | Admin     | Create task             |
| PUT    | `/:id`              | Admin     | Update task             |
| DELETE | `/:id`              | Admin     | Delete task             |
| POST   | `/:id/accept`       | Volunteer | Self-assign task        |
| POST   | `/:id/complete`     | Volunteer | Mark task complete      |

### Requests — `/api/requests`

| Method | Endpoint            | Auth      | Description                     |
|--------|---------------------|-----------|---------------------------------|
| GET    | `/`                 | JWT       | List requests (role-filtered)   |
| POST   | `/`                 | User      | Submit request (membership req) |
| POST   | `/:id/accept`       | Volunteer | Accept a pending request        |
| POST   | `/:id/complete`     | Volunteer | Mark request complete           |
| POST   | `/:id/cancel`       | User/Admin| Cancel a request                |

### Payments — `/api/payments`

| Method | Endpoint                  | Auth | Description                          |
|--------|---------------------------|------|--------------------------------------|
| POST   | `/create-payment-intent`  | JWT  | Create Stripe PaymentIntent          |
| POST   | `/confirm`                | JWT  | Verify with Stripe + mark succeeded  |
| GET    | `/status`                 | JWT  | Check if user has active membership  |
| GET    | `/my`                     | JWT  | List all user payments               |

---

## User Roles

| Role        | Sign Up | Membership | Submit Requests | Browse & Accept Tasks | Admin Panel |
|-------------|---------|------------|-----------------|-----------------------|-------------|
| `user`      | ✅      | Required   | ✅              | ❌                    | ❌          |
| `volunteer` | ✅      | Not needed | ❌              | ✅                    | ❌          |
| `admin`     | Seeded  | —          | —               | ✅                    | ✅          |

Default admin credentials (after running `seed-admin.js`):

```
Email:    admin@carelink.com
Password: Admin@1234
```

> Change these immediately after first login.

---

## Pages

| Route                  | Access       | Description                              |
|------------------------|--------------|------------------------------------------|
| `/`                    | Public       | Home — hero, services, stats, testimonials |
| `/about`               | Public       | Mission, values, impact stats, team      |
| `/contact`             | Public       | Contact form                             |
| `/tasks`               | Public       | Browse tasks + senior requests           |
| `/tasks/:id`           | Public       | Task detail, accept button for volunteers |
| `/signup`              | Public       | Register as user or volunteer            |
| `/login`               | Public       | Login                                    |
| `/request-assistance`  | User         | Choose service, set date/time/compensation |
| `/my-requests`         | User         | Dashboard — membership status, request tracking |
| `/payment`             | User         | Choose membership tier, pay via Stripe   |
| `/volunteer-dashboard` | Volunteer    | Stats, open requests, assigned tasks     |
| `/admin`               | Admin        | Full platform management                 |

---

## Author

**Darshan Patil** — Academic Project, 2026
