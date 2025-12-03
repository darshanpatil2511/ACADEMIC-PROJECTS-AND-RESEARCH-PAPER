<template>
  <section class="page">
    <h2>Pre-Visit Questionnaire</h2>
    <p class="subtitle">
      Share how you’re feeling before your appointment so the dental team can prepare for your visit.
      This form now saves securely to your Supabase <code>previsit_forms</code> table for the logged-in patient.
    </p>

    <!-- User session state -->
    <div class="user-banner" v-if="loadingUser">
      Checking your session…
    </div>
    <div class="user-banner" v-else-if="!userEmail">
      You’re not logged in. Log in first so we can attach this form to your account.
    </div>
    <div class="user-banner" v-else>
      Logged in as <span class="highlight">{{ userEmail }}</span>
    </div>

    <!-- Error banner -->
    <div v-if="errorMessage" class="error-banner">
      {{ errorMessage }}
    </div>

    <!-- Success message -->
    <div v-if="successMessage" class="success-banner">
      {{ successMessage }}
    </div>

    <form @submit.prevent="onSubmit" class="card" novalidate>
      <label>
        Pain level (1–10)
        <input
          v-model.number="painLevel"
          type="number"
          min="1"
          max="10"
          required
          placeholder="e.g., 4"
        />
      </label>

      <label>
        Area of concern
        <input
          v-model="concern"
          type="text"
          required
          placeholder="e.g., sensitivity in upper right molar"
        />
      </label>

      <label>
        Notes for your dentist
        <textarea
          v-model="notes"
          rows="4"
          placeholder="Anything else your dentist should know before the visit?"
        />
      </label>

      <button type="submit" :disabled="isSubmitting || !currentUserId">
        <span v-if="!currentUserId">Log in to submit</span>
        <span v-else-if="isSubmitting">Submitting…</span>
        <span v-else>Submit pre-visit form</span>
      </button>

      <p class="hint" v-if="currentUserId">
        On submit, this creates a row in the Supabase <code>previsit_forms</code> table linked to your
        user id.
      </p>
      <p class="hint" v-else>
        Form is disabled because there’s no logged-in user. Once you log in, your answers will be
        securely stored per account.
      </p>

      <div v-if="lastSubmitted" class="summary">
        <h3>Last submitted pre-visit info</h3>
        <p><strong>Pain level:</strong> {{ lastSubmitted.pain_level }}</p>
        <p><strong>Concern:</strong> {{ lastSubmitted.concern }}</p>
        <p v-if="lastSubmitted.notes"><strong>Notes:</strong> {{ lastSubmitted.notes }}</p>
        <p class="summary-meta">
          Submitted at
          {{ new Date(lastSubmitted.created_at).toLocaleString() }}
        </p>
      </div>
    </form>
  </section>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

interface PrevisitFormRow {
  id: string
  user_id: string
  pain_level: number
  concern: string
  notes: string | null
  created_at: string
}

const painLevel = ref<number | null>(null)
const concern = ref('')
const notes = ref('')

const loadingUser = ref(true)
const isSubmitting = ref(false)
const errorMessage = ref('')
const successMessage = ref('')

const userEmail = ref<string | null>(null)
const currentUserId = ref<string | null>(null)

const lastSubmitted = ref<PrevisitFormRow | null>(null)

onMounted(async () => {
  const { data, error } = await supabase.auth.getUser()

  if (error) {
    console.error('[PreVisit] getUser error:', error)
    errorMessage.value = 'Unable to verify your session. Try refreshing the page.'
    loadingUser.value = false
    return
  }

  if (data?.user) {
    userEmail.value = data.user.email ?? null
    currentUserId.value = data.user.id
  }

  loadingUser.value = false
})

const onSubmit = async () => {
  errorMessage.value = ''
  successMessage.value = ''

  if (!currentUserId.value) {
    errorMessage.value = 'Please log in before submitting the pre-visit form.'
    return
  }

  if (!painLevel.value || !concern.value.trim()) {
    errorMessage.value = 'Please fill in your pain level and area of concern.'
    return
  }

  isSubmitting.value = true

  const { data, error } = await supabase
    .from('previsit_forms')
    .insert({
      user_id: currentUserId.value,
      pain_level: painLevel.value,
      concern: concern.value.trim(),
      notes: notes.value.trim() || null
    })
    .select('id, user_id, pain_level, concern, notes, created_at')
    .single()

  if (error) {
    console.error('[PreVisit] Insert error:', error)
    errorMessage.value = 'Could not submit your pre-visit form. Please try again.'
    isSubmitting.value = false
    return
  }

  if (data) {
    lastSubmitted.value = data as PrevisitFormRow
    successMessage.value = 'Thanks! Your pre-visit information has been saved for your dentist.'
  }

  // reset form fields
  painLevel.value = null
  concern.value = ''
  notes.value = ''

  isSubmitting.value = false
}
</script>

<style scoped>
.page {
  max-width: 800px;
  margin: 2rem auto;
  padding: 1.5rem 1.25rem 2.25rem;
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
  margin-bottom: 1.25rem;
}

.user-banner {
  font-size: 0.9rem;
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  background: rgba(15, 23, 42, 0.95);
  border: 1px solid rgba(148, 163, 184, 0.45);
  margin-bottom: 0.75rem;
}

.highlight {
  color: #38bdf8;
  font-weight: 500;
}

.error-banner {
  margin-bottom: 0.5rem;
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  background: rgba(153, 27, 27, 0.95);
  border: 1px solid rgba(248, 113, 113, 0.9);
  color: #fee2e2;
  font-size: 0.85rem;
}

.success-banner {
  margin-bottom: 0.5rem;
  padding: 0.5rem 0.75rem;
  border-radius: 0.75rem;
  background: rgba(22, 163, 74, 0.95);
  border: 1px solid rgba(74, 222, 128, 0.9);
  color: #ecfdf5;
  font-size: 0.85rem;
}

.card {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  padding: 1.25rem 1.1rem;
  border-radius: 1rem;
  background: #020617;
  border: 1px solid #1f2937;
}

label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.9rem;
}

input,
textarea {
  width: 100%;
  padding: 0.5rem 0.6rem;
  border-radius: 0.6rem;
  border: 1px solid #334155;
  background: #020617;
  color: #e5e7eb;
  font-size: 0.9rem;
}

textarea {
  resize: vertical;
}

input::placeholder,
textarea::placeholder {
  color: #6b7280;
}

button {
  margin-top: 0.5rem;
  padding: 0.6rem 1rem;
  border-radius: 999px;
  border: none;
  background: linear-gradient(135deg, #22d3ee, #38bdf8, #6366f1);
  color: #020617;
  font-weight: 500;
  font-size: 0.9rem;
  cursor: pointer;
  transition: transform 0.1s ease, box-shadow 0.1s ease;
  box-shadow: 0 10px 24px rgba(56, 189, 248, 0.45);
}

button[disabled] {
  opacity: 0.55;
  cursor: not-allowed;
  box-shadow: none;
}

button:not([disabled]):hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 30px rgba(56, 189, 248, 0.7);
}

.success {
  color: #bbf7d0;
  font-size: 0.85rem;
  margin-top: 0.5rem;
}

.summary {
  margin-top: 1rem;
  padding-top: 0.75rem;
  border-top: 1px dashed #334155;
  font-size: 0.85rem;
}

.summary h3 {
  font-size: 0.95rem;
  margin-bottom: 0.35rem;
}

.summary-meta {
  margin-top: 0.3rem;
  color: #9ca3af;
}

.hint {
  margin-top: 0.4rem;
  font-size: 0.8rem;
  color: #9ca3af;
}
</style>
