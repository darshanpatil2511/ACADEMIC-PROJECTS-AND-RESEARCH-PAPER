package com.badas.dao;

import com.badas.model.Hospital;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class HospitalDAO {

    private final DatabaseManager db = DatabaseManager.getInstance();

    public List<Hospital> findAll() {
        List<Hospital> list = new ArrayList<>();
        String sql = "SELECT * FROM hospitals ORDER BY name";
        try (Connection conn = db.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) {
            System.err.println("HospitalDAO.findAll: " + e.getMessage());
        }
        return list;
    }

    public Hospital findById(int id) {
        String sql = "SELECT * FROM hospitals WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            System.err.println("HospitalDAO.findById: " + e.getMessage());
        }
        return null;
    }

    public int save(Hospital h) {
        String sql = """
            INSERT INTO hospitals (name, location, ambulance_count, available_ambulances, contact)
            VALUES (?, ?, ?, ?, ?)
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, h.getName());
            ps.setString(2, h.getLocation());
            ps.setInt(3, h.getAmbulanceCount());
            ps.setInt(4, h.getAvailableAmbulances());
            ps.setString(5, h.getContact() == null ? "" : h.getContact());
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return rs.getInt(1);
            }
        } catch (SQLException e) {
            System.err.println("HospitalDAO.save: " + e.getMessage());
        }
        return -1;
    }

    public boolean update(Hospital h) {
        String sql = """
            UPDATE hospitals
            SET name = ?, location = ?, ambulance_count = ?, available_ambulances = ?, contact = ?,
                updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, h.getName());
            ps.setString(2, h.getLocation());
            ps.setInt(3, h.getAmbulanceCount());
            ps.setInt(4, h.getAvailableAmbulances());
            ps.setString(5, h.getContact() == null ? "" : h.getContact());
            ps.setInt(6, h.getId());
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("HospitalDAO.update: " + e.getMessage());
            return false;
        }
    }

    public boolean delete(int id) {
        String sql = "DELETE FROM hospitals WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("HospitalDAO.delete: " + e.getMessage());
            return false;
        }
    }

    private Hospital mapRow(ResultSet rs) throws SQLException {
        Hospital h = new Hospital();
        h.setId(rs.getInt("id"));
        h.setName(rs.getString("name"));
        h.setLocation(rs.getString("location"));
        h.setAmbulanceCount(rs.getInt("ambulance_count"));
        h.setAvailableAmbulances(rs.getInt("available_ambulances"));
        h.setContact(rs.getString("contact"));
        h.setCreatedAt(rs.getString("created_at"));
        h.setUpdatedAt(rs.getString("updated_at"));
        return h;
    }
}
