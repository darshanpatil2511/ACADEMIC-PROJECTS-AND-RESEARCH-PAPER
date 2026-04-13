package com.badas;

import com.badas.dao.DatabaseManager;
import com.badas.ui.auth.LoginFrame;
import com.badas.ui.common.ThemeManager;

import javax.swing.*;

/**
 * Application entry point for BADAS v2.
 *
 * Startup sequence:
 *   1. Apply saved theme (FlatLaf if available, else Nimbus fallback)
 *   2. Initialise SQLite database — creates badas.db and seeds default data
 *   3. Launch the login window on the Event Dispatch Thread
 */
public class Main {

    public static void main(String[] args) {
        // 1. Theme must be applied before any Swing component is created
        ThemeManager.applyTheme();

        // 2. Initialize database (creates tables + seeds default data on first run)
        try {
            DatabaseManager.getInstance().initialize();
        } catch (RuntimeException e) {
            // Show a friendly error if the SQLite JDBC driver is missing
            JOptionPane.showMessageDialog(null,
                e.getMessage(),
                "Database Initialization Error",
                JOptionPane.ERROR_MESSAGE);
            System.exit(1);
        }

        // 3. Open login window
        SwingUtilities.invokeLater(() -> new LoginFrame().setVisible(true));
    }
}
