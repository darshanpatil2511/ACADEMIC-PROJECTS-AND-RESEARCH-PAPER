package com.badas.ui.dispatcher;

import com.badas.dao.DispatchDAO;
import com.badas.model.DispatchRequest;
import com.badas.service.ReportService;
import com.badas.service.SymptomAnalyzer;
import com.badas.service.SymptomAnalyzer.Severity;
import com.badas.ui.common.BaseFrame;
import com.badas.ui.common.UIConstants;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.border.TitledBorder;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.util.List;

/**
 * Dispatcher dashboard with two modes:
 *
 *  1. "Active Dispatches" — table view of all dispatch_requests with
 *     Dispatch / Cancel / Delete actions.
 *
 *  2. "New Emergency"     — 3-step wizard:
 *       Step 1: Patient Intake  (name, age, contact, location)
 *       Step 2: Symptom Analysis (description + analyse)
 *       Step 3: Recommendation  (result + confirm dispatch)
 *
 * After a dispatch is confirmed, a report is saved and the user is
 * returned to the Active Dispatches view.
 */
public class DispatcherDashboard extends BaseFrame {

    private static final String NAV_DISPATCHES = "Active Dispatches";
    private static final String NAV_NEW        = "New Emergency";

    private final DispatchDAO    dispatchDAO = new DispatchDAO();
    private final SymptomAnalyzer analyzer   = new SymptomAnalyzer();
    private final ReportService  reporter    = new ReportService();

    // Wizard state — carried across panels
    private String   wizName, wizContact, wizLocation;
    private int      wizAge;
    private String   wizSymptoms;
    private Severity wizSeverity;
    private String   wizAmbulanceType;

    // Dispatch table state
    private DefaultTableModel dispatchModel;
    private JTable            dispatchTable;
    private List<DispatchRequest> dispatches;

    public DispatcherDashboard() { super("Dispatcher Dashboard"); }

    @Override protected String[] getSidebarItems() {
        return new String[]{ NAV_DISPATCHES, NAV_NEW };
    }
    @Override protected String getDefaultItem() { return NAV_DISPATCHES; }

    @Override
    protected void showPanel(String navItem) {
        switch (navItem) {
            case NAV_DISPATCHES -> setContent(buildDispatchesPanel());
            case NAV_NEW        -> { resetWizard(); setContent(buildWizardPanel()); }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Active Dispatches panel
    // ─────────────────────────────────────────────────────────────────────────

    private JPanel buildDispatchesPanel() {
        dispatches = dispatchDAO.findAll();
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        JPanel titleRow = new JPanel(new BorderLayout());
        titleRow.add(pageTitle("Active Dispatches"), BorderLayout.WEST);

        JPanel buttons = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_SM, 0));
        JButton newBtn = dangerButton("+ New Emergency");
        newBtn.addActionListener(e -> showPanel(NAV_NEW));
        JButton refreshBtn = primaryButton("Refresh");
        refreshBtn.addActionListener(e -> setContent(buildDispatchesPanel()));
        buttons.add(newBtn);
        buttons.add(refreshBtn);
        titleRow.add(buttons, BorderLayout.EAST);
        root.add(titleRow, BorderLayout.NORTH);

        // Table
        String[] cols = {"#", "Patient Name", "Location", "Symptoms", "Severity",
                         "Ambulance Type", "Status", "Dispatched By", "Time"};
        dispatchModel = new DefaultTableModel(cols, 0) {
            @Override public boolean isCellEditable(int r, int c) { return false; }
        };
        dispatchTable = new JTable(dispatchModel);
        styleTable(dispatchTable);
        dispatchTable.getColumnModel().getColumn(0).setPreferredWidth(40);
        dispatchTable.getColumnModel().getColumn(1).setPreferredWidth(120);
        dispatchTable.getColumnModel().getColumn(4).setPreferredWidth(80);
        dispatchTable.getColumnModel().getColumn(6).setPreferredWidth(100);

        // Status colour renderer
        dispatchTable.getColumnModel().getColumn(6).setCellRenderer(new DefaultTableCellRenderer() {
            @Override public Component getTableCellRendererComponent(JTable t, Object val,
                    boolean sel, boolean foc, int row, int col) {
                super.getTableCellRendererComponent(t, val, sel, foc, row, col);
                if (!sel && val != null) {
                    setBackground(row % 2 == 0 ? Color.WHITE : UIConstants.TABLE_ROW_ALT);
                    setForeground(switch (val.toString()) {
                        case "Dispatched" -> UIConstants.SUCCESS;
                        case "Cancelled"  -> UIConstants.ACCENT_RED;
                        default           -> UIConstants.WARNING;
                    });
                    setFont(UIConstants.FONT_BODY_BOLD);
                }
                return this;
            }
        });

        loadDispatchTable();
        JScrollPane scroll = new JScrollPane(dispatchTable);
        scroll.setBorder(BorderFactory.createLineBorder(new Color(220, 220, 220)));
        root.add(scroll, BorderLayout.CENTER);
        root.add(buildDispatchActionBar(), BorderLayout.SOUTH);
        return root;
    }

    private void loadDispatchTable() {
        dispatchModel.setRowCount(0);
        int i = 1;
        for (DispatchRequest dr : dispatches) {
            String time = dr.getCreatedAt() != null
                    ? dr.getCreatedAt().substring(0, Math.min(16, dr.getCreatedAt().length()))
                    : "";
            dispatchModel.addRow(new Object[]{
                i++, dr.getPatientName(), dr.getLocation(), dr.getSymptoms(),
                dr.getSeverity(), dr.getAmbulanceType(), dr.getStatus(),
                dr.getDispatchedBy(), time
            });
        }
    }

    private JPanel buildDispatchActionBar() {
        JPanel bar = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_MD, UIConstants.GAP_SM));
        bar.setBorder(new EmptyBorder(UIConstants.GAP_SM, 0, 0, 0));

        JButton dispatchBtn = successButton("Mark Dispatched");
        dispatchBtn.addActionListener(e -> updateSelectedStatus("Dispatched"));
        bar.add(dispatchBtn);

        JButton cancelBtn = dangerButton("Mark Cancelled");
        cancelBtn.addActionListener(e -> updateSelectedStatus("Cancelled"));
        bar.add(cancelBtn);

        JButton deleteBtn = new JButton("Delete Record");
        deleteBtn.setFont(UIConstants.FONT_BUTTON);
        deleteBtn.addActionListener(e -> {
            int row = dispatchTable.getSelectedRow();
            if (row < 0) { showInfo("Select a record first."); return; }
            int confirm = JOptionPane.showConfirmDialog(this,
                "Delete this dispatch record?", "Confirm", JOptionPane.YES_NO_OPTION);
            if (confirm == JOptionPane.YES_OPTION) {
                dispatchDAO.delete(dispatches.get(row).getId());
                setContent(buildDispatchesPanel());
            }
        });
        bar.add(deleteBtn);

        return bar;
    }

    private void updateSelectedStatus(String status) {
        int row = dispatchTable.getSelectedRow();
        if (row < 0) { showInfo("Select a dispatch record first."); return; }
        dispatchDAO.updateStatus(dispatches.get(row).getId(), status);
        setContent(buildDispatchesPanel());
        JOptionPane.showMessageDialog(this, "Status updated to: " + status, "Done", JOptionPane.INFORMATION_MESSAGE);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Wizard — top-level container with CardLayout
    // ─────────────────────────────────────────────────────────────────────────

    private static final String CARD_STEP1 = "step1";
    private static final String CARD_STEP2 = "step2";
    private static final String CARD_STEP3 = "step3";

    private CardLayout wizardCards;
    private JPanel     wizardContainer;

    private JPanel buildWizardPanel() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));

        // Wizard header
        JLabel title = pageTitle("New Emergency \u2014 Dispatch Wizard");
        root.add(title, BorderLayout.NORTH);

        // Progress indicator
        root.add(buildProgressBar(1), BorderLayout.AFTER_LAST_LINE);

        // Card container
        wizardCards = new CardLayout();
        wizardContainer = new JPanel(wizardCards);
        wizardContainer.add(buildStep1(), CARD_STEP1);
        wizardContainer.add(buildStep2(), CARD_STEP2);
        wizardContainer.add(buildStep3(), CARD_STEP3);

        root.add(wizardContainer, BorderLayout.CENTER);
        return root;
    }

    private JPanel buildProgressBar(int activeStep) {
        JPanel bar = new JPanel(new FlowLayout(FlowLayout.CENTER, UIConstants.GAP_LG, UIConstants.GAP_SM));
        String[] steps = {"1  Patient Info", "2  Symptoms", "3  Recommendation"};
        for (int i = 0; i < steps.length; i++) {
            JLabel lbl = new JLabel(steps[i]);
            lbl.setFont(i + 1 == activeStep ? UIConstants.FONT_BODY_BOLD : UIConstants.FONT_BODY);
            lbl.setForeground(i + 1 == activeStep ? UIConstants.PRIMARY : new Color(150, 150, 150));
            bar.add(lbl);
            if (i < steps.length - 1) {
                JLabel sep = new JLabel("  \u2192  ");
                sep.setForeground(new Color(180, 180, 180));
                bar.add(sep);
            }
        }
        return bar;
    }

    // ─── Step 1: Patient Intake ───────────────────────────────────────────────

    private JPanel buildStep1() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));

        JPanel card = buildStepCard("Step 1: Patient Information",
            "Enter the basic details of the patient requiring emergency assistance.");

        JPanel form = new JPanel(new GridBagLayout());
        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets = new Insets(UIConstants.GAP_SM, UIConstants.GAP_SM, UIConstants.GAP_SM, UIConstants.GAP_SM);
        gbc.fill   = GridBagConstraints.HORIZONTAL;

        JTextField nameF     = styledField(22);
        JTextField ageF      = styledField(8);
        JTextField contactF  = styledField(18);
        JTextField locationF = styledField(22);

        addFormRow(form, gbc, 0, "Full Name *",            nameF);
        addFormRow(form, gbc, 1, "Age *",                  ageF);
        addFormRow(form, gbc, 2, "Contact Number",         contactF);
        addFormRow(form, gbc, 3, "Pickup Location *",      locationF);

        card.add(form, BorderLayout.CENTER);

        // Nav buttons
        JPanel nav = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_MD, 0));
        JButton cancelBtn = new JButton("Cancel");
        cancelBtn.addActionListener(e -> showPanel(NAV_DISPATCHES));
        nav.add(cancelBtn);

        JButton nextBtn = primaryButton("Next  \u2192");
        nextBtn.addActionListener(e -> {
            String name     = nameF.getText().trim();
            String ageStr   = ageF.getText().trim();
            String contact  = contactF.getText().trim();
            String location = locationF.getText().trim();

            if (name.isEmpty() || ageStr.isEmpty() || location.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Name, Age, and Location are required.", "Validation", JOptionPane.WARNING_MESSAGE);
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
            wizName     = name;
            wizAge      = age;
            wizContact  = contact;
            wizLocation = location;
            // Rebuild step 2 to show patient name in header
            wizardContainer.remove(1);
            wizardContainer.add(buildStep2(), CARD_STEP2, 1);
            wizardCards.show(wizardContainer, CARD_STEP2);
        });
        nav.add(nextBtn);

        root.add(card, BorderLayout.CENTER);
        root.add(nav,  BorderLayout.SOUTH);
        return root;
    }

    // ─── Step 2: Symptom Analysis ─────────────────────────────────────────────

    private JPanel buildStep2() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));

        JPanel card = buildStepCard("Step 2: Symptom Analysis",
            "Describe the patient's symptoms. Click Analyse to determine severity.");

        // Symptom input
        JTextArea sympArea = new JTextArea(6, 40);
        sympArea.setFont(UIConstants.FONT_BODY);
        sympArea.setLineWrap(true);
        sympArea.setWrapStyleWord(true);
        JScrollPane scroll = new JScrollPane(sympArea);
        scroll.setBorder(BorderFactory.createTitledBorder(
            BorderFactory.createLineBorder(new Color(200, 200, 200)),
            "Describe symptoms",
            TitledBorder.LEFT, TitledBorder.TOP,
            UIConstants.FONT_SMALL));

        // Result panel
        JPanel resultPanel = new JPanel(new BorderLayout());
        resultPanel.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));
        JLabel resultLabel = new JLabel("  Analysis result will appear here after clicking Analyse.");
        resultLabel.setFont(UIConstants.FONT_BODY);
        resultLabel.setForeground(new Color(120, 120, 120));
        resultPanel.add(resultLabel, BorderLayout.CENTER);

        JPanel center = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        center.add(scroll,       BorderLayout.NORTH);
        center.add(resultPanel,  BorderLayout.CENTER);
        card.add(center, BorderLayout.CENTER);

        // Analyse button inline
        JButton analyseBtn = successButton("Analyse Symptoms");
        analyseBtn.addActionListener(e -> {
            String symp = sympArea.getText().trim();
            if (symp.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Please describe the symptoms.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            Severity sev = analyzer.analyze(symp);
            String label = analyzer.severityLabel(sev);
            String ambulance = analyzer.recommendAmbulance(sev, wizAge);
            Color sColor = UIConstants.severityColor(label);

            resultLabel.setText("<html>"
                + "<b>Severity:</b> <span style='color:" + toHex(sColor) + "'>" + label + "</span>"
                + "&nbsp;&nbsp;&nbsp;"
                + "<b>Recommended:</b> " + ambulance
                + "</html>");

            // Store for Step 3
            wizSymptoms     = symp;
            wizSeverity     = sev;
            wizAmbulanceType = ambulance;
        });

        JPanel topBtns = new JPanel(new FlowLayout(FlowLayout.LEFT));
        topBtns.add(analyseBtn);
        card.add(topBtns, BorderLayout.NORTH);

        // Nav buttons
        JPanel nav = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_MD, 0));
        JButton backBtn = new JButton("\u2190  Back");
        backBtn.addActionListener(e -> wizardCards.show(wizardContainer, CARD_STEP1));
        nav.add(backBtn);

        JButton cancelBtn = new JButton("Cancel");
        cancelBtn.addActionListener(e -> showPanel(NAV_DISPATCHES));
        nav.add(cancelBtn);

        JButton nextBtn = primaryButton("Next  \u2192");
        nextBtn.addActionListener(e -> {
            if (wizSeverity == null) {
                JOptionPane.showMessageDialog(this, "Please analyse symptoms before proceeding.", "Validation", JOptionPane.WARNING_MESSAGE);
                return;
            }
            // Rebuild step 3 with current data
            wizardContainer.remove(2);
            wizardContainer.add(buildStep3(), CARD_STEP3, 2);
            wizardCards.show(wizardContainer, CARD_STEP3);
        });
        nav.add(nextBtn);

        root.add(card, BorderLayout.CENTER);
        root.add(nav,  BorderLayout.SOUTH);
        return root;
    }

    // ─── Step 3: Recommendation & Dispatch ───────────────────────────────────

    private JPanel buildStep3() {
        JPanel root = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        root.setBorder(new EmptyBorder(UIConstants.GAP_MD, 0, 0, 0));

        JPanel card = buildStepCard("Step 3: Ambulance Recommendation",
            "Review the recommendation and confirm dispatch.");

        // Summary block
        JPanel summary = new JPanel(new GridLayout(0, 2, UIConstants.GAP_MD, UIConstants.GAP_SM));
        summary.setBorder(new EmptyBorder(UIConstants.GAP_MD, UIConstants.GAP_LG,
                UIConstants.GAP_MD, UIConstants.GAP_LG));

        String severityLabel = wizSeverity != null ? analyzer.severityLabel(wizSeverity) : "—";
        Color  severityColor = UIConstants.severityColor(severityLabel);

        addSummaryRow(summary, "Patient Name",     wizName);
        addSummaryRow(summary, "Age",              String.valueOf(wizAge));
        addSummaryRow(summary, "Contact",          wizContact != null ? wizContact : "—");
        addSummaryRow(summary, "Location",         wizLocation);
        addSummaryRow(summary, "Reported Symptoms", wizSymptoms);

        JLabel sevKey = new JLabel("Severity Level");
        sevKey.setFont(UIConstants.FONT_BODY_BOLD);
        JLabel sevVal = new JLabel(severityLabel);
        sevVal.setFont(UIConstants.FONT_BODY_BOLD);
        sevVal.setForeground(severityColor);
        summary.add(sevKey); summary.add(sevVal);

        addSummaryRow(summary, "Ambulance Recommended", wizAmbulanceType != null ? wizAmbulanceType : "—");

        card.add(summary, BorderLayout.CENTER);

        // Dispatch note
        JPanel bottom = new JPanel(new BorderLayout());
        JLabel note = new JLabel("  Clicking 'Confirm Dispatch' will save this request to the database and generate a report.");
        note.setFont(UIConstants.FONT_SMALL);
        note.setForeground(new Color(100, 100, 100));
        bottom.add(note, BorderLayout.CENTER);
        card.add(bottom, BorderLayout.SOUTH);

        // Nav buttons
        JPanel nav = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_MD, 0));
        JButton backBtn = new JButton("\u2190  Back");
        backBtn.addActionListener(e -> wizardCards.show(wizardContainer, CARD_STEP2));
        nav.add(backBtn);

        JButton cancelBtn = new JButton("Cancel");
        cancelBtn.addActionListener(e -> showPanel(NAV_DISPATCHES));
        nav.add(cancelBtn);

        JButton dispatchBtn = dangerButton("Confirm Dispatch");
        dispatchBtn.addActionListener(e -> confirmDispatch());
        nav.add(dispatchBtn);

        root.add(card, BorderLayout.CENTER);
        root.add(nav,  BorderLayout.SOUTH);
        return root;
    }

    // ─── Confirm and save ────────────────────────────────────────────────────

    private void confirmDispatch() {
        String dispatchedBy = currentUser != null ? currentUser.getUsername() : "dispatcher";
        String severityStr  = wizSeverity != null ? analyzer.severityLabel(wizSeverity) : "Undetermined";

        DispatchRequest req = new DispatchRequest(
            wizName, wizLocation, wizSymptoms,
            wizAmbulanceType, severityStr, dispatchedBy
        );
        int id = dispatchDAO.save(req);

        // Generate report file
        String reportPath = reporter.generateDispatchReport(
            wizName, wizAge, wizContact, wizLocation,
            wizSymptoms, severityStr, wizAmbulanceType, dispatchedBy
        );

        String msg = "Dispatch confirmed and saved (ID: " + id + ").";
        if (reportPath != null) {
            msg += "\n\nReport saved to:\n" + reportPath;
        }
        JOptionPane.showMessageDialog(this, msg, "Dispatch Confirmed", JOptionPane.INFORMATION_MESSAGE);

        resetWizard();
        showPanel(NAV_DISPATCHES);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private void resetWizard() {
        wizName = null; wizContact = null; wizLocation = null;
        wizAge  = 0;    wizSymptoms = null;
        wizSeverity = null; wizAmbulanceType = null;
    }

    private JPanel buildStepCard(String title, String subtitle) {
        JPanel card = new JPanel(new BorderLayout(0, UIConstants.GAP_MD));
        card.setBorder(BorderFactory.createCompoundBorder(
            BorderFactory.createLineBorder(new Color(220, 220, 220)),
            new EmptyBorder(UIConstants.GAP_LG, UIConstants.GAP_LG,
                            UIConstants.GAP_LG, UIConstants.GAP_LG)
        ));

        JPanel header = new JPanel(new BorderLayout());
        JLabel titleLbl = new JLabel(title);
        titleLbl.setFont(UIConstants.FONT_SECTION);
        titleLbl.setForeground(UIConstants.PRIMARY);
        JLabel subtitleLbl = new JLabel(subtitle);
        subtitleLbl.setFont(UIConstants.FONT_SMALL);
        subtitleLbl.setForeground(new Color(120, 120, 120));
        header.add(titleLbl,    BorderLayout.NORTH);
        header.add(subtitleLbl, BorderLayout.CENTER);
        card.add(header, BorderLayout.NORTH);
        return card;
    }

    private void addFormRow(JPanel panel, GridBagConstraints gbc, int row, String label, JComponent field) {
        gbc.gridx = 0; gbc.gridy = row; gbc.weightx = 0.3;
        JLabel lbl = new JLabel(label); lbl.setFont(UIConstants.FONT_BODY_BOLD); panel.add(lbl, gbc);
        gbc.gridx = 1; gbc.weightx = 0.7; panel.add(field, gbc);
    }

    private void addSummaryRow(JPanel panel, String key, String value) {
        JLabel k = new JLabel(key);
        k.setFont(UIConstants.FONT_BODY_BOLD);
        JLabel v = new JLabel(value != null ? value : "—");
        v.setFont(UIConstants.FONT_BODY);
        panel.add(k); panel.add(v);
    }

    private String toHex(Color c) {
        return String.format("#%02x%02x%02x", c.getRed(), c.getGreen(), c.getBlue());
    }

    private void showInfo(String msg) {
        JOptionPane.showMessageDialog(this, msg, "Info", JOptionPane.INFORMATION_MESSAGE);
    }
}
