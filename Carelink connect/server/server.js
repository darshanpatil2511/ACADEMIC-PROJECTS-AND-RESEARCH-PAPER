const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();
const app = express();

// Stripe webhook needs raw body — mount BEFORE express.json()
app.use('/api/payments/webhook', express.raw({ type: 'application/json' }));

app.use(cors({
  origin: process.env.CLIENT_URL || 'http://localhost:3000',
  credentials: true,
}));
app.use(express.json());

// Routes
app.use('/api/auth',       require('./routes/auth'));
app.use('/api/tasks',      require('./routes/tasks'));
app.use('/api/requests',   require('./routes/requests'));
app.use('/api/volunteers', require('./routes/volunteers'));
app.use('/api/users',      require('./routes/users'));
app.use('/api/payments',   require('./routes/payments'));
app.use('/api/contact',    require('./routes/contact'));

app.get('/health', (_req, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));

// Global error handler
app.use((err, _req, res, _next) => {
  console.error('[ERROR]', err.message);
  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
});

const PORT = process.env.PORT || 5009;
app.listen(PORT, () => console.log(`Server running → http://localhost:${PORT}`));
