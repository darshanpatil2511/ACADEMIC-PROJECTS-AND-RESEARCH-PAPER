package com.badas.dao;

import com.badas.model.Patient;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class PatientDAO {

    private final DatabaseManager db = DatabaseManager.getInstance();

    public List<Patient> findAll() {
        List<Patient> list = new ArrayList<>();
        String sql = "SELECT * FROM patients ORDER BY name";
        try (Connection conn = db.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) {
            System.err.println("PatientDAO.findAll: " + e.getMessage());
        }
        return list;
    }

    public Patient findById(int id) {
        String sql = "SELECT * FROM patients WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            System.err.println("PatientDAO.findById: " + e.getMessage());
        }
        return null;
    }

    public List<Patient> search(String query) {
        List<Patient> list = new ArrayList<>();
        String sql = "SELECT * FROM patients WHERE LOWER(name) LIKE ? OR LOWER(symptoms) LIKE ? ORDER BY name";
        String pattern = "%" + query.toLowerCase() + "%";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, pattern);
            ps.setString(2, pattern);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) list.add(mapRow(rs));
            }
        } catch (SQLException e) {
            System.err.println("PatientDAO.search: " + e.getMessage());
        }
        return list;
    }

    public int save(Patient p) {
        String sql = """
            INSERT INTO patients (name, age, contact, symptoms, diagnosis, prescription, status, registered_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, p.getName());
            ps.setInt(2, p.getAge());
            ps.setString(3, p.getContact());
            ps.setString(4, p.getSymptoms());
            ps.setString(5, coalesce(p.getDiagnosis(), "Pending"));
            ps.setString(6, coalesce(p.getPrescription(), ""));
            ps.setString(7, coalesce(p.getStatus(), "Registered"));
            ps.setString(8, p.getRegisteredBy());
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return rs.getInt(1);
            }
        } catch (SQLException e) {
            System.err.println("PatientDAO.save: " + e.getMessage());
        }
        return -1;
    }

    public boolean update(Patient p) {
        String sql = """
            UPDATE patients
            SET name = ?, age = ?, contact = ?, symptoms = ?,
                diagnosis = ?, prescription = ?, status = ?,
                updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, p.getName());
            ps.setInt(2, p.getAge());
            ps.setString(3, p.getContact());
            ps.setString(4, p.getSymptoms());
            ps.setString(5, coalesce(p.getDiagnosis(), "Pending"));
            ps.setString(6, coalesce(p.getPrescription(), ""));
            ps.setString(7, coalesce(p.getStatus(), "Registered"));
            ps.setInt(8, p.getId());
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("PatientDAO.update: " + e.getMessage());
            return false;
        }
    }

    public boolean updateDiagnosis(int id, String diagnosis, String prescription) {
        String sql = """
            UPDATE patients
            SET diagnosis = ?, prescription = ?, updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, diagnosis);
            ps.setString(2, prescription);
            ps.setInt(3, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("PatientDAO.updateDiagnosis: " + e.getMessage());
            return false;
        }
    }

    public boolean updateStatus(int id, String status) {
        String sql = """
            UPDATE patients
            SET status = ?, updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, status);
            ps.setInt(2, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("PatientDAO.updateStatus: " + e.getMessage());
            return false;
        }
    }

    public boolean delete(int id) {
        String sql = "DELETE FROM patients WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("PatientDAO.delete: " + e.getMessage());
            return false;
        }
    }

    private Patient mapRow(ResultSet rs) throws SQLException {
        Patient p = new Patient();
        p.setId(rs.getInt("id"));
        p.setName(rs.getString("name"));
        p.setAge(rs.getInt("age"));
        p.setContact(rs.getString("contact"));
        p.setSymptoms(rs.getString("symptoms"));
        p.setDiagnosis(rs.getString("diagnosis"));
        p.setPrescription(rs.getString("prescription"));
        p.setStatus(rs.getString("status"));
        p.setRegisteredBy(rs.getString("registered_by"));
        p.setRegisteredAt(rs.getString("registered_at"));
        p.setUpdatedAt(rs.getString("updated_at"));
        return p;
    }

    private String coalesce(String value, String fallback) {
        return (value == null || value.isEmpty()) ? fallback : value;
    }
}
