package com.badas.ui.dashboard;

import com.badas.dao.EmergencyDAO;
import com.badas.model.EmergencyCase;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.util.List;

public class CoordinatorDashboard extends BaseFrame {

    private static final String NAV_CASES   = "Emergency Cases";
    private static final String NAV_ADD     = "Add New Case";

    private final EmergencyDAO emergencyDAO = new EmergencyDAO();

    private DefaultTableModel tableModel;
    private JTable            caseTable;
    private List<EmergencyCase> cases;

    public CoordinatorDashboard() { super("Emergency Coordinator Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_CASES, NAV_ADD };
    }
    @Override protected String getDefaultItem() { return NAV_CASES; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_CASES -> setContent(buildCasesPanel());
            case NAV_ADD   -> setContent(buildAddCasePanel());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Emergency cases panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildCasesPanel() {
        cases = emergencyDAO.findAll();
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Title + refresh
        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Active Emergency Cases"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildCasesPanel()));
        titleRow.add(refreshBtn, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Table
        String[] cols = {"#", "Patient Name", "Location", "Symptoms", "Level", "Status", "Resources", "Time"};
        tableModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        caseTable = new JTable(tableModel);
        styleTable(caseTable);
        caseTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        caseTable.getColumnModel().getColumn(1).setPreferredWidth(130);
        caseTable.getColumnModel().getColumn(4).setPreferredWidth(90);
        caseTable.getColumnModel().getColumn(5).setPreferredWidth(120);

        // Severity color renderer for Level column
        caseTable.getColumnModel().getColumn(4).setCellRenderer(new DefaultTableCellRenderer() {
            @Override public Component getTableCellRendererComponent(JTable t, Object val,
                    boolean sel, boolean foc, int row, int col) {
                super.getTableCellRendererComponent(t, val, sel, foc, row, col);
                if (!sel) {
                    setBackground(row % 2 == 0 ? Color.WHITE : UIConstants.TABLE_ROW_ALT);
                    setForeground(UIConstants.severityColor(val != null ? val.toString() : ""));
                    setFont(UIConstants.FONT_BODY_BOLD);
                }
                return this;
            }
        });

        loadTable();
        JScrollPane scroll = new JScrollPane(caseTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);

        // Action buttons
        root.add(buildActionBar(), BorderLayout.SOUTH);
        return root;
    }

    private void loadTable() {
        tableModel.setRowCount(0);
        int i = 1;
        for (EmergencyCase ec : cases) {
            String time = ec.getCreatedAt() != null
                    ? ec.getCreatedAt().substring(0, Math.min(16, ec.getCreatedAt().length()))
                    : "";
            tableModel.addRow(new Object[]{
                i++, ec.getPatientName(), ec.getLocation(), ec.getSymptoms(),
                ec.getEmergencyLevel(), ec.getStatus(), ec.getAssignedResources(), time
            });
        }
    }

    private JPanel buildActionBar() {
        JPanel bar = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, UIConstants.GAP_SM));
        bar.setBorder(new EmptyBorder(UIConstants.GAP_SM, 0, 0, 0));

        JButton assignBtn = primaryButton("Assign Resources");
        assignBtn.addActionListener(e -> {
            int row = caseTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a case first.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            String input = JOptionPane.showInputDialog(this,
                "Enter resources to assign (e.g., 'Ambulance A, Paramedic Team 2'):",
                "Assign Resources", JOptionPane.QUESTION_MESSAGE);
            if (input != null && !input.trim().isEmpty()) {
                emergencyDAO.assignResources(cases.get(row).getId(), input.trim());
                setContent(buildCasesPanel());
                JOptionPane.showMessageDialog(this, "Resources assigned.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        bar.add(assignBtn);

        JButton closeBtn = dangerButton("Close Case");
        closeBtn.addActionListener(e -> {
            int row = caseTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a case first.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            EmergencyCase ec = cases.get(row);
            int confirm = JOptionPane.showConfirmDialog(this,
                "Close emergency case for \"" + ec.getPatientName() + "\"?",
                "Confirm Close", JOptionPane.YES_NO_OPTION);
            if (confirm == JOptionPane.YES_OPTION) {
                emergencyDAO.updateStatus(ec.getId(), "Closed");
                setContent(buildCasesPanel());
                JOptionPane.showMessageDialog(this, "Case closed.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        bar.add(closeBtn);

        JButton reopenBtn = successButton("Reopen Case");
        reopenBtn.addActionListener(e -> {
            int row = caseTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a case first.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            emergencyDAO.updateStatus(cases.get(row).getId(), "Active");
            setContent(buildCasesPanel());
        });
        bar.add(reopenBtn);

        return bar;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Add new case panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildAddCasePanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.add(pageTitle("Add Emergency Case"), BorderLayout.NORTH);

        JPanel form = new JPanel(new GridBagLayout());
        form.setBorder(new EmptyBorder(UIConstants.GAP_LG, 0, UIConstants.GAP_LG, 0));
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets  = new Insets(UIConstants.GAP_SM, UIConstants.GAP_SM,
                                  UIConstants.GAP_SM, UIConstants.GAP_SM);
        gbc.fill    = GridBagConstraints.HORIZONTAL;
        gbc.weightx = 1.0;

        JTextField nameF     = styledField(24);
        JTextField locationF = styledField(24);
        JTextArea  symptomsA = new JTextArea(3, 30);
        symptomsA.setFont(UIConstants.FONT_BODY);
        symptomsA.setLineWrap(true);
        symptomsA.setWrapStyleWord(true);
        String[] levels = {"Critical", "Severe", "Moderate", "Minor"};
        JComboBox<String> levelBox = new JComboBox<>(levels);
        levelBox.setFont(UIConstants.FONT_BODY);

        addRow(form, gbc, 0, "Patient Name *", nameF);
        addRow(form, gbc, 1, "Location *",     locationF);
        gbc.gridx = 0; gbc.gridy = 2; gbc.weightx = 0.3;
        JLabel sl = new JLabel("Symptoms"); sl.setFont(UIConstants.FONT_BODY_BOLD); form.add(sl, gbc);
        gbc.gridx = 1; gbc.weightx = 0.7; form.add(new JScrollPane(symptomsA), gbc);
        addRow(form, gbc, 3, "Emergency Level *", levelBox);

        root.add(form, BorderLayout.CENTER);

        JPanel btns = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));
        JButton saveBtn = dangerButton("Create Emergency Case");
        saveBtn.addActionListener(e -> {
            String name  = nameF.getText().trim();
            String loc   = locationF.getText().trim();
            if (name.isEmpty() || loc.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Name and Location are required.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            String coordinator = currentUser != null ? currentUser.getUsername() : "coordinator";
            EmergencyCase ec = new EmergencyCase(name, loc, symptomsA.getText().trim(),
                    (String) levelBox.getSelectedItem(), coordinator);
            emergencyDAO.save(ec);
            nameF.setText(""); locationF.setText(""); symptomsA.setText("");
            JOptionPane.showMessageDialog(this, "Emergency case created.", "Success", JOptionPane.INFORMATION_MESSAGE);
            showPanel(NAV_CASES);
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
}
