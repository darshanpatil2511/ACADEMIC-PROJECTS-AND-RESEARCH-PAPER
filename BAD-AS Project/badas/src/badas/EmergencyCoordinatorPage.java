package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class EmergencyCoordinatorPage {
    private JFrame frame;
    private JTable emergencyTable;
    private DefaultTableModel tableModel;
    private final String FILE_PATH = "emergency_cases.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new EmergencyCoordinatorPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Emergency Coordinator - Emergency Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(900, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Emergency Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Emergency Cases
        String[] columnNames = {"Patient Name", "Location", "Symptoms", "Emergency Level", "Status"};
        tableModel = new DefaultTableModel(columnNames, 0);
        emergencyTable = new JTable(tableModel);
        loadEmergencyData();

        JScrollPane tableScrollPane = new JScrollPane(emergencyTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Button Panel for Actions
        JPanel buttonPanel = new JPanel();

        JButton assignResourcesButton = new JButton("Assign Resources");
        assignResourcesButton.addActionListener(this::assignResources);
        buttonPanel.add(assignResourcesButton);

        JButton closeCaseButton = new JButton("Close Case");
        closeCaseButton.addActionListener(this::closeCase);
        buttonPanel.add(closeCaseButton);

        JButton backButton = new JButton("Back to Login");
        backButton.addActionListener(e -> {
            frame.dispose();
            Login.main(new String[]{});
        });
        buttonPanel.add(backButton);

        JButton homeButton = new JButton("Home");
        homeButton.addActionListener(e -> {
            frame.dispose();
            new EmergencyCoordinatorPage().createAndShowGUI();
        });
        buttonPanel.add(homeButton);

        frame.add(buttonPanel, BorderLayout.SOUTH);

        frame.setVisible(true);
    }

    // Load emergency data from CSV file
    private void loadEmergencyData() {
        File file = new File(FILE_PATH);
        if (!file.exists()) {
            JOptionPane.showMessageDialog(frame, "Emergency cases file not found. Creating a new file.", "File Not Found", JOptionPane.WARNING_MESSAGE);
            createDefaultEmergencyFile();
        }

        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] data = line.split(",");
                tableModel.addRow(data);
            }
        } catch (IOException e) {
            e.printStackTrace();
            JOptionPane.showMessageDialog(frame, "Error loading emergency data.", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Create a default CSV file if it doesn't exist
    private void createDefaultEmergencyFile() {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(FILE_PATH))) {
            bw.write("Patient Name,Location,Symptoms,Emergency Level,Status");
            bw.newLine();
            bw.write("John Doe,123 Main St,Severe Chest Pain,Critical,Pending");
            bw.newLine();
            bw.write("Jane Smith,456 Elm St,Difficulty Breathing,Severe,Pending");
            bw.newLine();
            bw.write("Bob Johnson,789 Pine St,Fracture,Moderate,Pending");
            bw.newLine();
            bw.write("Alice Brown,321 Oak Ave,High Fever,Moderate,Pending");
            bw.newLine();
            bw.write("Charlie White,654 Maple Dr,Severe Headache,Severe,Pending");
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // Save emergency data to CSV file
    private void saveEmergencyData() {
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

    // Assign resources to an emergency case
    private void assignResources(ActionEvent e) {
        int selectedRow = emergencyTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.setValueAt("Resources Assigned", selectedRow, 4);
            saveEmergencyData();
            JOptionPane.showMessageDialog(frame, "Resources assigned successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select an emergency case to assign resources!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Close an emergency case
    private void closeCase(ActionEvent e) {
        int selectedRow = emergencyTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.setValueAt("Closed", selectedRow, 4);
            saveEmergencyData();
            JOptionPane.showMessageDialog(frame, "Emergency case closed successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select an emergency case to close!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
