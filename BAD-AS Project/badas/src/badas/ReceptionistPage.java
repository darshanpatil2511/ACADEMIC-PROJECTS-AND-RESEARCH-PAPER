package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class ReceptionistPage {
    private JFrame frame;
    private JTable patientTable;
    private DefaultTableModel tableModel;
    private JTextField nameField, ageField, symptomsField, contactField;
    private final String FILE_PATH = "patient_records.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new ReceptionistPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Receptionist - Patient Registration");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(900, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Patient Registration", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Patient Records
        String[] columnNames = {"Patient Name", "Age", "Symptoms", "Contact Info"};
        tableModel = new DefaultTableModel(columnNames, 0);
        patientTable = new JTable(tableModel);
        loadPatientData();

        JScrollPane tableScrollPane = new JScrollPane(patientTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Form Panel for Adding/Updating Patients
        JPanel formPanel = new JPanel(new GridLayout(5, 2, 10, 10));
        formPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        formPanel.add(new JLabel("Patient Name:"));
        nameField = new JTextField();
        formPanel.add(nameField);

        formPanel.add(new JLabel("Age:"));
        ageField = new JTextField();
        formPanel.add(ageField);

        formPanel.add(new JLabel("Symptoms:"));
        symptomsField = new JTextField();
        formPanel.add(symptomsField);

        formPanel.add(new JLabel("Contact Info:"));
        contactField = new JTextField();
        formPanel.add(contactField);

        JButton addButton = new JButton("Add Patient");
        addButton.addActionListener(this::addPatient);
        formPanel.add(addButton);

        JButton updateButton = new JButton("Update Patient");
        updateButton.addActionListener(this::updatePatient);
        formPanel.add(updateButton);

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
            new ReceptionistPage().createAndShowGUI();
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

    // Add a new patient
    private void addPatient(ActionEvent e) {
        String name = nameField.getText().trim();
        String age = ageField.getText().trim();
        String symptoms = symptomsField.getText().trim();
        String contact = contactField.getText().trim();

        if (!name.isEmpty() && !age.isEmpty() && !symptoms.isEmpty() && !contact.isEmpty()) {
            tableModel.addRow(new String[]{name, age, symptoms, contact});
            savePatientData();
            clearFields();
            JOptionPane.showMessageDialog(frame, "Patient added successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Update an existing patient
    private void updatePatient(ActionEvent e) {
        int selectedRow = patientTable.getSelectedRow();
        if (selectedRow != -1) {
            String name = nameField.getText().trim();
            String age = ageField.getText().trim();
            String symptoms = symptomsField.getText().trim();
            String contact = contactField.getText().trim();

            if (!name.isEmpty() && !age.isEmpty() && !symptoms.isEmpty() && !contact.isEmpty()) {
                tableModel.setValueAt(name, selectedRow, 0);
                tableModel.setValueAt(age, selectedRow, 1);
                tableModel.setValueAt(symptoms, selectedRow, 2);
                tableModel.setValueAt(contact, selectedRow, 3);
                savePatientData();
                clearFields();
                JOptionPane.showMessageDialog(frame, "Patient updated successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
            } else {
                JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
            }
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a patient to update!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Clear input fields
    private void clearFields() {
        nameField.setText("");
        ageField.setText("");
        symptomsField.setText("");
        contactField.setText("");
    }
}
