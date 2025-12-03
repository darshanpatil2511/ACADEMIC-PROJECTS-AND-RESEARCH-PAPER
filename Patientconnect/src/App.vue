<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRouter, RouterLink, RouterView } from 'vue-router'
import { useAuth } from '@/composables/useAuth'

const router = useRouter()
const { user, loading, fetchUser, logout } = useAuth()

const authUser = computed(() => user.value)
const authLoading = computed(() => loading.value)

onMounted(() => {
  // Check Supabase session once when the app bootstraps
  fetchUser()
})

async function handleLogout() {
  await logout()
  router.push('/')
}
</script>

<template>
  <div class="app">
    <header class="nav">
      <div class="nav-left">
        <span class="logo-dot" />
        <h1 class="logo-text">PatientConnect</h1>
      </div>

      <nav class="nav-links">
        <RouterLink to="/">Home</RouterLink>
        <RouterLink to="/appointments">Appointments</RouterLink>
        <RouterLink to="/pre-visit">Pre-Visit Form</RouterLink>
      </nav>

      <div class="nav-right">
        <span v-if="authLoading" class="auth-status">Checking session…</span>

        <template v-else>
          <!-- Logged-in state -->
          <div v-if="authUser" class="auth-controls">
            <span class="user-email">{{ authUser.email }}</span>
            <button type="button" class="ghost-btn" @click="handleLogout">Log out</button>
          </div>

          <!-- Logged-out state -->
          <div v-else class="auth-controls">
            <RouterLink to="/login" class="ghost-link">Login</RouterLink>
            <RouterLink to="/register" class="ghost-link">Register</RouterLink>
          </div>
        </template>
      </div>
    </header>

    <main class="main">
      <RouterView />
    </main>
  </div>
</template>

<style scoped>
.app {
  font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  min-height: 100vh;
  background: radial-gradient(circle at top, #0f172a 0, #020617 50%, #000 100%);
  color: #f9fafb;
}

/* Top nav */
.nav {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1.5rem;
  border-bottom: 1px solid rgba(148, 163, 184, 0.35);
  background: rgba(15, 23, 42, 0.9);
  backdrop-filter: blur(10px);
}

.nav-left {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.logo-dot {
  width: 16px;
  height: 16px;
  border-radius: 999px;
  background: conic-gradient(from 180deg, #22d3ee, #38bdf8, #a855f7, #22d3ee);
  box-shadow: 0 0 12px rgba(56, 189, 248, 0.7);
}

.logo-text {
  font-size: 1.1rem;
  font-weight: 600;
  letter-spacing: 0.04em;
}

.nav-links {
  display: flex;
  gap: 1rem;
  font-size: 0.9rem;
}

.nav-links a {
  color: #e5e7eb;
  text-decoration: none;
  padding: 0.3rem 0.6rem;
  border-radius: 999px;
  transition: background 0.15s ease, color 0.15s ease, transform 0.1s ease;
}

.nav-links a.router-link-exact-active {
  background: rgba(56, 189, 248, 0.16);
  color: #38bdf8;
}

.nav-links a:hover {
  background: rgba(148, 163, 184, 0.25);
  transform: translateY(-1px);
}

/* Main content */
.main {
  padding: 1.5rem;
}

@media (min-width: 1024px) {
  .main {
    padding: 2.5rem 3.5rem;
  }
}

.nav-right {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.auth-status {
  font-size: 0.8rem;
  color: #9ca3af;
}

.auth-controls {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.user-email {
  font-size: 0.8rem;
  color: #cbd5f5;
}

.ghost-btn,
.ghost-link {
  font-size: 0.8rem;
  padding: 0.3rem 0.7rem;
  border-radius: 999px;
  border: 1px solid rgba(148, 163, 184, 0.7);
  background: transparent;
  color: #e5e7eb;
  text-decoration: none;
  cursor: pointer;
  transition: background 0.15s ease, border-color 0.15s ease, color 0.15s ease;
}

.ghost-btn:hover,
.ghost-link:hover {
  background: rgba(15, 23, 42, 0.9);
  border-color: #38bdf8;
  color: #e0f2fe;
}
</style>