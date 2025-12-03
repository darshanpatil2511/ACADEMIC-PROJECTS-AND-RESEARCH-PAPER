<template>
  <div class="page">
    <h2>Log in to PatientConnect</h2>
    <p class="subtitle">
      Sign in with the email and password you used to register. After logging in, you can view your
      appointments and complete pre-visit forms.
    </p>

    <form @submit.prevent="onSubmit" class="card">
      <label>
        Email
        <input v-model="email" type="email" required placeholder="you@example.com" />
      </label>

      <label>
        Password
        <input v-model="password" type="password" required placeholder="Your password" />
      </label>

      <button type="submit" :disabled="loading">
        {{ loading ? 'Signing in…' : 'Sign In' }}
      </button>

      <p v-if="error" class="error">{{ error }}</p>
    </form>

    <p class="meta">
      Don’t have an account?
      <router-link to="/register">Create one here</router-link>.
    </p>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'

const router = useRouter()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

const onSubmit = async () => {
  error.value = ''
  loading.value = true

  const { data, error: signInError } = await supabase.auth.signInWithPassword({
    email: email.value,
    password: password.value
  })

  loading.value = false

  if (signInError) {
    error.value = signInError.message
    return
  }

  if (data.session) {
    router.push('/appointments')
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
  margin-top: 0.35rem;
}

.meta {
  margin-top: 1rem;
  font-size: 0.85rem;
  color: #e5e7eb;
}
</style>
