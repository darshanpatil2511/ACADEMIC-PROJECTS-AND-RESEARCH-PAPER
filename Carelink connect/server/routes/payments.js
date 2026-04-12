const router = require('express').Router();
const Stripe = require('stripe');
const supabase = require('../config/supabase');
const { authenticate } = require('../middleware/authenticate');

const stripe = Stripe(process.env.STRIPE_SECRET_KEY);

const TIER_AMOUNTS = { basic: 1000, premium: 2500, elite: 5000 }; // cents

// POST /api/payments/create-payment-intent — authenticated users only
router.post('/create-payment-intent', authenticate, async (req, res, next) => {
  try {
    const { tier } = req.body;
    if (!TIER_AMOUNTS[tier]) {
      return res.status(400).json({ error: 'Invalid tier. Choose basic, premium, or elite.' });
    }

    const amount = TIER_AMOUNTS[tier];
    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency: 'usd',
      automatic_payment_methods: { enabled: true },
      metadata: { userId: req.user.id, tier },
    });

    // Record pending payment in DB
    await supabase.from('payments').insert({
      user_id: req.user.id,
      tier,
      amount,
      stripe_payment_id: paymentIntent.id,
      status: 'pending',
    });

    res.json({ clientSecret: paymentIntent.client_secret });
  } catch (err) {
    next(err);
  }
});

// POST /api/payments/webhook — raw body (mounted before express.json() in server.js)
router.post('/webhook', async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;

  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    console.error('[Stripe Webhook] Signature check failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  if (event.type === 'payment_intent.succeeded') {
    await supabase
      .from('payments')
      .update({ status: 'succeeded' })
      .eq('stripe_payment_id', event.data.object.id);
  } else if (event.type === 'payment_intent.payment_failed') {
    await supabase
      .from('payments')
      .update({ status: 'failed' })
      .eq('stripe_payment_id', event.data.object.id);
  }

  res.json({ received: true });
});

// POST /api/payments/confirm — client calls this after Stripe confirms; we verify with Stripe and update DB
router.post('/confirm', authenticate, async (req, res, next) => {
  try {
    const { paymentIntentId } = req.body;
    if (!paymentIntentId) return res.status(400).json({ error: 'paymentIntentId is required.' });

    // Verify with Stripe directly (can't be spoofed)
    const intent = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (intent.status !== 'succeeded') {
      return res.status(400).json({ error: 'Payment has not succeeded yet.' });
    }

    // Mark as succeeded in DB
    const { error } = await supabase
      .from('payments')
      .update({ status: 'succeeded' })
      .eq('stripe_payment_id', paymentIntentId)
      .eq('user_id', req.user.id);

    if (error) return next(error);
    res.json({ ok: true });
  } catch (err) { next(err); }
});

// GET /api/payments/status — does this user have an active (succeeded) membership?
router.get('/status', authenticate, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('payments')
      .select('tier, created_at')
      .eq('user_id', req.user.id)
      .eq('status', 'succeeded')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) return next(error);
    res.json({ hasMembership: !!data, tier: data?.tier || null, since: data?.created_at || null });
  } catch (err) { next(err); }
});

// GET /api/payments/my — get logged-in user's payments
router.get('/my', authenticate, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('payments')
      .select('*')
      .eq('user_id', req.user.id)
      .order('created_at', { ascending: false });

    if (error) return next(error);
    res.json(data);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
