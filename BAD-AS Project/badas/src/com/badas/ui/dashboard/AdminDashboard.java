package com.badas.ui.dashboard;

import com.badas.dao.HospitalDAO;
import com.badas.model.Hospital;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.table.DefaultTableModel;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.Insets;
import java.awt.*;
import java.util.List;

public class AdminDashboard extends BaseFrame {

    private static final String NAV_HOSPITALS = "Hospital Management";
    private static final String NAV_STATS     = "Statistics";

    private final HospitalDAO hospitalDAO = new HospitalDAO();

    // Hospital table state
    private DefaultTableModel hospitalModel;
    private JTable            hospitalTable;
    private List<Hospital>    hospitals;

    public AdminDashboard() {
        super("Admin Dashboard");
    }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_HOSPITALS, NAV_STATS };
    }

    @Override protected String getDefaultItem() { return NAV_HOSPITALS; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_HOSPITALS -> setContent(buildHospitalPanel());
            case NAV_STATS     -> setContent(buildStatsPanel());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Hospital management panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildHospitalPanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Title row
        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Hospital Management"), BorderLayout.WEST);
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> refreshHospitalTable());
        titleRow.add(refreshBtn, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Table
        String[] cols = {"#", "Hospital Name", "Location", "Total Ambulances", "Available"};
        hospitalModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        hospitalTable = new JTable(hospitalModel);
        styleTable(hospitalTable);
        hospitalTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        hospitalTable.getColumnModel().getColumn(1).setPreferredWidth(280);
        hospitalTable.getColumnModel().getColumn(2).setPreferredWidth(160);
        loadHospitals();

        JScrollPane scroll = new JScrollPane(hospitalTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);

        // Bottom form + action buttons
        root.add(buildHospitalForm(), BorderLayout.SOUTH);

        return root;
    }

    private JPanel buildHospitalForm() {
        JPanel wrapper = new JPanel(new BorderLayout(UIConstants.GAP_MD, UIConstants.GAP_SM));
        wrapper.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createMatteBorder(1, 0, 0, 0, new Color(220, 220, 220)),
            new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0)
        ));

        // ── Input grid: label on left, field on right ──────────────────────
        JPanel grid = new JPanel(new GridBagLayout());
        GridBagConstraints g = new GridBagConstraints();
        g.insets = new Insets(UIConstants.GAP_XS, UIConstants.GAP_SM,
                              UIConstants.GAP_XS, UIConstants.GAP_SM);
        g.anchor = GridBagConstraints.WEST;

        JTextField nameF = styledField(22);
        JTextField locF  = styledField(22);
        JTextField ambF  = styledField(8);

        // Row 0 — labels
        g.gridy = 0; g.fill = GridBagConstraints.NONE; g.weightx = 0;
        g.gridx = 0; grid.add(labelFor("Hospital Name"), g);
        g.gridx = 2; grid.add(labelFor("Location"), g);
        g.gridx = 4; grid.add(labelFor("Ambulances"), g);

        // Row 1 — fields
        g.gridy = 1; g.fill = GridBagConstraints.HORIZONTAL; g.weightx = 1.0;
        g.gridx = 0; grid.add(nameF, g);
        g.gridx = 1; g.fill = GridBagConstraints.NONE; g.weightx = 0;
        grid.add(Box.createHorizontalStrut(UIConstants.GAP_MD), g);
        g.gridx = 2; g.fill = GridBagConstraints.HORIZONTAL; g.weightx = 1.0;
        grid.add(locF, g);
        g.gridx = 3; g.fill = GridBagConstraints.NONE; g.weightx = 0;
        grid.add(Box.createHorizontalStrut(UIConstants.GAP_MD), g);
        g.gridx = 4; g.fill = GridBagConstraints.HORIZONTAL; g.weightx = 0.3;
        grid.add(ambF, g);

        wrapper.add(grid, BorderLayout.CENTER);

        // ── Action buttons ─────────────────────────────────────────────────
        JPanel btns = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_SM, 0));

        JButton addBtn = successButton("Add Hospital");
        addBtn.addActionListener(e -> {
            String name   = nameF.getText().trim();
            String loc    = locF.getText().trim();
            String ambStr = ambF.getText().trim();
            if (name.isEmpty() || loc.isEmpty() || ambStr.isEmpty()) {
                JOptionPane.showMessageDialog(this, "All fields are required.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            int amb;
            try { amb = Integer.parseInt(ambStr); if (amb < 0) throw new NumberFormatException(); }
            catch (NumberFormatException ex) {
                JOptionPane.showMessageDialog(this, "Ambulance count must be a non-negative integer.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            hospitalDAO.save(new Hospital(name, loc, amb));
            nameF.setText(""); locF.setText(""); ambF.setText("");
            refreshHospitalTable();
            JOptionPane.showMessageDialog(this, "Hospital added successfully.", "Success", JOptionPane.INFORMATION_MESSAGE);
        });
        btns.add(addBtn);

        JButton editBtn = primaryButton("Edit Selected");
        editBtn.addActionListener(e -> {
            int row = hospitalTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a hospital to edit.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            showEditDialog(hospitals.get(row));
        });
        btns.add(editBtn);

        JButton delBtn = dangerButton("Delete Selected");
        delBtn.addActionListener(e -> {
            int row = hospitalTable.getSelectedRow();
            if (row < 0) { JOptionPane.showMessageDialog(this, "Select a hospital to delete.", "Info", JOptionPane.INFORMATION_MESSAGE); return; }
            Hospital h = hospitals.get(row);
            int confirm = JOptionPane.showConfirmDialog(this,
                "Delete \"" + h.getName() + "\"?", "Confirm Delete", JOptionPane.YES_NO_OPTION);
            if (confirm == JOptionPane.YES_OPTION) {
                hospitalDAO.delete(h.getId());
                refreshHospitalTable();
                JOptionPane.showMessageDialog(this, "Hospital deleted.", "Success", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        btns.add(delBtn);

        wrapper.add(btns, BorderLayout.SOUTH);
        return wrapper;
    }

    private JLabel labelFor(String text) {
        JLabel lbl = new JLabel(text);
        lbl.setFont(UIConstants.FONT_SMALL);
        lbl.setForeground(UIConstants.STATUS_BAR_TEXT);
        return lbl;
    }

    private void showEditDialog(Hospital h) {
        JTextField nameF = new JTextField(h.getName(), 20);
        JTextField locF  = new JTextField(h.getLocation(), 14);
        JTextField ambF  = new JTextField(String.valueOf(h.getAmbulanceCount()), 5);
        JTextField avaF  = new JTextField(String.valueOf(h.getAvailableAmbulances()), 5);

        JPanel form = new JPanel(new GridLayout(4, 2, UIConstants.GAP_SM, UIConstants.GAP_SM));
        form.add(new JLabel("Name:")); form.add(nameF);
        form.add(new JLabel("Location:")); form.add(locF);
        form.add(new JLabel("Total Ambulances:")); form.add(ambF);
        form.add(new JLabel("Available Ambulances:")); form.add(avaF);

        int result = JOptionPane.showConfirmDialog(this, form, "Edit Hospital", JOptionPane.OK_CANCEL_OPTION);
        if (result == JOptionPane.OK_OPTION) {
            try {
                h.setName(nameF.getText().trim());
                h.setLocation(locF.getText().trim());
                h.setAmbulanceCount(Integer.parseInt(ambF.getText().trim()));
                h.setAvailableAmbulances(Integer.parseInt(avaF.getText().trim()));
                hospitalDAO.update(h);
                refreshHospitalTable();
                JOptionPane.showMessageDialog(this, "Hospital updated.", "Success", JOptionPane.INFORMATION_MESSAGE);
            } catch (NumberFormatException ex) {
                JOptionPane.showMessageDialog(this, "Ambulance counts must be integers.", "Error", JOptionPane.ERROR_MESSAGE);
            }
        }
    }

    private void loadHospitals() {
        hospitals = hospitalDAO.findAll();
        hospitalModel.setRowCount(0);
        int i = 1;
        for (Hospital h : hospitals) {
            hospitalModel.addRow(new Object[]{
                i++, h.getName(), h.getLocation(), h.getAmbulanceCount(), h.getAvailableAmbulances()
            });
        }
    }

    private void refreshHospitalTable() { loadHospitals(); }

    // ─────────────────────────────────────────────────────────────────────────
    //  Stats panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildStatsPanel() {
        JPanel root = new JPanel(new BorderLayout());
        root.add(pageTitle("System Statistics"), BorderLayout.NORTH);

        JPanel cards = new JPanel(new GridLayout(2, 3, UIConstants.GAP_LG, UIConstants.GAP_LG));
        cards.setBorder(new EmptyBorder(UIConstants.GAP_LG, 0, 0, 0));

        List<Hospital> hs = hospitalDAO.findAll();
        int totalAmbulances = hs.stream().mapToInt(Hospital::getAmbulanceCount).sum();
        int available       = hs.stream().mapToInt(Hospital::getAvailableAmbulances).sum();

        cards.add(statCard("Total Hospitals",    String.valueOf(hs.size()),           UIConstants.PRIMARY));
        cards.add(statCard("Total Ambulances",   String.valueOf(totalAmbulances),     UIConstants.SUCCESS));
        cards.add(statCard("Available Ambulances", String.valueOf(available),         UIConstants.SECONDARY));

        root.add(cards, BorderLayout.CENTER);
        return root;
    }

    private JPanel statCard(String label, String value, Color color) {
        JPanel card = new JPanel(new BorderLayout());
        card.setBackground(color);
        card.setBorder(new EmptyBorder(UIConstants.GAP_LG, UIConstants.GAP_LG,
                UIConstants.GAP_LG, UIConstants.GAP_LG));

        JLabel val = new JLabel(value, SwingConstants.CENTER);
        val.setFont(new Font("Segoe UI", Font.BOLD, 44));
        val.setForeground(Color.WHITE);
        card.add(val, BorderLayout.CENTER);

        JLabel lbl = new JLabel(label, SwingConstants.CENTER);
        lbl.setFont(UIConstants.FONT_SECTION);
        lbl.setForeground(new Color(220, 235, 255));
        card.add(lbl, BorderLayout.SOUTH);

        return card;
    }
}
