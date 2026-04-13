package com.badas.ui.auth;

import com.badas.model.User;
import com.badas.service.AuthService;
import com.badas.ui.common.ThemeManager;
import com.badas.ui.common.UIConstants;
import com.badas.ui.dashboard.*;
import com.badas.ui.dispatcher.DispatcherDashboard;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.*;

/**
 * Modern split-panel login screen.
 * Left half  : branded blue panel with app identity.
 * Right half : clean login form.
 */
public class LoginFrame extends JFrame {

    private JTextField     usernameField;
    private JPasswordField passwordField;
    private JLabel         errorLabel;
    private JToggleButton  themeToggle;

    private final AuthService auth = AuthService.getInstance();

    public LoginFrame() {
        setTitle("BADAS \u2014 Login");
        setDefaultCloseOperation(EXIT_ON_CLOSE);
        setSize(900, 560);
        setMinimumSize(new Dimension(760, 500));
        setResizable(true);
        setLocationRelativeTo(null);
        setLayout(new BorderLayout());
        add(buildContent(), BorderLayout.CENTER);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Layout
    // ─────────────────────────────────────────────────────────────────────────

    private JSplitPane buildContent() {
        JSplitPane split = new JSplitPane(JSplitPane.HORIZONTAL_SPLIT,
                buildBrandPanel(), buildFormPanel());
        split.setDividerSize(0);
        split.setEnabled(false);
        split.setResizeWeight(0.42);
        split.setBorder(null);
        return split;
    }

    // ─── Left branded panel ──────────────────────────────────────────────────

    private JPanel buildBrandPanel() {
        JPanel panel = new JPanel() {
            @Override protected void paintComponent(Graphics g) {
                super.paintComponent(g);
                Graphics2D g2 = (Graphics2D) g;
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                // Gradient background
                GradientPaint gp = new GradientPaint(
                    0, 0, new Color(13, 71, 161),
                    0, getHeight(), new Color(21, 101, 192));
                g2.setPaint(gp);
                g2.fillRect(0, 0, getWidth(), getHeight());
            }
        };
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setBorder(new EmptyBorder(60, 40, 60, 40));

        panel.add(Box.createVerticalGlue());

        // Medical cross icon
        JLabel icon = new JLabel("\u2665", SwingConstants.CENTER);
        icon.setFont(new Font("Segoe UI", Font.BOLD, 56));
        icon.setForeground(new Color(255, 120, 120));
        icon.setAlignmentX(Component.CENTER_ALIGNMENT);
        panel.add(icon);
        panel.add(Box.createVerticalStrut(20));

        // App name
        JLabel appName = new JLabel("BADAS", SwingConstants.CENTER);
        appName.setFont(new Font("Segoe UI", Font.BOLD, 36));
        appName.setForeground(Color.WHITE);
        appName.setAlignmentX(Component.CENTER_ALIGNMENT);
        panel.add(appName);
        panel.add(Box.createVerticalStrut(8));

        // Full name
        JLabel fullName = new JLabel("Boston Aid & Dispatch", SwingConstants.CENTER);
        fullName.setFont(new Font("Segoe UI", Font.PLAIN, 15));
        fullName.setForeground(new Color(187, 222, 251));
        fullName.setAlignmentX(Component.CENTER_ALIGNMENT);
        panel.add(fullName);

        JLabel fullName2 = new JLabel("Assistant System", SwingConstants.CENTER);
        fullName2.setFont(new Font("Segoe UI", Font.PLAIN, 15));
        fullName2.setForeground(new Color(187, 222, 251));
        fullName2.setAlignmentX(Component.CENTER_ALIGNMENT);
        panel.add(fullName2);
        panel.add(Box.createVerticalStrut(40));

        // Feature bullets
        String[] features = {
            "  Emergency Dispatch Management",
            "  Multi-Role Access Control",
            "  Real-time Patient Tracking",
            "  Hospital Resource Coordination"
        };
        for (String f : features) {
            JLabel lbl = new JLabel(f);
            lbl.setFont(new Font("Segoe UI", Font.PLAIN, 12));
            lbl.setForeground(new Color(200, 220, 255));
            lbl.setAlignmentX(Component.CENTER_ALIGNMENT);
            panel.add(lbl);
            panel.add(Box.createVerticalStrut(6));
        }

        panel.add(Box.createVerticalGlue());

        // Version footer
        JLabel version = new JLabel("v2.0  \u2014  2025", SwingConstants.CENTER);
        version.setFont(new Font("Segoe UI", Font.PLAIN, 11));
        version.setForeground(new Color(160, 190, 230));
        version.setAlignmentX(Component.CENTER_ALIGNMENT);
        panel.add(version);

        return panel;
    }

    // ─── Right form panel ────────────────────────────────────────────────────

    private JPanel buildFormPanel() {
        JPanel outer = new JPanel(new BorderLayout());

        // Top-right: theme toggle
        JPanel topBar = new JPanel(new FlowLayout(FlowLayout.RIGHT));
        topBar.setOpaque(false);
        themeToggle = new JToggleButton(ThemeManager.isDark() ? "\u2600 Light" : "\u263D Dark");
        themeToggle.setFont(new Font("Segoe UI", Font.PLAIN, 12));
        themeToggle.setFocusPainted(false);
        themeToggle.setSelected(ThemeManager.isDark());
        themeToggle.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        themeToggle.addActionListener(e -> {
            ThemeManager.toggleTheme();
            themeToggle.setText(ThemeManager.isDark() ? "\u2600 Light" : "\u263D Dark");
        });
        topBar.add(themeToggle);
        outer.add(topBar, BorderLayout.NORTH);

        // Center form
        JPanel form = new JPanel(new GridBagLayout());
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets = new Insets(8, 0, 8, 0);
        gbc.fill = GridBagConstraints.HORIZONTAL;
        gbc.gridx = 0;
        gbc.weightx = 1.0;

        // Title
        JLabel title = new JLabel("Welcome back");
        title.setFont(new Font("Segoe UI", Font.BOLD, 26));
        gbc.gridy = 0;
        gbc.insets = new Insets(0, 0, 4, 0);
        form.add(title, gbc);

        JLabel subtitle = new JLabel("Sign in to your account");
        subtitle.setFont(new Font("Segoe UI", Font.PLAIN, 13));
        subtitle.setForeground(new Color(120, 120, 120));
        gbc.gridy = 1;
        gbc.insets = new Insets(0, 0, 28, 0);
        form.add(subtitle, gbc);

        // Username
        gbc.insets = new Insets(6, 0, 2, 0);
        gbc.gridy = 2;
        form.add(fieldLabel("Username"), gbc);

        usernameField = new JTextField();
        usernameField.setFont(UIConstants.FONT_BODY);
        usernameField.setPreferredSize(new Dimension(280, UIConstants.FIELD_HEIGHT));
        gbc.gridy = 3;
        gbc.insets = new Insets(0, 0, 14, 0);
        form.add(usernameField, gbc);

        // Password
        gbc.gridy = 4;
        gbc.insets = new Insets(6, 0, 2, 0);
        form.add(fieldLabel("Password"), gbc);

        passwordField = new JPasswordField();
        passwordField.setFont(UIConstants.FONT_BODY);
        passwordField.setPreferredSize(new Dimension(280, UIConstants.FIELD_HEIGHT));
        gbc.gridy = 5;
        gbc.insets = new Insets(0, 0, 8, 0);
        form.add(passwordField, gbc);

        // Error label
        errorLabel = new JLabel(" ");
        errorLabel.setFont(UIConstants.FONT_SMALL);
        errorLabel.setForeground(UIConstants.ACCENT_RED);
        gbc.gridy = 6;
        gbc.insets = new Insets(0, 0, 12, 0);
        form.add(errorLabel, gbc);

        // Login button
        JButton loginBtn = new JButton("Sign In");
        loginBtn.setFont(UIConstants.FONT_BUTTON);
        loginBtn.setBackground(UIConstants.PRIMARY);
        loginBtn.setForeground(Color.WHITE);
        loginBtn.setFocusPainted(false);
        loginBtn.setBorderPainted(false);
        loginBtn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        loginBtn.setPreferredSize(new Dimension(280, 40));
        loginBtn.addActionListener(e -> attemptLogin());
        gbc.gridy = 7;
        gbc.insets = new Insets(0, 0, 16, 0);
        form.add(loginBtn, gbc);

        // Allow Enter key to trigger login
        getRootPane().setDefaultButton(loginBtn);
        passwordField.addActionListener(e -> attemptLogin());
        usernameField.addActionListener(e -> passwordField.requestFocus());

        // Exit link
        JLabel exitLink = new JLabel("<html><a href='#'>Exit application</a></html>");
        exitLink.setFont(UIConstants.FONT_SMALL);
        exitLink.setForeground(new Color(120, 120, 120));
        exitLink.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        exitLink.addMouseListener(new MouseAdapter() {
            @Override public void mouseClicked(MouseEvent e) { System.exit(0); }
        });
        gbc.gridy = 8;
        gbc.insets = new Insets(0, 0, 0, 0);
        form.add(exitLink, gbc);

        // Wrap form in a padded container
        JPanel padded = new JPanel(new GridBagLayout());
        padded.setBorder(new EmptyBorder(0, 60, 0, 60));
        padded.add(form);

        outer.add(padded, BorderLayout.CENTER);

        // Bottom hint
        JLabel hint = new JLabel("  Default admin: ad / ad123", SwingConstants.LEFT);
        hint.setFont(new Font("Segoe UI", Font.PLAIN, 10));
        hint.setForeground(new Color(180, 180, 180));
        hint.setBorder(new EmptyBorder(0, 20, 8, 0));
        outer.add(hint, BorderLayout.SOUTH);

        return outer;
    }

    private JLabel fieldLabel(String text) {
        JLabel lbl = new JLabel(text);
        lbl.setFont(UIConstants.FONT_BODY_BOLD);
        return lbl;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Login logic
    // ─────────────────────────────────────────────────────────────────────────

    private void attemptLogin() {
        String username = usernameField.getText().trim();
        String password = new String(passwordField.getPassword()).trim();

        if (username.isEmpty() || password.isEmpty()) {
            showError("Please enter username and password.");
            return;
        }

        User user = auth.login(username, password);
        if (user == null) {
            showError("Invalid username or password.");
            passwordField.setText("");
            passwordField.requestFocus();
            return;
        }

        // Success — route to the appropriate dashboard
        dispose();
        SwingUtilities.invokeLater(() -> openDashboard(user));
    }

    private void openDashboard(User user) {
        JFrame dashboard = switch (user.getRole().toLowerCase()) {
            case "admin"                -> new AdminDashboard();
            case "doctor"               -> new DoctorDashboard();
            case "nurse"                -> new NurseDashboard();
            case "receptionist"         -> new ReceptionistDashboard();
            case "dispatcher"           -> new DispatcherDashboard();
            case "emergency coordinator"-> new CoordinatorDashboard();
            case "it support"           -> new ITSupportDashboard();
            default -> {
                JOptionPane.showMessageDialog(null,
                    "Unrecognized role: " + user.getRole(),
                    "Login Error", JOptionPane.ERROR_MESSAGE);
                yield null;
            }
        };
        if (dashboard != null) dashboard.setVisible(true);
    }

    private void showError(String message) {
        errorLabel.setText(message);
    }
}
