<template>
  <section class="page">
    <h2>Welcome to PatientConnect</h2>
    <p class="subtitle">
      A modern digital platform for patient engagement, appointment management, and streamlined clinical workflows
    </p>

    <div class="grid">
      <div class="card">
        <h3>For Patients</h3>
        <ul>
          <li>Secure login and account creation</li>
          <li>View your upcoming appointments</li>
          <li>Complete a pre-visit questionnaire before you arrive</li>
        </ul>
      </div>

      <div class="card">
        <h3>For the Dental Team</h3>
        <ul>
          <li>Structured pre-visit info to prepare for each appointment</li>
          <li>Reduced manual data entry and phone calls</li>
          <li>A scalable digital foundation for advanced automation</li>
        </ul>
      </div>
    </div>

    <div class="cta-row">
      <router-link to="/register" class="btn primary">Get Started as a Patient</router-link>
      <router-link to="/login" class="btn">Already have an account? Log in</router-link>
    </div>
  </section>
</template>

<script setup lang="ts">
</script>

<style scoped>
.page {
  max-width: 880px;
  margin: 2rem auto;
  padding: 1.5rem 1.25rem 2.5rem;
  border-radius: 1.25rem;
  background: radial-gradient(circle at top left, rgba(56, 189, 248, 0.12), transparent 55%),
    radial-gradient(circle at bottom right, rgba(129, 140, 248, 0.16), transparent 55%),
    rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(148, 163, 184, 0.35);
  box-shadow: 0 18px 45px rgba(15, 23, 42, 0.85);
}

h2 {
  font-size: 1.8rem;
  margin-bottom: 0.4rem;
}

.subtitle {
  margin-bottom: 1.5rem;
  color: #e5e7eb;
  font-size: 0.98rem;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 1.25rem;
  margin-bottom: 1.75rem;
}

.card {
  padding: 1.1rem 1rem;
  border-radius: 0.9rem;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(51, 65, 85, 0.9);
}

.card h3 {
  font-size: 1.05rem;
  margin-bottom: 0.5rem;
}

.card ul {
  list-style: none;
  padding: 0;
  margin: 0;
}

.card li {
  font-size: 0.9rem;
  margin-bottom: 0.35rem;
  color: #e5e7eb;
}

.cta-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.6rem 1.2rem;
  border-radius: 999px;
  font-size: 0.9rem;
  text-decoration: none;
  border: 1px solid rgba(148, 163, 184, 0.6);
  color: #e5e7eb;
  background: transparent;
  transition: background 0.15s ease, color 0.15s ease, transform 0.1s ease, box-shadow 0.1s ease;
}

.btn.primary {
  background: linear-gradient(135deg, #22d3ee, #38bdf8, #6366f1);
  border-color: transparent;
  color: #020617;
  box-shadow: 0 8px 22px rgba(56, 189, 248, 0.45);
}

.btn:hover {
  transform: translateY(-1px);
  box-shadow: 0 10px 26px rgba(15, 23, 42, 0.85);
}

.btn.primary:hover {
  box-shadow: 0 12px 30px rgba(56, 189, 248, 0.65);
}

@media (max-width: 640px) {
  .page {
    margin: 1.5rem 1rem;
    padding: 1.25rem 1rem 2rem;
  }
}
</style>
