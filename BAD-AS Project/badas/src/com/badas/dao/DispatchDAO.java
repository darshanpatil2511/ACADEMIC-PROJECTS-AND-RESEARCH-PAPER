package com.badas.dao;

import com.badas.model.DispatchRequest;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class DispatchDAO {

    private final DatabaseManager db = DatabaseManager.getInstance();

    public List<DispatchRequest> findAll() {
        List<DispatchRequest> list = new ArrayList<>();
        String sql = "SELECT * FROM dispatch_requests ORDER BY created_at DESC";
        try (Connection conn = db.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) list.add(mapRow(rs));
        } catch (SQLException e) {
            System.err.println("DispatchDAO.findAll: " + e.getMessage());
        }
        return list;
    }

    public DispatchRequest findById(int id) {
        String sql = "SELECT * FROM dispatch_requests WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return mapRow(rs);
            }
        } catch (SQLException e) {
            System.err.println("DispatchDAO.findById: " + e.getMessage());
        }
        return null;
    }

    public int save(DispatchRequest req) {
        String sql = """
            INSERT INTO dispatch_requests
              (patient_name, patient_id, location, symptoms, ambulance_type, severity, hospital_assigned, status, dispatched_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, req.getPatientName());
            if (req.getPatientId() != null) ps.setInt(2, req.getPatientId());
            else ps.setNull(2, Types.INTEGER);
            ps.setString(3, req.getLocation());
            ps.setString(4, req.getSymptoms());
            ps.setString(5, req.getAmbulanceType());
            ps.setString(6, req.getSeverity());
            ps.setString(7, req.getHospitalAssigned() == null ? "" : req.getHospitalAssigned());
            ps.setString(8, req.getStatus() == null ? "Pending" : req.getStatus());
            ps.setString(9, req.getDispatchedBy());
            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) return rs.getInt(1);
            }
        } catch (SQLException e) {
            System.err.println("DispatchDAO.save: " + e.getMessage());
        }
        return -1;
    }

    public boolean updateStatus(int id, String status) {
        String sql = """
            UPDATE dispatch_requests
            SET status = ?, updated_at = datetime('now','localtime')
            WHERE id = ?
            """;
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, status);
            ps.setInt(2, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("DispatchDAO.updateStatus: " + e.getMessage());
            return false;
        }
    }

    public boolean delete(int id) {
        String sql = "DELETE FROM dispatch_requests WHERE id = ?";
        try (Connection conn = db.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            System.err.println("DispatchDAO.delete: " + e.getMessage());
            return false;
        }
    }

    private DispatchRequest mapRow(ResultSet rs) throws SQLException {
        DispatchRequest req = new DispatchRequest();
        req.setId(rs.getInt("id"));
        req.setPatientName(rs.getString("patient_name"));
        int pid = rs.getInt("patient_id");
        if (!rs.wasNull()) req.setPatientId(pid);
        req.setLocation(rs.getString("location"));
        req.setSymptoms(rs.getString("symptoms"));
        req.setAmbulanceType(rs.getString("ambulance_type"));
        req.setSeverity(rs.getString("severity"));
        req.setHospitalAssigned(rs.getString("hospital_assigned"));
        req.setStatus(rs.getString("status"));
        req.setDispatchedBy(rs.getString("dispatched_by"));
        req.setCreatedAt(rs.getString("created_at"));
        req.setUpdatedAt(rs.getString("updated_at"));
        return req;
    }
}
