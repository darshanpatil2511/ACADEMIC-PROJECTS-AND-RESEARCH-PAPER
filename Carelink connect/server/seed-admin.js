/**
 * seed-admin.js
 * Run once to create the admin user in Supabase.
 * Usage: node seed-admin.js
 */
require('dotenv').config();
const bcrypt   = require('bcryptjs');
const supabase = require('./config/supabase');

const ADMIN = {
  name:     'Admin',
  email:    'admin@carelink.com',
  password: 'Admin@1234',   // change after first login
  role:     'admin',
};

async function seed() {
  console.log('Seeding admin user…');

  const { data: existing } = await supabase
    .from('profiles')
    .select('id')
    .eq('email', ADMIN.email)
    .single();

  if (existing) {
    console.log('Admin already exists — skipping.');
    process.exit(0);
  }

  const hash = await bcrypt.hash(ADMIN.password, 12);

  const { data, error } = await supabase
    .from('profiles')
    .insert({ name: ADMIN.name, email: ADMIN.email, password_hash: hash, role: 'admin' })
    .select('id, name, email, role')
    .single();

  if (error) { console.error('Seed failed:', error.message); process.exit(1); }

  console.log('Admin created successfully:');
  console.log(`  Email:    ${data.email}`);
  console.log(`  Password: ${ADMIN.password}`);
  console.log(`  Role:     ${data.role}`);
  console.log('\nRemember to change the password after first login!');
  process.exit(0);
}

seed();
