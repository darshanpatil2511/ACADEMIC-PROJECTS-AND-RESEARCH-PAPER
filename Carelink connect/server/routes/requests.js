const router = require('express').Router();
const supabase = require('../config/supabase');
const { authenticate, requireRole } = require('../middleware/authenticate');

// GET /api/requests
// admin: all requests | volunteer: pending/accepted/in_progress | user: own requests only
router.get('/', authenticate, async (req, res, next) => {
  try {
    let query = supabase
      .from('requests')
      .select('*, user:user_id(id, name, email, phone), volunteer:assigned_volunteer_id(id, name, email)')
      .order('created_at', { ascending: false });

    if (req.user.role === 'user') {
      query = query.eq('user_id', req.user.id);
    } else if (req.user.role === 'volunteer') {
      query = query.in('status', ['pending', 'accepted', 'in_progress']);
    }
    // admin sees everything

    const { data, error } = await query;
    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/requests/:id
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('requests')
      .select('*, user:user_id(id, name, email, phone), volunteer:assigned_volunteer_id(id, name, email)')
      .eq('id', req.params.id)
      .single();

    if (error || !data) return res.status(404).json({ error: 'Request not found.' });

    // Users can only see their own requests
    if (req.user.role === 'user' && data.user_id !== req.user.id) {
      return res.status(403).json({ error: 'Access denied.' });
    }
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/requests — user/senior submits a request
router.post('/', authenticate, requireRole('user'), async (req, res, next) => {
  try {
    const { service_type, description, scheduled_date, scheduled_time, compensation_amount } = req.body;
    if (!service_type || !scheduled_date || !scheduled_time) {
      return res.status(400).json({ error: 'Service type, date, and time are required.' });
    }

    // Membership gate: user must have a succeeded payment
    const { data: membership } = await supabase
      .from('payments')
      .select('id')
      .eq('user_id', req.user.id)
      .eq('status', 'succeeded')
      .limit(1)
      .maybeSingle();
    if (!membership) {
      return res.status(403).json({ error: 'An active membership is required to submit requests.', code: 'NO_MEMBERSHIP' });
    }

    const amount = parseInt(compensation_amount, 10);
    if (isNaN(amount) || amount < 0) {
      return res.status(400).json({ error: 'Invalid compensation amount.' });
    }

    const { data, error } = await supabase
      .from('requests')
      .insert({
        user_id: req.user.id,
        service_type,
        description: description || null,
        scheduled_date,
        scheduled_time,
        compensation_amount: amount,
        status: 'pending',
      })
      .select()
      .single();

    if (error) return next(error);
    res.status(201).json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/requests/:id/accept — volunteer accepts a pending request
router.post('/:id/accept', authenticate, requireRole('volunteer'), async (req, res, next) => {
  try {
    const { data: existing } = await supabase
      .from('requests')
      .select('status')
      .eq('id', req.params.id)
      .single();

    if (!existing) return res.status(404).json({ error: 'Request not found.' });
    if (existing.status !== 'pending') {
      return res.status(400).json({ error: 'This request is no longer pending.' });
    }

    const { data, error } = await supabase
      .from('requests')
      .update({ assigned_volunteer_id: req.user.id, status: 'accepted', updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/requests/:id/complete — volunteer marks request done
router.post('/:id/complete', authenticate, requireRole('volunteer'), async (req, res, next) => {
  try {
    const { data: existing } = await supabase
      .from('requests')
      .select('assigned_volunteer_id')
      .eq('id', req.params.id)
      .single();

    if (!existing) return res.status(404).json({ error: 'Request not found.' });
    if (existing.assigned_volunteer_id !== req.user.id) {
      return res.status(403).json({ error: 'You are not assigned to this request.' });
    }

    const { data, error } = await supabase
      .from('requests')
      .update({ status: 'completed', updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/requests/:id/cancel — user cancels own or admin cancels any
router.post('/:id/cancel', authenticate, async (req, res, next) => {
  try {
    const { data: existing } = await supabase
      .from('requests')
      .select('user_id, status')
      .eq('id', req.params.id)
      .single();

    if (!existing) return res.status(404).json({ error: 'Request not found.' });
    if (req.user.role === 'user' && existing.user_id !== req.user.id) {
      return res.status(403).json({ error: 'Access denied.' });
    }
    if (existing.status === 'completed') {
      return res.status(400).json({ error: 'Cannot cancel a completed request.' });
    }

    const { data, error } = await supabase
      .from('requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
