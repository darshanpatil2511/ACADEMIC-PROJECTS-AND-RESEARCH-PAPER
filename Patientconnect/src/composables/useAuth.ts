

import { ref } from 'vue'
import { supabase } from '@/supabaseClient'

// Global, shared auth state for Patientconnect
const user = ref<any | null>(null)
const loading = ref<boolean>(true)
const authError = ref<string | null>(null)

async function fetchUser() {
  loading.value = true
  authError.value = null
  try {
    const { data, error } = await supabase.auth.getUser()
    if (error) {
      console.error('[Auth] getUser error', error)
      authError.value = 'Unable to check your session.'
      user.value = null
    } else {
      user.value = data.user ?? null
    }
  } finally {
    loading.value = false
  }
}

async function logout() {
  authError.value = null
  try {
    const { error } = await supabase.auth.signOut()
    if (error) {
      console.error('[Auth] signOut error', error)
      authError.value = 'Sign out failed. Please try again.'
    }
    user.value = null
  } catch (e) {
    console.error('[Auth] unexpected signOut error', e)
    authError.value = 'Sign out failed. Please try again.'
    user.value = null
  }
}

export function useAuth() {
  return {
    user,
    loading,
    authError,
    fetchUser,
    logout,
  }
}