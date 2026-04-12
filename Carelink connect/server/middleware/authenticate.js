const jwt = require('jsonwebtoken');

/**
 * Verifies the Bearer JWT and attaches decoded user to req.user.
 * Decoded payload shape: { id, name, role }
 */
const authenticate = (req, res, next) => {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided.' });
  }
  const token = auth.split(' ')[1];
  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
};

/**
 * Restricts a route to one or more roles.
 * Usage: router.delete('/:id', authenticate, requireRole('admin'), handler)
 */
const requireRole = (...roles) => (req, res, next) => {
  if (!roles.includes(req.user?.role)) {
    return res.status(403).json({ error: 'Access denied.' });
  }
  next();
};

module.exports = { authenticate, requireRole };
