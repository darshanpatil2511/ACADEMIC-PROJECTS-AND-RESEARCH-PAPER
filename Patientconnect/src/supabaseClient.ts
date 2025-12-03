import { createClient, type SupabaseClient } from '@supabase/supabase-js'

// Read Vite env vars (must be prefixed with VITE_ to be exposed to the client)
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

if (!supabaseUrl || !supabaseAnonKey) {
  // Fail fast in dev so we don't accidentally talk to an empty/invalid endpoint
  console.error('[Supabase] Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY.')
  console.error(
    'Add them to your .env file at the project root, then restart the dev server.'
  )
}

/**
 * Singleton Supabase client for the PatientConnect app.
 *
 * Usage:
 *   import { supabase } from '@/supabaseClient'
 *   const { data, error } = await supabase.from('appointments').select('*')
 */
export const supabase: SupabaseClient = createClient(
  // Fallback to empty strings to satisfy the type system; if these are empty
  // the client will simply fail requests, but we log loudly above.
  supabaseUrl ?? '',
  supabaseAnonKey ?? '',
  {
    auth: {
      // Keep the user logged in across refreshes; this is the usual SPA behaviour.
      persistSession: true,
      autoRefreshToken: true,
    },
  }
)

/**
 * Helper to get the current logged‑in user id.
 * Returns `null` if there is no active session.
 */
export async function getCurrentUserId(): Promise<string | null> {
  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) {
    if (error) {
      console.error('[Supabase] getUser error:', error.message)
    }
    return null
  }
  return data.user.id
}
