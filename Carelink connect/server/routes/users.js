const router = require('express').Router();
const supabase = require('../config/supabase');
const { authenticate, requireRole } = require('../middleware/authenticate');

// GET /api/users/me — own profile
router.get('/me', authenticate, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, name, email, role, phone, availability, skills, bio, is_active, created_at')
      .eq('id', req.user.id)
      .single();

    if (error || !data) return res.status(404).json({ error: 'Profile not found.' });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// PUT /api/users/me — update own profile
router.put('/me', authenticate, async (req, res, next) => {
  try {
    const allowed = ['name', 'phone', 'availability', 'skills', 'bio'];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => allowed.includes(k))
    );
    updates.updated_at = new Date().toISOString();

    const { data, error } = await supabase
      .from('profiles')
      .update(updates)
      .eq('id', req.user.id)
      .select('id, name, email, role, phone, availability, skills, bio')
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/users — admin: list all users (seniors)
router.get('/', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, name, email, phone, role, is_active, created_at')
      .eq('role', 'user')
      .order('created_at', { ascending: false });

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
