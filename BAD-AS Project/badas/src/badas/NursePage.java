package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class NursePage {
    private JFrame frame;
    private JTable patientTable;
    private DefaultTableModel tableModel;
    private final String FILE_PATH = "patient_records.csv";
    private JTextField statusField;

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new NursePage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Nurse - Patient Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(900, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Patient Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Patient Records
        String[] columnNames = {"Patient Name", "Age", "Symptoms", "Diagnosis", "Prescription", "Status"};
        tableModel = new DefaultTableModel(columnNames, 0);
        patientTable = new JTable(tableModel);
        loadPatientData();

        JScrollPane tableScrollPane = new JScrollPane(patientTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Form Panel for Updating Status
        JPanel formPanel = new JPanel(new GridLayout(2, 2, 10, 10));
        formPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        formPanel.add(new JLabel("Update Status:"));
        statusField = new JTextField();
        formPanel.add(statusField);

        JButton updateStatusButton = new JButton("Update Status");
        updateStatusButton.addActionListener(this::updateStatus);
        formPanel.add(updateStatusButton);

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
            new NursePage().createAndShowGUI();
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

    // Update patient status
    private void updateStatus(ActionEvent e) {
        int selectedRow = patientTable.getSelectedRow();
        if (selectedRow != -1) {
            String status = statusField.getText().trim();

            if (!status.isEmpty()) {
                tableModel.setValueAt(status, selectedRow, 5);
                savePatientData();
                JOptionPane.showMessageDialog(frame, "Patient status updated successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
                statusField.setText("");
            } else {
                JOptionPane.showMessageDialog(frame, "Status field cannot be empty!", "Error", JOptionPane.ERROR_MESSAGE);
            }
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a patient to update!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
