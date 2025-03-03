package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class DoctorPage {
    private JFrame frame;
    private JTable patientTable;
    private DefaultTableModel tableModel;
    private JTextField diagnosisField, prescriptionField, searchField;
    private final String FILE_PATH = "patient_records.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new DoctorPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Doctor - Patient Records Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(900, 600);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Patient Records Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Patient Records
        String[] columnNames = {"Patient Name", "Age", "Symptoms", "Diagnosis", "Prescription"};
        tableModel = new DefaultTableModel(columnNames, 0);
        patientTable = new JTable(tableModel);
        loadPatientData();

        JScrollPane tableScrollPane = new JScrollPane(patientTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Form Panel for Diagnosis and Prescription
        JPanel formPanel = new JPanel(new GridLayout(3, 2, 10, 10));
        formPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        formPanel.add(new JLabel("Diagnosis:"));
        diagnosisField = new JTextField();
        formPanel.add(diagnosisField);

        formPanel.add(new JLabel("Prescription:"));
        prescriptionField = new JTextField();
        formPanel.add(prescriptionField);

        JButton updateButton = new JButton("Update Record");
        updateButton.addActionListener(this::updateRecord);
        formPanel.add(updateButton);

        JButton searchButton = new JButton("Search");
        searchButton.addActionListener(this::searchPatient);
        formPanel.add(searchButton);

        frame.add(formPanel, BorderLayout.SOUTH);

        // Button Panel for Navigation
        JPanel buttonPanel = new JPanel();

        JButton backButton = new JButton("Back to Login");
        backButton.addActionListener(e -> {
            frame.dispose();
            Login.main(new String[]{});
        });
        buttonPanel.add(backButton);

        JButton homeButton = new JButton("Home");
        homeButton.addActionListener(e -> {
            frame.dispose();
            new DoctorPage().createAndShowGUI();
        });
        buttonPanel.add(homeButton);

        frame.add(buttonPanel, BorderLayout.WEST);

        frame.setVisible(true);
    }

    // Load patient data from CSV file
    private void loadPatientData() {
        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] data = line.split(",");
                tableModel.addRow(data);
            }
        } catch (IOException e) {
            System.out.println("No existing patient data found. Starting with an empty list.");
        }
    }

    // Save patient data to CSV file
    private void savePatientData() {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(FILE_PATH))) {
            for (int i = 0; i < tableModel.getRowCount(); i++) {
                Vector<?> row = tableModel.getDataVector().elementAt(i);
                bw.write(String.join(",", row.toArray(new String[0])));
                bw.newLine();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // Update diagnosis and prescription
    private void updateRecord(ActionEvent e) {
        int selectedRow = patientTable.getSelectedRow();
        if (selectedRow != -1) {
            String diagnosis = diagnosisField.getText().trim();
            String prescription = prescriptionField.getText().trim();

            if (!diagnosis.isEmpty() && !prescription.isEmpty()) {
                tableModel.setValueAt(diagnosis, selectedRow, 3);
                tableModel.setValueAt(prescription, selectedRow, 4);
                savePatientData();
                JOptionPane.showMessageDialog(frame, "Record updated successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
                diagnosisField.setText("");
                prescriptionField.setText("");
            } else {
                JOptionPane.showMessageDialog(frame, "Diagnosis and Prescription fields cannot be empty!", "Error", JOptionPane.ERROR_MESSAGE);
            }
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a patient to update!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Search patient by name or symptoms
    private void searchPatient(ActionEvent e) {
        String searchTerm = JOptionPane.showInputDialog(frame, "Enter Patient Name or Symptoms to search:");
        if (searchTerm != null && !searchTerm.trim().isEmpty()) {
            for (int i = 0; i < tableModel.getRowCount(); i++) {
                String name = tableModel.getValueAt(i, 0).toString().toLowerCase();
                String symptoms = tableModel.getValueAt(i, 2).toString().toLowerCase();

                if (name.contains(searchTerm.toLowerCase()) || symptoms.contains(searchTerm.toLowerCase())) {
                    patientTable.setRowSelectionInterval(i, i);
                    patientTable.scrollRectToVisible(patientTable.getCellRect(i, 0, true));
                    return;
                }
            }
            JOptionPane.showMessageDialog(frame, "No matching records found!", "Info", JOptionPane.INFORMATION_MESSAGE);
        }
    }
}
