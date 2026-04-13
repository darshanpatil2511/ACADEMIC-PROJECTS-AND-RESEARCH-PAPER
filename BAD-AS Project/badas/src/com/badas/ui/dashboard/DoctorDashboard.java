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

public class DoctorDashboard extends BaseFrame {

    private static final String NAV_RECORDS = "Patient Records";
    private static final String NAV_SEARCH  = "Search Patient";

    private final PatientDAO patientDAO = new PatientDAO();

    private DefaultTableModel tableModel;
    private JTable            patientTable;
    private List<Patient>     patients;

    public DoctorDashboard() { super("Doctor Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_RECORDS, NAV_SEARCH };
    }
    @Override protected String getDefaultItem() { return NAV_RECORDS; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_RECORDS -> setContent(buildRecordsPanel(patientDAO.findAll()));
            case NAV_SEARCH  -> setContent(buildSearchPanel());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildRecordsPanel(List<Patient> data) {
        this.patients = data;
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Title + refresh
        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Patient Records"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildRecordsPanel(patientDAO.findAll())));
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
        populateTable(this.patients);

        JScrollPane scroll = new JScrollPane(patientTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);

        // Update form
        root.add(buildUpdateForm(), BorderLayout.SOUTH);
        return root;
    }

    private void populateTable(List<Patient> list) {
        tableModel.setRowCount(0);
        int i = 1;
        for (Patient p : list) {
            tableModel.addRow(new Object[]{
                i++, p.getName(), p.getAge(), p.getSymptoms(),
                p.getDiagnosis(), p.getPrescription(), p.getStatus()
            });
        }
    }

    private JPanel buildUpdateForm() {
        JPanel wrapper = new JPanel(new BorderLayout(UIConstants.GAP_MD, 0));
        wrapper.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));

        JPanel fields = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));
        fields.add(new JLabel("Diagnosis:"));
        JTextField diagF = styledField(20);
        fields.add(diagF);
        fields.add(new JLabel("Prescription:"));
        JTextField prescF = styledField(20);
        fields.add(prescF);
        wrapper.add(fields, BorderLayout.CENTER);

        JButton updateBtn = primaryButton("Update Record");
        updateBtn.addActionListener(e -> {
            int row = patientTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a patient to update.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            String diag  = diagF.getText().trim();
            String presc = prescF.getText().trim();
            if (diag.isEmpty()) { JOptionPane.showMessageDialog(this, "Diagnosis cannot be empty.", "Validation", JOptionPane.WARNING_MESSAGE); return; }
            Patient p = patients.get(row);
            patientDAO.updateDiagnosis(p.getId(), diag, presc);
            diagF.setText(""); prescF.setText("");
            setContent(buildRecordsPanel(patientDAO.findAll()));
            JOptionPane.showMessageDialog(this, "Record updated successfully.", "Success", JOptionPane.INFORMATION_MESSAGE);
        });

        JPanel btns = new JPanel(new FlowLayout(FlowLayout.RIGHT));
        btns.add(updateBtn);
        wrapper.add(btns, BorderLayout.EAST);
        return wrapper;
    }

    private JPanel buildSearchPanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.add(pageTitle("Search Patient"), BorderLayout.NORTH);

        JPanel searchRow = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));
        JTextField queryF = styledField(24);
        queryF.setToolTipText("Search by name or symptoms");
        JButton searchBtn = primaryButton("Search");
        JButton clearBtn  = new JButton("Clear");

        searchRow.add(new JLabel("Name / Symptoms:"));
        searchRow.add(queryF);
        searchRow.add(searchBtn);
        searchRow.add(clearBtn);
        root.add(searchRow, BorderLayout.NORTH);

        JPanel resultsPanel = new JPanel(new BorderLayout());
        // Build an empty table initially
        String[] cols = {"#", "Name", "Age", "Symptoms", "Diagnosis", "Prescription", "Status"};
        DefaultTableModel model = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        JTable t = new JTable(model);
        styleTable(t);
        JScrollPane scroll = new JScrollPane(t);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        resultsPanel.add(scroll, BorderLayout.CENTER);
        root.add(resultsPanel, BorderLayout.CENTER);

        searchBtn.addActionListener(e -> {
            String q = queryF.getText().trim();
            if (q.isEmpty()) return;
            List<Patient> results = patientDAO.search(q);
            model.setRowCount(0);
            int i = 1;
            for (Patient p : results) {
                model.addRow(new Object[]{
                    i++, p.getName(), p.getAge(), p.getSymptoms(),
                    p.getDiagnosis(), p.getPrescription(), p.getStatus()
                });
            }
            if (results.isEmpty()) {
                JOptionPane.showMessageDialog(this, "No matching records found.", "Search", JOptionPane.INFORMATION_MESSAGE);
            }
        });

        clearBtn.addActionListener(e -> { queryF.setText(""); model.setRowCount(0); });
        queryF.addActionListener(e -> searchBtn.doClick());

        return root;
    }
}
