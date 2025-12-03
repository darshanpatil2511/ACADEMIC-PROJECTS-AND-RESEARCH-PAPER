<template>
  <section class="page">
    <h2>My Appointments</h2>
    <p class="subtitle">
      Review your upcoming dental visits and book new ones. This screen is now wired to a real
      <strong>Supabase</strong> <code>appointments</code> table scoped to the logged-in patient.
    </p>

    <!-- User session status -->
    <div class="user-banner" v-if="loadingUser">
      Checking your session…
    </div>
    <div class="user-banner" v-else-if="!userEmail">
      You’re not logged in. Log in from the top navigation to book and view your appointments.
    </div>
    <div class="user-banner" v-else>
      Logged in as <span class="highlight">{{ userEmail }}</span>
    </div>

    <!-- Error banner -->
    <div v-if="errorMessage" class="error-banner">
      {{ errorMessage }}
    </div>

    <div class="layout">
      <!-- Upcoming appointments list -->
      <div class="card">
        <h3>Upcoming appointments</h3>

        <p v-if="loadingAppointments" class="empty">
          Loading your appointments…
        </p>

        <p v-else-if="appointments.length === 0" class="empty">
          No appointments yet. Use the form on the right to book one.
        </p>

        <ul v-else class="appointments-list">
          <li v-for="appt in appointments" :key="appt.id" class="appointment-row">
            <div class="appt-main">
              <span class="appt-date">{{ appt.date }} · {{ appt.time }}</span>
              <span class="appt-reason">{{ appt.reason }}</span>
            </div>
            <span class="status-pill" :data-status="appt.status">
              {{ appt.status }}
            </span>
          </li>
        </ul>
      </div>

      <!-- Booking form (Supabase-backed) -->
      <form class="card form" @submit.prevent="createAppointment">
        <h3>Book a new appointment</h3>

        <label>
          Date
          <input v-model="date" type="date" required />
        </label>

        <label>
          Time
          <input v-model="time" type="time" required />
        </label>

        <label>
          Reason
          <input
            v-model="reason"
            type="text"
            required
            placeholder="e.g., cleaning, tooth pain, follow-up"
          />
        </label>

        <button type="submit" :disabled="isSubmitting || !currentUserId">
          <span v-if="!currentUserId">Log in to book</span>
          <span v-else-if="isSubmitting">Saving…</span>
          <span v-else>Book appointment</span>
        </button>

        <p class="hint" v-if="currentUserId">
          This creates a row in the Supabase <code>appointments</code> table linked to your account.
        </p>
        <p class="hint" v-else>
          Form is disabled because no user is logged in. Once you log in, you’ll be able to book and
          see your appointments persisted in Supabase.
        </p>
      </form>
    </div>
  </section>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

interface Appointment {
  id: string
  date: string
  time: string
  reason: string
  status: string
}

const loadingUser = ref(true)
const loadingAppointments = ref(false)
const isSubmitting = ref(false)
const errorMessage = ref('')

const userEmail = ref<string | null>(null)
const currentUserId = ref<string | null>(null)

const appointments = ref<Appointment[]>([])

// form state
const date = ref('')
const time = ref('')
const reason = ref('')

async function fetchAppointments() {
  if (!currentUserId.value) return

  loadingAppointments.value = true
  errorMessage.value = ''

  const { data, error } = await supabase
    .from('appointments')
    .select('id, date, time, reason, status')
    .eq('user_id', currentUserId.value)
    .order('date', { ascending: true })

  if (error) {
    console.error('[Appointments] Fetch error:', error)
    errorMessage.value = 'Unable to load appointments right now. Please try again in a moment.'
    loadingAppointments.value = false
    return
  }

  appointments.value = (data ?? []).map((row: any) => ({
    id: row.id,
    date: row.date,
    time: row.time,
    reason: row.reason ?? 'General visit',
    status: row.status ?? 'Scheduled'
  }))

  loadingAppointments.value = false
}

onMounted(async () => {
  const { data, error } = await supabase.auth.getUser()

  if (error) {
    console.error('[Appointments] getUser error:', error)
    errorMessage.value = 'Unable to verify your session. Try refreshing the page.'
    loadingUser.value = false
    return
  }

  if (data?.user) {
    userEmail.value = data.user.email ?? null
    currentUserId.value = data.user.id
    await fetchAppointments()
  }

  loadingUser.value = false
})

async function createAppointment() {
  if (!currentUserId.value) {
    errorMessage.value = 'Please log in before booking an appointment.'
    return
  }

  if (!date.value || !time.value || !reason.value) {
    errorMessage.value = 'Please fill in date, time, and reason.'
    return
  }

  isSubmitting.value = true
  errorMessage.value = ''

  const { data, error } = await supabase
    .from('appointments')
    .insert({
      user_id: currentUserId.value,
      date: date.value,
      time: time.value,
      reason: reason.value,
      status: 'Scheduled'
    })
    .select('id, date, time, reason, status')
    .single()

  if (error) {
    console.error('[Appointments] Insert error:', error)
    errorMessage.value = 'Could not save this appointment. Please try again.'
    isSubmitting.value = false
    return
  }

  if (data) {
    appointments.value.unshift({
      id: data.id,
      date: data.date,
      time: data.time,
      reason: data.reason ?? 'General visit',
      status: data.status ?? 'Scheduled'
    })
  }

  // clear form
  date.value = ''
  time.value = ''
  reason.value = ''

  isSubmitting.value = false
}
</script>

<style scoped>
.page {
  max-width: 980px;
  margin: 2rem auto;
  padding: 1.5rem 1.25rem 2.5rem;
  border-radius: 1.25rem;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.4);
  box-shadow: 0 18px 45px rgba(15, 23, 42, 0.85);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

h2 {
  font-size: 1.5rem;
  margin-bottom: 0.4rem;
}

.subtitle {
  font-size: 0.95rem;
  color: #e5e7eb;
  margin-bottom: 1rem;
}

.user-banner {
  font-size: 0.9rem;
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  background: rgba(15, 23, 42, 0.95);
  border: 1px solid rgba(148, 163, 184, 0.45);
  margin-bottom: 0.75rem;
}

.error-banner {
  margin-bottom: 0.75rem;
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  background: rgba(153, 27, 27, 0.95);
  border: 1px solid rgba(248, 113, 113, 0.9);
  color: #fee2e2;
  font-size: 0.85rem;
}

.highlight {
  color: #38bdf8;
  font-weight: 500;
}

.layout {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
  gap: 1.25rem;
}

.card {
  padding: 1.1rem 1rem;
  border-radius: 1rem;
  background: #020617;
  border: 1px solid #1f2937;
}

.card h3 {
  font-size: 1.05rem;
  margin-bottom: 0.6rem;
}

.empty {
  font-size: 0.9rem;
  color: #e5e7eb;
}

.appointments-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.appointment-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.55rem 0.65rem;
  border-radius: 0.75rem;
  background: #020617;
  border: 1px solid #1f2937;
}

.appt-main {
  display: flex;
  flex-direction: column;
  gap: 0.15rem;
}

.appt-date {
  font-size: 0.9rem;
  font-weight: 500;
}

.appt-reason {
  font-size: 0.85rem;
  color: #e5e7eb;
}

.status-pill {
  font-size: 0.75rem;
  padding: 0.25rem 0.55rem;
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.7);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.status-pill[data-status='Scheduled'] {
  border-color: rgba(52, 211, 153, 0.7);
  color: #6ee7b7;
}

.form label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.9rem;
  margin-bottom: 0.5rem;
}

.form input {
  width: 100%;
  padding: 0.5rem 0.6rem;
  border-radius: 0.6rem;
  border: 1px solid #334155;
  background: #020617;
  color: #e5e7eb;
  font-size: 0.9rem;
}

.form button {
  margin-top: 0.5rem;
  padding: 0.6rem 1rem;
  border-radius: 999px;
  border: none;
  background: linear-gradient(135deg, #22d3ee, #38bdf8, #6366f1);
  color: #020617;
  font-weight: 500;
  font-size: 0.9rem;
  cursor: pointer;
  transition: opacity 0.15s ease, transform 0.1s ease, box-shadow 0.1s ease;
  box-shadow: 0 10px 24px rgba(56, 189, 248, 0.45);
}

.form button[disabled] {
  opacity: 0.55;
  cursor: not-allowed;
  box-shadow: none;
}

.form button:not([disabled]):hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 30px rgba(56, 189, 248, 0.7);
}

.hint {
  margin-top: 0.5rem;
  font-size: 0.78rem;
  color: #9ca3af;
}

@media (max-width: 768px) {
  .layout {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
