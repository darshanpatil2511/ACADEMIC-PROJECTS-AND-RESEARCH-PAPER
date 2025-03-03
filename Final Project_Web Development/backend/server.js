const express = require("express");
const mongoose = require("mongoose");
const cors = require("cors");
const dotenv = require("dotenv");
const path = require("path");

// Initialize app and load environment variables
dotenv.config();
const app = express();

// Middleware
app.use(cors()); // Enable CORS for cross-origin requests
app.use(express.json()); // Parse JSON request bodies

// Import routes
const authRoutes = require("./routes/auth");
const taskRoutes = require("./routes/tasks");
const volunteerRoutes = require("./routes/volunteers");
const paymentRoutes = require("./routes/payments");

// MongoDB connection
mongoose
  .connect(process.env.MONGO_URI || "mongodb://localhost:27017/carelink", {
    useNewUrlParser: true,
    useUnifiedTopology: true,
  })
  .then(() => console.log("MongoDB connected successfully"))
  .catch((err) => console.error("MongoDB connection error:", err));

// API Routes
app.use("/api/auth", authRoutes); // Authentication routes
app.use("/api/tasks", taskRoutes); // Task-related routes
app.use("/api/volunteers", volunteerRoutes); // Volunteer management routes
app.use("/api/payments", paymentRoutes); // Payment processing routes

// Serve static files in production (for frontend integration)
if (process.env.NODE_ENV === "production") {
  const buildPath = path.join(__dirname, "frontend/build");
  app.use(express.static(buildPath));

  // Catch-all route to serve React app for unknown paths
  app.get("*", (req, res) => {
    res.sendFile(path.join(buildPath, "index.html"));
  });
}

// Health Check Endpoint (useful for monitoring tools)
app.get("/health", (req, res) => {
  res.status(200).json({ message: "Server is running and healthy!" });
});

// Global error handler (centralized error handling)
app.use((err, req, res, next) => {
  console.error("Unhandled error:", err.message);
  res.status(err.status || 500).json({
    message: "An internal server error occurred",
    error: process.env.NODE_ENV === "production" ? undefined : err.message,
  });
});

// Start server
const PORT = process.env.PORT || 5009;
app.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}`));
