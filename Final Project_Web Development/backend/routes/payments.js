const express = require("express");
const Stripe = require("stripe");
const router = express.Router();

// Load Stripe secret key from environment variables
const stripe = Stripe(process.env.STRIPE_SECRET_KEY || "sk_test_default_key"); // Replace with your actual key in .env

// Create Payment Intent Route
router.post("/create-payment-intent", async (req, res) => {
  const { amount, currency, metadata } = req.body;

  if (!amount || !currency) {
    return res.status(400).json({ error: "Amount and currency are required." });
  }

  try {
    console.log("Creating payment intent with:", { amount, currency });

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency,
      automatic_payment_methods: { enabled: true }, // Enables automatic payment methods like cards
      metadata: metadata || {}, // Optional metadata for additional information
    });

    console.log("Payment Intent created successfully:", paymentIntent.id);

    res.status(200).json({
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
    });
  } catch (error) {
    console.error("Error creating payment intent:", error.message);
    res.status(500).json({
      error: "Failed to create payment intent. Please try again.",
    });
  }
});

// Webhook for Payment Status
router.post(
  "/webhook",
  express.raw({ type: "application/json" }),
  (req, res) => {
    const sig = req.headers["stripe-signature"];

    try {
      const event = stripe.webhooks.constructEvent(
        req.body,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET // Webhook secret for validation
      );

      console.log("Webhook event received:", event.type);

      // Handle the event
      switch (event.type) {
        case "payment_intent.succeeded":
          console.log("Payment succeeded:", event.data.object);
          // Add logic to handle successful payments, e.g., updating a database
          break;
        case "payment_intent.payment_failed":
          console.error("Payment failed:", event.data.object);
          // Add logic to handle failed payments
          break;
        default:
          console.log(`Unhandled event type: ${event.type}`);
      }

      res.status(200).json({ received: true });
    } catch (err) {
      console.error("Webhook error:", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
    }
  }
);

module.exports = router;
