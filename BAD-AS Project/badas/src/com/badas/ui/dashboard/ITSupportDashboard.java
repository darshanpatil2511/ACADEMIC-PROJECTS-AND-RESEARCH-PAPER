package com.badas.ui.dashboard;

import com.badas.dao.UserDAO;
import com.badas.model.User;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.util.List;

/**
 * IT Support dashboard for managing user accounts.
 * Passwords are hashed on save/update — never stored or shown in plaintext.
 */
public class ITSupportDashboard extends BaseFrame {

    private static final String NAV_ACCOUNTS = "User Accounts";
    private static final String NAV_ADD      = "Add User";

    private final UserDAO userDAO = new UserDAO();

    private DefaultTableModel tableModel;
    private JTable            userTable;
    private List<User>        users;

    public ITSupportDashboard() { super("IT Support Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_ACCOUNTS, NAV_ADD };
    }
    @Override protected String getDefaultItem() { return NAV_ACCOUNTS; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_ACCOUNTS -> setContent(buildAccountsPanel());
            case NAV_ADD      -> setContent(buildAddUserPanel());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  User accounts panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildAccountsPanel() {
        users = userDAO.findAll();
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("User Account Management"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildAccountsPanel()));
        titleRow.add(refreshBtn, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Note about security
        JLabel note = new JLabel("  Passwords are stored as SHA-256 hashes. Use 'Reset Password' to change a user's password.");
        note.setFont(UIConstants.FONT_SMALL);
        note.setForeground(UIConstants.STATUS_BAR_TEXT);
        note.setBorder(new EmptyBorder(0, 0, UIConstants.GAP_SM, 0));
        root.add(note, BorderLayout.AFTER_LAST_LINE);

        // Table — NO password column shown
        String[] cols = {"#", "Username", "Role", "Created", "Last Login"};
        tableModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        userTable = new JTable(tableModel);
        styleTable(userTable);
        userTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        userTable.getColumnModel().getColumn(1).setPreferredWidth(140);
        userTable.getColumnModel().getColumn(2).setPreferredWidth(180);
        loadTable();

        JScrollPane scroll = new JScrollPane(userTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));

        // Wrap in a panel that shows the note above the scroll
        JPanel center = new JPanel(new BorderLayout(0, UIConstants.GAP_SM));
        center.add(note, BorderLayout.NORTH);
        center.add(scroll, BorderLayout.CENTER);
        root.add(center, BorderLayout.CENTER);

        root.add(buildActionBar(), BorderLayout.SOUTH);
        return root;
    }

    private void loadTable() {
        tableModel.setRowCount(0);
        int i = 1;
        for (User u : users) {
            tableModel.addRow(new Object[]{
                i++, u.getUsername(), u.getRole(),
                u.getCreatedAt() != null ? u.getCreatedAt().substring(0, Math.min(10, u.getCreatedAt().length())) : "",
                u.getLastLogin() != null ? u.getLastLogin().substring(0, Math.min(16, u.getLastLogin().length())) : "Never"
            });
        }
    }

    private JPanel buildActionBar() {
        JPanel bar = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, UIConstants.GAP_SM));
        bar.setBorder(new EmptyBorder(UIConstants.GAP_SM, 0, 0, 0));

        JButton editBtn = primaryButton("Edit Role");
        editBtn.addActionListener(e -> {
            int row = userTable.getSelectedRow();
            if (row < 0) { showInfo("Select a user to edit."); return; }
            User u = users.get(row);
            String[] roles = {"Admin", "Doctor", "Nurse", "Receptionist", "Dispatcher",
                              "Emergency Coordinator", "IT Support"};
            String newRole = (String) JOptionPane.showInputDialog(this,
                "Select new role for \"" + u.getUsername() + "\":",
                "Edit Role", JOptionPane.QUESTION_MESSAGE, null, roles, u.getRole());
            if (newRole != null && !newRole.equals(u.getRole())) {
                userDAO.update(u.getId(), u.getUsername(), generateTempPassword(), newRole);
                setContent(buildAccountsPanel());
                JOptionPane.showMessageDialog(this, "Role updated.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        bar.add(editBtn);

        JButton resetPwdBtn = primaryButton("Reset Password");
        resetPwdBtn.addActionListener(e -> {
            int row = userTable.getSelectedRow();
            if (row < 0) { showInfo("Select a user to reset."); return; }
            User u = users.get(row);
            JPasswordField pwdF = new JPasswordField(20);
            JPasswordField confirmF = new JPasswordField(20);
            JPanel panel = new JPanel(new GridLayout(4, 1, UIConstants.GAP_SM, UIConstants.GAP_SM));
            panel.add(new JLabel("New password for \"" + u.getUsername() + "\":"));
            panel.add(pwdF);
            panel.add(new JLabel("Confirm password:"));
            panel.add(confirmF);
            int result = JOptionPane.showConfirmDialog(this, panel, "Reset Password", JOptionPane.OK_CANCEL_OPTION);
            if (result == JOptionPane.OK_OPTION) {
                String pw1 = new String(pwdF.getPassword());
                String pw2 = new String(confirmF.getPassword());
                if (!pw1.equals(pw2)) {
                    JOptionPane.showMessageDialog(this, "Passwords do not match.", "Error", JOptionPane.ERROR_MESSAGE);
                    return;
                }
                if (pw1.length() < 2) {
                    JOptionPane.showMessageDialog(this, "Password too short (min 2 characters).", "Error", JOptionPane.ERROR_MESSAGE);
                    return;
                }
                userDAO.resetPassword(u.getId(), pw1);
                JOptionPane.showMessageDialog(this, "Password reset successfully.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        bar.add(resetPwdBtn);

        JButton deleteBtn = dangerButton("Delete User");
        deleteBtn.addActionListener(e -> {
            int row = userTable.getSelectedRow();
            if (row < 0) { showInfo("Select a user to delete."); return; }
            User u = users.get(row);
            if (currentUser != null && currentUser.getUsername().equals(u.getUsername())) {
                JOptionPane.showMessageDialog(this, "Cannot delete your own account.", "Error", JOptionPane.ERROR_MESSAGE);
                return;
            }
            int confirm = JOptionPane.showConfirmDialog(this,
                "Delete user \"" + u.getUsername() + "\"? This cannot be undone.",
                "Confirm Delete", JOptionPane.YES_NO_OPTION, JOptionPane.WARNING_MESSAGE);
            if (confirm == JOptionPane.YES_OPTION) {
                userDAO.delete(u.getId());
                setContent(buildAccountsPanel());
                JOptionPane.showMessageDialog(this, "User deleted.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        bar.add(deleteBtn);

        return bar;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Add user panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildAddUserPanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.add(pageTitle("Add New User"), BorderLayout.NORTH);

        JPanel form = new JPanel(new GridBagLayout());
        form.setBorder(new EmptyBorder(UIConstants.GAP_LG, 0, UIConstants.GAP_LG, 0));
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets  = new Insets(UIConstants.GAP_SM, UIConstants.GAP_SM, UIConstants.GAP_SM, UIConstants.GAP_SM);
        gbc.fill    = GridBagConstraints.HORIZONTAL;
        gbc.weightx = 1.0;

        JTextField     usernameF = styledField(20);
        JPasswordField passwordF = new JPasswordField(20);
        passwordF.setFont(UIConstants.FONT_BODY);
        passwordF.setPreferredSize(new Dimension(passwordF.getPreferredSize().width, UIConstants.FIELD_HEIGHT));
        JPasswordField confirmF  = new JPasswordField(20);
        confirmF.setFont(UIConstants.FONT_BODY);
        confirmF.setPreferredSize(new Dimension(confirmF.getPreferredSize().width, UIConstants.FIELD_HEIGHT));
        String[] roles = {"Admin", "Doctor", "Nurse", "Receptionist", "Dispatcher",
                          "Emergency Coordinator", "IT Support"};
        JComboBox<String> roleBox = new JComboBox<>(roles);
        roleBox.setFont(UIConstants.FONT_BODY);

        addRow(form, gbc, 0, "Username *", usernameF);
        addRow(form, gbc, 1, "Password *", passwordF);
        addRow(form, gbc, 2, "Confirm Password *", confirmF);
        addRow(form, gbc, 3, "Role *", roleBox);

        root.add(form, BorderLayout.CENTER);

        JPanel btns = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));
        JButton saveBtn = successButton("Create User");
        saveBtn.addActionListener(e -> {
            String uname = usernameF.getText().trim();
            String pw1   = new String(passwordF.getPassword());
            String pw2   = new String(confirmF.getPassword());
            String role  = (String) roleBox.getSelectedItem();

            if (uname.isEmpty() || pw1.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Username and password are required.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            if (!pw1.equals(pw2)) {
                JOptionPane.showMessageDialog(this, "Passwords do not match.", "Error", JOptionPane.ERROR_MESSAGE);
                return;
            }
            if (pw1.length() < 2) {
                JOptionPane.showMessageDialog(this, "Password must be at least 2 characters.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            boolean success = userDAO.save(uname, pw1, role);
            if (success) {
                usernameF.setText(""); passwordF.setText(""); confirmF.setText("");
                JOptionPane.showMessageDialog(this, "User \"" + uname + "\" created successfully.", "Success", JOptionPane.INFORMATION_MESSAGE);
                showPanel(NAV_ACCOUNTS);
            } else {
                JOptionPane.showMessageDialog(this, "Username already exists or save failed.", "Error", JOptionPane.ERROR_MESSAGE);
            }
        });
        btns.add(saveBtn);
        root.add(btns, BorderLayout.SOUTH);
        return root;
    }

    private void addRow(JPanel panel, GridBagConstraints gbc, int row, String label, JComponent field) {
        gbc.gridx = 0; gbc.gridy = row; gbc.weightx = 0.3;
        JLabel lbl = new JLabel(label); lbl.setFont(UIConstants.FONT_BODY_BOLD); panel.add(lbl, gbc);
        gbc.gridx = 1; gbc.weightx = 0.7; panel.add(field, gbc);
    }

    private void showInfo(String msg) {
        JOptionPane.showMessageDialog(this, msg, "Info", JOptionPane.INFORMATION_MESSAGE);
    }

    // Placeholder — password must be reset after role edit
    private String generateTempPassword() {
        return "TempPass" + System.currentTimeMillis() % 10000;
    }
}
