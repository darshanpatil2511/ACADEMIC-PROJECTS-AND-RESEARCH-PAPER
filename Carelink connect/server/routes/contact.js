const router = require('express').Router();
const supabase = require('../config/supabase');

// POST /api/contact — public, no auth required
router.post('/', async (req, res, next) => {
  try {
    const { name, email, subject, message } = req.body;
    if (!name || !email || !subject || !message) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email address.' });
    }

    const { error } = await supabase
      .from('contacts')
      .insert({ name: name.trim(), email: email.toLowerCase(), subject: subject.trim(), message: message.trim() });

    if (error) return next(error);
    res.status(201).json({ message: 'Message sent successfully. We\'ll get back to you soon!' });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
