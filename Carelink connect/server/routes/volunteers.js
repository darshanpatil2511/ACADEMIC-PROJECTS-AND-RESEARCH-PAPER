const router = require('express').Router();
const supabase = require('../config/supabase');
const { authenticate, requireRole } = require('../middleware/authenticate');

// GET /api/volunteers — admin only
router.get('/', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, name, email, phone, availability, skills, bio, is_active, created_at')
      .eq('role', 'volunteer')
      .order('created_at', { ascending: false });

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/volunteers/:id — admin or the volunteer themselves
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    if (req.user.role !== 'admin' && req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'Access denied.' });
    }

    const { data, error } = await supabase
      .from('profiles')
      .select('id, name, email, phone, availability, skills, bio, is_active, created_at')
      .eq('id', req.params.id)
      .eq('role', 'volunteer')
      .single();

    if (error || !data) return res.status(404).json({ error: 'Volunteer not found.' });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// PUT /api/volunteers/:id — admin or volunteer updates own profile
router.put('/:id', authenticate, async (req, res, next) => {
  try {
    if (req.user.role !== 'admin' && req.user.id !== req.params.id) {
      return res.status(403).json({ error: 'Access denied.' });
    }

    const allowed = ['name', 'phone', 'availability', 'skills', 'bio'];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => allowed.includes(k))
    );
    updates.updated_at = new Date().toISOString();

    const { data, error } = await supabase
      .from('profiles')
      .update(updates)
      .eq('id', req.params.id)
      .select('id, name, email, phone, availability, skills, bio')
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// DELETE /api/volunteers/:id — admin deactivates volunteer
router.delete('/:id', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { error } = await supabase
      .from('profiles')
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) return next(error);
    res.json({ message: 'Volunteer deactivated.' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
