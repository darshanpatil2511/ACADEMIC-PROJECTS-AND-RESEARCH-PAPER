<template>
  <div class="page">
    <h2>Create your PatientConnect account</h2>
    <p class="subtitle">
      Use your email and a secure password to register. You’ll use this account to book appointments
      and complete pre-visit forms.
    </p>

    <form @submit.prevent="onSubmit" class="card">
      <label>
        Full name
        <input
          v-model="fullName"
          type="text"
          required
          placeholder="Your full name"
        />
      </label>

      <label>
        Email
        <input v-model="email" type="email" required placeholder="you@example.com" />
      </label>

      <label>
        Password
        <input
          v-model="password"
          type="password"
          required
          minlength="6"
          placeholder="At least 6 characters"
        />
      </label>

      <label>
        Confirm password
        <input
          v-model="confirmPassword"
          type="password"
          required
          minlength="6"
          placeholder="Re-enter your password"
        />
      </label>

      <button type="submit" :disabled="loading">
        {{ loading ? 'Creating account…' : 'Register' }}
      </button>

      <p v-if="error" class="error">{{ error }}</p>
      <p v-if="success" class="success">
        Registration successful. Please check your email to confirm your account, then
        <router-link to="/login">log in</router-link>.
      </p>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { supabase } from '../supabaseClient'

const fullName = ref('')
const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const loading = ref(false)
const error = ref('')
const success = ref(false)

const onSubmit = async () => {
  error.value = ''
  success.value = false

  if (password.value !== confirmPassword.value) {
    error.value = 'Passwords do not match. Please re-enter them.'
    return
  }

  loading.value = true

  const { error: signUpError } = await supabase.auth.signUp({
    email: email.value,
    password: password.value,
    options: {
      data: {
        full_name: fullName.value
      }
    }
  })

  loading.value = false

  if (signUpError) {
    error.value = signUpError.message
  } else {
    success.value = true
    // Optionally clear sensitive fields after successful registration
    password.value = ''
    confirmPassword.value = ''
  }
}
</script>

<style scoped>
.page {
  max-width: 420px;
  margin: 2.5rem auto;
  padding: 1.5rem 1.25rem 2rem;
  border-radius: 1rem;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.4);
  box-shadow: 0 18px 45px rgba(15, 23, 42, 0.85);
  font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

h2 {
  font-size: 1.4rem;
  margin-bottom: 0.4rem;
}

.subtitle {
  font-size: 0.9rem;
  color: #e5e7eb;
  margin-bottom: 1.25rem;
}

.card {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
}

label {
  font-size: 0.9rem;
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}

input {
  width: 100%;
  padding: 0.5rem 0.6rem;
  border-radius: 0.6rem;
  border: 1px solid #334155;
  background: #020617;
  color: #e5e7eb;
  font-size: 0.9rem;
}

input::placeholder {
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
  opacity: 0.7;
  cursor: default;
  box-shadow: none;
}

button:not([disabled]):hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 30px rgba(56, 189, 248, 0.7);
}

.error {
  color: #fecaca;
  font-size: 0.85rem;
}

.success {
  color: #bbf7d0;
  font-size: 0.85rem;
  margin-top: 0.25rem;
}
</style>