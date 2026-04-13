package com.badas.util;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.nio.charset.StandardCharsets;

public final class SecurityUtils {

    private SecurityUtils() {}

    /**
     * Hashes a password using SHA-256.
     * Returns a 64-character lowercase hex string.
     */
    public static String hashPassword(String plaintext) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] hash = md.digest(plaintext.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte b : hash) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 is guaranteed to be available in all Java SE implementations
            throw new RuntimeException("SHA-256 algorithm not available", e);
        }
    }

    /**
     * Verifies a plaintext password against a stored SHA-256 hash.
     */
    public static boolean verifyPassword(String plaintext, String storedHash) {
        if (plaintext == null || storedHash == null) return false;
        return hashPassword(plaintext).equals(storedHash);
    }

    /**
     * Masks a password string for display (e.g., in tables).
     */
    public static String maskPassword(String password) {
        if (password == null || password.isEmpty()) return "";
        return "\u2022".repeat(Math.min(password.length(), 8));
    }
}
