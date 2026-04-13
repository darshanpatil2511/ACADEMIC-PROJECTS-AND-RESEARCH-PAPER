package com.badas.ui.dashboard;

import com.badas.dao.PatientDAO;
import com.badas.model.Patient;
import com.badas.service.AuthService;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.util.List;

public class ReceptionistDashboard extends BaseFrame {

    private static final String NAV_REGISTER = "Register Patient";
    private static final String NAV_LIST     = "Patient List";

    private final PatientDAO patientDAO = new PatientDAO();

    private DefaultTableModel tableModel;
    private JTable            patientTable;
    private List<Patient>     patients;

    public ReceptionistDashboard() { super("Receptionist Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_REGISTER, NAV_LIST };
    }
    @Override protected String getDefaultItem() { return NAV_REGISTER; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_REGISTER -> setContent(buildRegisterPanel());
            case NAV_LIST     -> setContent(buildListPanel());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Register patient panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildRegisterPanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.add(pageTitle("Register New Patient"), BorderLayout.NORTH);

        JPanel form = new JPanel(new GridBagLayout());
        form.setBorder(new EmptyBorder(UIConstants.GAP_LG, 0, UIConstants.GAP_LG, 0));
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets  = new Insets(UIConstants.GAP_SM, UIConstants.GAP_SM,
                                  UIConstants.GAP_SM, UIConstants.GAP_SM);
        gbc.fill    = GridBagConstraints.HORIZONTAL;
        gbc.weightx = 1.0;

        JTextField nameF     = styledField(24);
        JTextField ageF      = styledField(8);
        JTextField contactF  = styledField(18);
        JTextArea  symptomsA = new JTextArea(4, 30);
        symptomsA.setFont(UIConstants.FONT_BODY);
        symptomsA.setLineWrap(true);
        symptomsA.setWrapStyleWord(true);
        JScrollPane sympScroll = new JScrollPane(symptomsA);

        addFormRow(form, gbc, 0, "Full Name *",    nameF);
        addFormRow(form, gbc, 1, "Age *",           ageF);
        addFormRow(form, gbc, 2, "Contact Number", contactF);
        addFormTextArea(form, gbc, 3, "Symptoms",  sympScroll);

        root.add(form, BorderLayout.CENTER);

        // Buttons
        JPanel btns = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, 0));

        JButton saveBtn = successButton("Register Patient");
        saveBtn.addActionListener(e -> {
            String name    = nameF.getText().trim();
            String ageStr  = ageF.getText().trim();
            String contact = contactF.getText().trim();
            String symp    = symptomsA.getText().trim();
            if (name.isEmpty() || ageStr.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Name and Age are required.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            int age;
            try {
                age = Integer.parseInt(ageStr);
                if (age < 0 || age > 150) throw new NumberFormatException();
            } catch (NumberFormatException ex) {
                JOptionPane.showMessageDialog(this, "Age must be a number between 0 and 150.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            Patient p = new Patient(name, age, contact, symp);
            String registeredBy = currentUser != null ? currentUser.getUsername() : "receptionist";
            p.setRegisteredBy(registeredBy);
            int id = patientDAO.save(p);
            if (id > 0) {
                nameF.setText(""); ageF.setText(""); contactF.setText(""); symptomsA.setText("");
                JOptionPane.showMessageDialog(this, "Patient registered (ID: " + id + ").", "Success", JOptionPane.INFORMATION_MESSAGE);
            } else {
                JOptionPane.showMessageDialog(this, "Failed to register patient. Please try again.", "Error", JOptionPane.ERROR_MESSAGE);
            }
        });
        btns.add(saveBtn);

        JButton clearBtn = new JButton("Clear Form");
        clearBtn.addActionListener(e -> { nameF.setText(""); ageF.setText(""); contactF.setText(""); symptomsA.setText(""); });
        btns.add(clearBtn);

        root.add(btns, BorderLayout.SOUTH);
        return root;
    }

    private void addFormRow(JPanel panel, GridBagConstraints gbc, int row, String label, JComponent field) {
        gbc.gridx = 0; gbc.gridy = row; gbc.weightx = 0.3;
        JLabel lbl = new JLabel(label);
        lbl.setFont(UIConstants.FONT_BODY_BOLD);
        panel.add(lbl, gbc);
        gbc.gridx = 1; gbc.weightx = 0.7;
        panel.add(field, gbc);
    }

    private void addFormTextArea(JPanel panel, GridBagConstraints gbc, int row, String label, JComponent field) {
        gbc.gridx = 0; gbc.gridy = row; gbc.weightx = 0.3; gbc.anchor = GridBagConstraints.NORTHWEST;
        JLabel lbl = new JLabel(label);
        lbl.setFont(UIConstants.FONT_BODY_BOLD);
        panel.add(lbl, gbc);
        gbc.gridx = 1; gbc.weightx = 0.7; gbc.anchor = GridBagConstraints.CENTER;
        panel.add(field, gbc);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Patient list panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildListPanel() {
        patients = patientDAO.findAll();
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Title + refresh
        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Registered Patients"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildListPanel()));
        titleRow.add(refreshBtn, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Table
        String[] cols = {"#", "Name", "Age", "Contact", "Symptoms", "Status", "Registered"};
        tableModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        patientTable = new JTable(tableModel);
        styleTable(patientTable);
        patientTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        patientTable.getColumnModel().getColumn(1).setPreferredWidth(140);

        int i = 1;
        for (Patient p : patients) {
            tableModel.addRow(new Object[]{
                i++, p.getName(), p.getAge(), p.getContact(),
                p.getSymptoms(), p.getStatus(),
                p.getRegisteredAt() != null ? p.getRegisteredAt().substring(0, 10) : ""
            });
        }

        JScrollPane scroll = new JScrollPane(patientTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);

        // Delete button
        JPanel btns = new JPanel(new FlowLayout(FlowLayout.RIGHT));
        JButton deleteBtn = dangerButton("Delete Selected");
        deleteBtn.addActionListener(e -> {
            int row = patientTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a patient first.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            Patient p = patients.get(row);
            int confirm = JOptionPane.showConfirmDialog(this,
                "Delete patient \"" + p.getName() + "\"?", "Confirm", JOptionPane.YES_NO_OPTION);
            if (confirm == JOptionPane.YES_OPTION) {
                patientDAO.delete(p.getId());
                setContent(buildListPanel());
                JOptionPane.showMessageDialog(this, "Patient record deleted.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        btns.add(deleteBtn);
        root.add(btns, BorderLayout.SOUTH);
        return root;
    }
}
