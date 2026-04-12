const router = require('express').Router();
const supabase = require('../config/supabase');
const { authenticate, requireRole } = require('../middleware/authenticate');

// GET /api/tasks — public, with optional ?category=&status= filters
router.get('/', async (req, res, next) => {
  try {
    let query = supabase
      .from('tasks')
      .select('*, volunteer:assigned_volunteer_id(id, name, email)')
      .order('created_at', { ascending: false });

    if (req.query.category) query = query.eq('category', req.query.category);
    if (req.query.status)   query = query.eq('status', req.query.status);

    const { data, error } = await query;
    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// GET /api/tasks/:id — public
router.get('/:id', async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('tasks')
      .select('*, volunteer:assigned_volunteer_id(id, name, email), creator:created_by(id, name)')
      .eq('id', req.params.id)
      .single();

    if (error || !data) return res.status(404).json({ error: 'Task not found.' });
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/tasks — admin only
router.post('/', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { title, description, category, priority, due_date } = req.body;
    if (!title || !description || !category) {
      return res.status(400).json({ error: 'Title, description, and category are required.' });
    }

    const { data, error } = await supabase
      .from('tasks')
      .insert({
        title: title.trim(),
        description: description.trim(),
        category,
        priority: priority || 'medium',
        due_date: due_date || null,
        created_by: req.user.id,
      })
      .select()
      .single();

    if (error) return next(error);
    res.status(201).json(data);
  } catch (err) {
    next(err);
  }
});

// PUT /api/tasks/:id — admin only (full edit including assign)
router.put('/:id', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const allowed = ['title', 'description', 'category', 'status', 'priority', 'due_date', 'assigned_volunteer_id'];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => allowed.includes(k))
    );
    updates.updated_at = new Date().toISOString();

    const { data, error } = await supabase
      .from('tasks')
      .update(updates)
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/tasks/:id/accept — volunteer self-assigns
router.post('/:id/accept', authenticate, requireRole('volunteer'), async (req, res, next) => {
  try {
    const { data: task } = await supabase
      .from('tasks')
      .select('status, assigned_volunteer_id')
      .eq('id', req.params.id)
      .single();

    if (!task) return res.status(404).json({ error: 'Task not found.' });
    if (task.status !== 'available') {
      return res.status(400).json({ error: 'This task is no longer available.' });
    }

    const { data, error } = await supabase
      .from('tasks')
      .update({ assigned_volunteer_id: req.user.id, status: 'in_progress', updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

// POST /api/tasks/:id/complete — volunteer marks done
router.post('/:id/complete', authenticate, requireRole('volunteer'), async (req, res, next) => {
  try {
    const { data: task } = await supabase
      .from('tasks')
      .select('assigned_volunteer_id')
      .eq('id', req.params.id)
      .single();

    if (!task) return res.status(404).json({ error: 'Task not found.' });
    if (task.assigned_volunteer_id !== req.user.id) {
      return res.status(403).json({ error: 'You are not assigned to this task.' });
    }

    const { data, error } = await supabase
      .from('tasks')
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

// DELETE /api/tasks/:id — admin only
router.delete('/:id', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { error } = await supabase.from('tasks').delete().eq('id', req.params.id);
    if (error) return next(error);
    res.json({ message: 'Task deleted.' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
