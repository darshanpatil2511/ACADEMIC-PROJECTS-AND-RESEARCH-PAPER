const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const router = express.Router();
const User = require("../models/User");

// Environment variables for sensitive data
const JWT_SECRET = process.env.JWT_SECRET || "default_secret_key"; // Ensure secure key in production
const JWT_EXPIRY = process.env.JWT_EXPIRY || "1h"; // Token expiry duration

// Helper function to send error responses
const handleError = (res, status, message) => {
  return res.status(status).json({ error: message });
};

// Signup Route
router.post("/signup", async (req, res) => {
  const { name, email, password, role } = req.body;

  try {
    // Check if user already exists
    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return handleError(res, 400, "Email already registered.");
    }

    // Hash the password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create and save the new user
    const newUser = new User({ name, email, password: hashedPassword, role });
    await newUser.save();

    res.status(201).json({ message: "User registered successfully!" });
  } catch (err) {
    console.error("Error during signup:", err.message);
    handleError(res, 500, "Server error. Please try again later.");
  }
});

// Login Route
router.post("/login", async (req, res) => {
  const { email, password } = req.body;

  try {
    // Validate input
    if (!email || !password) {
      return handleError(res, 400, "Email and password are required.");
    }

    // Find the user by email
    const user = await User.findOne({ email });
    if (!user) {
      return handleError(res, 400, "Invalid email or password");
    }

    // Compare the provided password with the hashed password
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return handleError(res, 400, "Invalid email or password");
    }

    // Generate a JWT token
    const token = jwt.sign(
      { id: user._id, role: user.role },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    res.json({
      message: "Login successful",
      token,
      role: user.role, // Send role for client-side handling
      name: user.name, // Send user's name for personalized client-side UI
    });

    // Optionally update the last login timestamp
    if (typeof user.updateLastLogin === "function") {
      await user.updateLastLogin();
    }
  } catch (err) {
    console.error("Error during login:", err.message);
    handleError(res, 500, "Server error. Please try again later.");
  }
});

// Middleware to verify token
const verifyToken = (req, res, next) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return handleError(res, 401, "Access denied. No token provided.");
  }

  try {
    const verified = jwt.verify(token, JWT_SECRET);
    req.user = verified; // Attach user information to the request object
    next();
  } catch (err) {
    console.error("Token verification error:", err.message);
    handleError(res, 403, "Invalid or expired token.");
  }
};

module.exports = router;
