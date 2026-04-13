package com.badas.service;

import com.badas.dao.UserDAO;
import com.badas.model.User;

/**
 * Singleton that manages the current logged-in session.
 * Delegates credential verification to UserDAO.
 */
public class AuthService {

    private static AuthService instance;
    private User currentUser;
    private final UserDAO userDAO = new UserDAO();

    private AuthService() {}

    public static synchronized AuthService getInstance() {
        if (instance == null) instance = new AuthService();
        return instance;
    }

    /**
     * Attempts login. Returns the User on success, null on failure.
     */
    public User login(String username, String password) {
        if (username == null || password == null) return null;
        if (!userDAO.verifyPassword(username.trim(), password)) return null;

        currentUser = userDAO.findByUsername(username.trim());
        userDAO.updateLastLogin(username.trim());
        return currentUser;
    }

    public void logout() {
        currentUser = null;
    }

    public User getCurrentUser() {
        return currentUser;
    }

    public boolean isLoggedIn() {
        return currentUser != null;
    }

    /**
     * Returns the role string in a normalized form for switch statements.
     * e.g., "Emergency Coordinator" -> "emergency coordinator"
     */
    public String getCurrentRoleLower() {
        if (currentUser == null) return "";
        return currentUser.getRole().toLowerCase();
    }
}
