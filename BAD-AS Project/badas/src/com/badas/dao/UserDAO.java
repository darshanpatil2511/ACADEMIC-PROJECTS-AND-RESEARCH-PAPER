package com.badas.dao;

import com.badas.model.User;
import com.badas.util.SecurityUtils;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class UserDAO {

    private final DatabaseManager db = DatabaseManager.getInstance();

    public User findByUsername(String username) {
        String sql = "SELECT * FROM users WHERE username = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, username);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            System.err.println("UserDAO.findByUsername: " + e.getMessage());
        }
        return null;
    }

    public boolean verifyPassword(String username, String plaintext) {
        User user = findByUsername(username);
        if (user == null) return false;
        return SecurityUtils.verifyPassword(plaintext, user.getPasswordHash());
    }

    public List<User> findAll() {
        List<User> list = new ArrayList<>();
        String sql = "SELECT * FROM users ORDER BY username";
        try (Connection conn = db.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) {
            System.err.println("UserDAO.findAll: " + e.getMessage());
        }
        return list;
    }

    public boolean save(String username, String plainPassword, String role) {
        String sql = "INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, username.trim());
            ps.setString(2, SecurityUtils.hashPassword(plainPassword));
            ps.setString(3, role.trim());
            ps.executeUpdate();
            return true;
        } catch (SQLException e) {
            System.err.println("UserDAO.save: " + e.getMessage());
            return false;
        }
    }

    public boolean update(int id, String username, String newPlainPassword, String role) {
        String sql = "UPDATE users SET username = ?, password_hash = ?, role = ? WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, username.trim());
            ps.setString(2, SecurityUtils.hashPassword(newPlainPassword));
            ps.setString(3, role.trim());
            ps.setInt(4, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("UserDAO.update: " + e.getMessage());
            return false;
        }
    }

    public boolean resetPassword(int id, String newPlainPassword) {
        String sql = "UPDATE users SET password_hash = ? WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, SecurityUtils.hashPassword(newPlainPassword));
            ps.setInt(2, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("UserDAO.resetPassword: " + e.getMessage());
            return false;
        }
    }

    public boolean delete(int id) {
        String sql = "DELETE FROM users WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("UserDAO.delete: " + e.getMessage());
            return false;
        }
    }

    public void updateLastLogin(String username) {
        String sql = "UPDATE users SET last_login = datetime('now','localtime') WHERE username = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, username);
            ps.executeUpdate();
        } catch (SQLException e) {
            System.err.println("UserDAO.updateLastLogin: " + e.getMessage());
        }
    }

    private User mapRow(ResultSet rs) throws SQLException {
        User u = new User();
        u.setId(rs.getInt("id"));
        u.setUsername(rs.getString("username"));
        u.setPasswordHash(rs.getString("password_hash"));
        u.setRole(rs.getString("role"));
        u.setCreatedAt(rs.getString("created_at"));
        u.setLastLogin(rs.getString("last_login"));
        return u;
    }
}
