package com.badas.ui.dashboard;

import com.badas.dao.PatientDAO;
import com.badas.model.Patient;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.util.List;

public class NurseDashboard extends BaseFrame {

    private static final String NAV_STATUS = "Patient Status";

    private final PatientDAO patientDAO = new PatientDAO();

    private DefaultTableModel tableModel;
    private JTable            patientTable;
    private List<Patient>     patients;

    public NurseDashboard() { super("Nurse Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_STATUS };
    }
    @Override protected String getDefaultItem() { return NAV_STATUS; }

    @Override
    protected void showPanel(String navItem) {
        setContent(buildStatusPanel());
    }

    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildStatusPanel() {
        patients = patientDAO.findAll();
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Title + refresh
        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Patient Status Management"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildStatusPanel()));
        titleRow.add(refreshBtn, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Table
        String[] cols = {"#", "Name", "Age", "Symptoms", "Diagnosis", "Prescription", "Status"};
        tableModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        patientTable = new JTable(tableModel);
        styleTable(patientTable);
        patientTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        patientTable.getColumnModel().getColumn(1).setPreferredWidth(140);
        patientTable.getColumnModel().getColumn(3).setPreferredWidth(200);
        loadTable();

        JScrollPane scroll = new JScrollPane(patientTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);

        // Update form
        root.add(buildUpdateBar(), BorderLayout.SOUTH);
        return root;
    }

    private void loadTable() {
        tableModel.setRowCount(0);
        int i = 1;
        for (Patient p : patients) {
            tableModel.addRow(new Object[]{
                i++, p.getName(), p.getAge(), p.getSymptoms(),
                p.getDiagnosis(), p.getPrescription(), p.getStatus()
            });
        }
    }

    private JPanel buildUpdateBar() {
        JPanel wrapper = new JPanel(new BorderLayout(UIConstants.GAP_MD, 0));
        wrapper.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));

        // Status dropdown
        JPanel left = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));
        left.add(new JLabel("New Status:"));
        String[] statusOptions = {"Under Observation", "Stable", "Critical", "Discharged", "Transferred"};
        JComboBox<String> statusBox = new JComboBox<>(statusOptions);
        statusBox.setFont(UIConstants.FONT_BODY);
        statusBox.setPreferredSize(new Dimension(200, UIConstants.FIELD_HEIGHT));
        left.add(statusBox);

        JTextField customStatus = styledField(14);
        customStatus.setToolTipText("Or type a custom status");
        left.add(new JLabel("Custom:"));
        left.add(customStatus);

        wrapper.add(left, BorderLayout.CENTER);

        JButton updateBtn = primaryButton("Update Status");
        updateBtn.addActionListener(e -> {
            int row = patientTable.getSelectedRow();
            if (row < 0) {
                JOptionPane.showMessageDialog(this, "Select a patient to update.", "Info", JOptionPane.INFORMATION_MESSAGE);
                return;
            }
            String newStatus = customStatus.getText().trim().isEmpty()
                    ? (String) statusBox.getSelectedItem()
                    : customStatus.getText().trim();
            Patient p = patients.get(row);
            patientDAO.updateStatus(p.getId(), newStatus);
            customStatus.setText("");
            setContent(buildStatusPanel());
            JOptionPane.showMessageDialog(this, "Status updated to: " + newStatus, "Success", JOptionPane.INFORMATION_MESSAGE);
        });

        JPanel btns = new JPanel(new FlowLayout(FlowLayout.RIGHT));
        btns.add(updateBtn);
        wrapper.add(btns, BorderLayout.EAST);
        return wrapper;
    }
}
