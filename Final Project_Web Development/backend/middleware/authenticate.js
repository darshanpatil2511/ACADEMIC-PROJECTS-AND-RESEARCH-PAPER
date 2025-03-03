const jwt = require("jsonwebtoken");

// Middleware to authenticate the user
const authenticate = (req, res, next) => {
    try {
        // Extract the token from the Authorization header
        const authHeader = req.headers.authorization;
        const token = authHeader && authHeader.split(" ")[1];

        if (!token) {
            return res.status(401).json({
                error: "Access denied. No token provided.",
            });
        }

        // Verify the token
        jwt.verify(token, process.env.JWT_SECRET, (err, decoded) => {
            if (err) {
                console.error("Token verification error:", err.message);
                return res.status(403).json({
                    error: "Invalid or expired token.",
                });
            }

            req.user = decoded; // Attach the verified user to the request object
            next(); // Proceed to the next middleware or route handler
        });
    } catch (err) {
        console.error("Authentication error:", err.message);
        res.status(500).json({
            error: "An internal server error occurred during authentication.",
        });
    }
};

module.exports = authenticate;
