package com.badas.dao;

import com.badas.util.SecurityUtils;

import java.io.File;
import java.sql.*;

/**
 * Singleton that manages the SQLite connection, schema creation, and seed data.
 * Database file: badas.db in the project root (user.dir).
 */
public class DatabaseManager {

    private static DatabaseManager instance;

    private final String dbPath;
    private final String dbUrl;

    private DatabaseManager() {
        dbPath = System.getProperty("user.dir") + File.separator + "badas.db";
        dbUrl  = "jdbc:sqlite:" + dbPath;
    }

    public static synchronized DatabaseManager getInstance() {
        if (instance == null) {
            instance = new DatabaseManager();
        }
        return instance;
    }

    /** Returns a fresh JDBC connection. Caller must close it. */
    public Connection getConnection() throws SQLException {
        return DriverManager.getConnection(dbUrl);
    }

    /** Creates all tables (if not exist) and seeds default data. */
    public void initialize() {
        try {
            // Ensure the SQLite JDBC driver is loaded
            Class.forName("org.sqlite.JDBC");
        } catch (ClassNotFoundException e) {
            throw new RuntimeException(
                "SQLite JDBC driver not found.\n" +
                "Download sqlite-jdbc-3.45.1.0.jar and place it in the lib/ folder.", e);
        }

        createTables();
        seedData();
    }

    // ─────────────────────────────────────────────
    //  Schema
    // ─────────────────────────────────────────────

    private void createTables() {
        String[] ddl = {
            // Users
            """
            CREATE TABLE IF NOT EXISTS users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                username      TEXT NOT NULL UNIQUE,
                password_hash TEXT NOT NULL,
                role          TEXT NOT NULL,
                created_at    TEXT DEFAULT (datetime('now', 'localtime')),
                last_login    TEXT
            )
            """,
            // Patients
            """
            CREATE TABLE IF NOT EXISTS patients (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                name          TEXT NOT NULL,
                age           INTEGER NOT NULL CHECK(age >= 0 AND age <= 150),
                contact       TEXT,
                symptoms      TEXT,
                diagnosis     TEXT DEFAULT 'Pending',
                prescription  TEXT DEFAULT '',
                status        TEXT DEFAULT 'Registered',
                registered_by TEXT,
                registered_at TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at    TEXT DEFAULT (datetime('now', 'localtime'))
            )
            """,
            // Hospitals
            """
            CREATE TABLE IF NOT EXISTS hospitals (
                id                   INTEGER PRIMARY KEY AUTOINCREMENT,
                name                 TEXT NOT NULL,
                location             TEXT NOT NULL,
                ambulance_count      INTEGER DEFAULT 0 CHECK(ambulance_count >= 0),
                available_ambulances INTEGER DEFAULT 0,
                contact              TEXT DEFAULT '',
                created_at           TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at           TEXT DEFAULT (datetime('now', 'localtime'))
            )
            """,
            // Dispatch requests
            """
            CREATE TABLE IF NOT EXISTS dispatch_requests (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_name      TEXT NOT NULL,
                patient_id        INTEGER,
                location          TEXT NOT NULL,
                symptoms          TEXT,
                ambulance_type    TEXT,
                severity          TEXT,
                hospital_assigned TEXT DEFAULT '',
                status            TEXT DEFAULT 'Pending',
                dispatched_by     TEXT,
                created_at        TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at        TEXT DEFAULT (datetime('now', 'localtime')),
                FOREIGN KEY (patient_id) REFERENCES patients(id)
            )
            """,
            // Emergency cases
            """
            CREATE TABLE IF NOT EXISTS emergency_cases (
                id                INTEGER PRIMARY KEY AUTOINCREMENT,
                patient_name      TEXT NOT NULL,
                location          TEXT NOT NULL,
                symptoms          TEXT,
                emergency_level   TEXT NOT NULL,
                status            TEXT DEFAULT 'Active',
                assigned_resources TEXT DEFAULT '',
                coordinator       TEXT,
                created_at        TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at        TEXT DEFAULT (datetime('now', 'localtime'))
            )
            """
        };

        try (Connection conn = getConnection();
             Statement stmt = conn.createStatement()) {
            for (String sql : ddl) {
                stmt.execute(sql);
            }
        } catch (SQLException e) {
            throw new RuntimeException("Failed to create database tables: " + e.getMessage(), e);
        }
    }

    // ─────────────────────────────────────────────
    //  Seed data — only inserted once (checks first)
    // ─────────────────────────────────────────────

    private void seedData() {
        seedUsers();
        seedHospitals();
        seedPatients();
        seedEmergencyCases();
    }

    private void seedUsers() {
        String check = "SELECT COUNT(*) FROM users";
        try (Connection conn = getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(check)) {
            if (rs.getInt(1) > 0) return; // already seeded
        } catch (SQLException e) {
            return;
        }

        // username -> plaintext password -> role
        String[][] users = {
            {"ad",             "ad123",  "Admin"},
            {"d1",             "d1",     "Dispatcher"},
            {"d2",             "d2",     "Dispatcher"},
            {"doc1",           "doc1",   "Doctor"},
            {"doc2",           "doc2",   "Doctor"},
            {"nurse1",         "nurse1", "Nurse"},
            {"nurse2",         "nurse2", "Nurse"},
            {"nurse3",         "nurse3", "Nurse"},
            {"rec1",           "rec1",   "Receptionist"},
            {"receptionist2",  "rec456", "Receptionist"},
            {"ec1",            "ec1",    "Emergency Coordinator"},
            {"ec2",            "ec2",    "Emergency Coordinator"},
            {"it2",            "it456",  "IT Support"},
            {"anmol",          "shetty", "Nurse"},
            {"prayag",         "adh",    "Admin"},
            {"abhi",           "abhi",   "IT Support"},
            {"darshan",        "patil",  "Doctor"}
        };

        String sql = "INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)";
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (String[] u : users) {
                ps.setString(1, u[0]);
                ps.setString(2, SecurityUtils.hashPassword(u[1]));
                ps.setString(3, u[2]);
                ps.addBatch();
            }
            ps.executeBatch();
        } catch (SQLException e) {
            System.err.println("User seed error: " + e.getMessage());
        }
    }

    private void seedHospitals() {
        String check = "SELECT COUNT(*) FROM hospitals";
        try (Connection conn = getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(check)) {
            if (rs.getInt(1) > 0) return;
        } catch (SQLException e) {
            return;
        }

        // name, location, ambulance_count
        String[][] hospitals = {
            {"Massachusetts General Hospital",        "Boston",         "30"},
            {"Brigham and Women's Hospital",           "Boston",         "6"},
            {"Beth Israel Deaconess Medical Center",   "Boston",         "10"},
            {"Boston Medical Center",                  "Boston",         "6"},
            {"Tufts Medical Center",                   "Boston",         "7"},
            {"Boston Children's Hospital",             "Boston",         "2"},
            {"Lahey Hospital & Medical Center",        "Burlington",     "5"},
            {"Newton-Wellesley Hospital",              "Newton",         "8"},
            {"Mount Auburn Hospital",                  "Cambridge",      "9"},
            {"Cambridge Health Alliance",              "Cambridge",      "15"},
            {"UMass Memorial Medical Center",          "Worcester",      "5"},
            {"South Shore Hospital",                   "South Weymouth", "2"},
            {"Lawrence General Hospital",              "Lawrence",       "55"},
            {"Cape Cod Hospital",                      "Hyannis",        "6"},
            {"St. Luke's Hospital",                    "New Bedford",    "7"},
            {"Falmouth Hospital",                      "Falmouth",       "1"},
            {"Anna Jaques Hospital",                   "Newburyport",    "7"},
            {"DY Patil Medical Center",                "Mumbai",         "300"}
        };

        String sql = "INSERT INTO hospitals (name, location, ambulance_count, available_ambulances) VALUES (?, ?, ?, ?)";
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (String[] h : hospitals) {
                ps.setString(1, h[0]);
                ps.setString(2, h[1]);
                ps.setInt(3, Integer.parseInt(h[2]));
                ps.setInt(4, Integer.parseInt(h[2]));
                ps.addBatch();
            }
            ps.executeBatch();
        } catch (SQLException e) {
            System.err.println("Hospital seed error: " + e.getMessage());
        }
    }

    private void seedPatients() {
        String check = "SELECT COUNT(*) FROM patients";
        try (Connection conn = getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(check)) {
            if (rs.getInt(1) > 0) return;
        } catch (SQLException e) {
            return;
        }

        // name, age, contact, symptoms, diagnosis, status
        String[][] patients = {
            {"John Doe",      "45", "617-555-0101", "Severe Chest Pain",       "Pending", "Registered"},
            {"Jane Smith",    "34", "617-555-0102", "Difficulty Breathing",    "Pending", "Registered"},
            {"Bob Johnson",   "50", "617-555-0103", "Fracture",                "Pending", "Registered"},
            {"Alice Brown",   "33", "617-555-0104", "Cough",                   "Pending", "Registered"},
            {"Charlie White", "60", "617-555-0105", "Severe Headache",         "Pending", "Registered"},
            {"Darshan Patil", "25", "617-555-0106", "Bleeding",                "Pending", "Registered"}
        };

        String sql = "INSERT INTO patients (name, age, contact, symptoms, diagnosis, status) VALUES (?, ?, ?, ?, ?, ?)";
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (String[] p : patients) {
                ps.setString(1, p[0]);
                ps.setInt(2, Integer.parseInt(p[1]));
                ps.setString(3, p[2]);
                ps.setString(4, p[3]);
                ps.setString(5, p[4]);
                ps.setString(6, p[5]);
                ps.addBatch();
            }
            ps.executeBatch();
        } catch (SQLException e) {
            System.err.println("Patient seed error: " + e.getMessage());
        }
    }

    private void seedEmergencyCases() {
        String check = "SELECT COUNT(*) FROM emergency_cases";
        try (Connection conn = getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(check)) {
            if (rs.getInt(1) > 0) return;
        } catch (SQLException e) {
            return;
        }

        String[][] cases = {
            {"John Doe",      "123 Main St",   "Severe Chest Pain",      "Critical", "Active"},
            {"Jane Smith",    "456 Elm St",    "Difficulty Breathing",   "Severe",   "Active"},
            {"Bob Johnson",   "789 Pine St",   "Fracture",               "Moderate", "Active"},
            {"Alice Brown",   "321 Oak Ave",   "High Fever",             "Moderate", "Active"},
            {"Charlie White", "654 Maple Dr",  "Severe Headache",        "Severe",   "Active"}
        };

        String sql = "INSERT INTO emergency_cases (patient_name, location, symptoms, emergency_level, status) VALUES (?, ?, ?, ?, ?)";
        try (Connection conn = getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            for (String[] c : cases) {
                ps.setString(1, c[0]);
                ps.setString(2, c[1]);
                ps.setString(3, c[2]);
                ps.setString(4, c[3]);
                ps.setString(5, c[4]);
                ps.addBatch();
            }
            ps.executeBatch();
        } catch (SQLException e) {
            System.err.println("Emergency case seed error: " + e.getMessage());
        }
    }
}
