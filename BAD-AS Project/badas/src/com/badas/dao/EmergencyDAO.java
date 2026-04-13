package com.badas.dao;

import com.badas.model.EmergencyCase;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class EmergencyDAO {

    private final DatabaseManager db = DatabaseManager.getInstance();

    public List<EmergencyCase> findAll() {
        List<EmergencyCase> list = new ArrayList<>();
        String sql = "SELECT * FROM emergency_cases ORDER BY created_at DESC";
        try (Connection conn = db.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.findAll: " + e.getMessage());
        }
        return list;
    }

    public EmergencyCase findById(int id) {
        String sql = "SELECT * FROM emergency_cases WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.findById: " + e.getMessage());
        }
        return null;
    }

    public int save(EmergencyCase ec) {
        String sql = """
            INSERT INTO emergency_cases
              (patient_name, location, symptoms, emergency_level, status, assigned_resources, coordinator)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, ec.getPatientName());
            ps.setString(2, ec.getLocation());
            ps.setString(3, ec.getSymptoms());
            ps.setString(4, ec.getEmergencyLevel());
            ps.setString(5, ec.getStatus() == null ? "Active" : ec.getStatus());
            ps.setString(6, ec.getAssignedResources() == null ? "" : ec.getAssignedResources());
            ps.setString(7, ec.getCoordinator());
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return rs.getInt(1);
            }
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.save: " + e.getMessage());
        }
        return -1;
    }

    public boolean updateStatus(int id, String status) {
        String sql = """
            UPDATE emergency_cases
            SET status = ?, updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, status);
            ps.setInt(2, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.updateStatus: " + e.getMessage());
            return false;
        }
    }

    public boolean assignResources(int id, String resources) {
        String sql = """
            UPDATE emergency_cases
            SET assigned_resources = ?, status = 'Resources Assigned',
                updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, resources);
            ps.setInt(2, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.assignResources: " + e.getMessage());
            return false;
        }
    }

    public boolean delete(int id) {
        String sql = "DELETE FROM emergency_cases WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("EmergencyDAO.delete: " + e.getMessage());
            return false;
        }
    }

    private EmergencyCase mapRow(ResultSet rs) throws SQLException {
        EmergencyCase ec = new EmergencyCase();
        ec.setId(rs.getInt("id"));
        ec.setPatientName(rs.getString("patient_name"));
        ec.setLocation(rs.getString("location"));
        ec.setSymptoms(rs.getString("symptoms"));
        ec.setEmergencyLevel(rs.getString("emergency_level"));
        ec.setStatus(rs.getString("status"));
        ec.setAssignedResources(rs.getString("assigned_resources"));
        ec.setCoordinator(rs.getString("coordinator"));
        ec.setCreatedAt(rs.getString("created_at"));
        ec.setUpdatedAt(rs.getString("updated_at"));
        return ec;
    }
}
