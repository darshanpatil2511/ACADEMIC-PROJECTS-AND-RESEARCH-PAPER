package badas;
import badas.Login;
import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class AdminPage {
    private JFrame frame;
    private JTable hospitalTable;
    private DefaultTableModel tableModel;
    private JTextField nameField, locationField, ambulanceField;
    private final String FILE_PATH = "hospitals.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new AdminPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Admin - Hospital Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(800, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Hospital Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Hospitals
        String[] columnNames = {"Hospital Name", "Location", "Number of Ambulances"};
        tableModel = new DefaultTableModel(columnNames, 0);
        hospitalTable = new JTable(tableModel);
        loadHospitalData();

        JScrollPane tableScrollPane = new JScrollPane(hospitalTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Form Panel for Adding Hospitals
        JPanel formPanel = new JPanel(new GridLayout(4, 2, 10, 10));
        formPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        formPanel.add(new JLabel("Hospital Name:"));
        nameField = new JTextField();
        formPanel.add(nameField);

        formPanel.add(new JLabel("Location:"));
        locationField = new JTextField();
        formPanel.add(locationField);

        formPanel.add(new JLabel("Number of Ambulances:"));
        ambulanceField = new JTextField();
        formPanel.add(ambulanceField);

        JButton addButton = new JButton("Add Hospital");
        addButton.addActionListener(this::addHospital);
        formPanel.add(addButton);

        JButton updateButton = new JButton("Update Hospital");
        updateButton.addActionListener(e -> openUpdateHospitalPage());
        formPanel.add(updateButton);

        frame.add(formPanel, BorderLayout.SOUTH);

        // Button Panel for Navigation and Deletion
        JPanel buttonPanel = new JPanel();

        JButton deleteButton = new JButton("Delete Hospital");
        deleteButton.addActionListener(this::deleteHospital);
        buttonPanel.add(deleteButton);

        JButton backButton = new JButton("Back to Login");
        backButton.addActionListener(e -> {
            frame.dispose();
            Login.main(new String[]{});
        });
        buttonPanel.add(backButton);

        frame.add(buttonPanel, BorderLayout.NORTH);

        frame.setVisible(true);
    }

    private void loadHospitalData() {
        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] data = line.split(",");
                tableModel.addRow(data);
            }
        } catch (IOException e) {
            System.out.println("No existing data found. Starting with an empty list.");
        }
    }

    public void saveHospitalData() {
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
    
    public DefaultTableModel getTableModel() {
        return tableModel;
    }
    
    private void addHospital(ActionEvent e) {
        String name = nameField.getText().trim();
        String location = locationField.getText().trim();
        String ambulances = ambulanceField.getText().trim();

        if (!name.isEmpty() && !location.isEmpty() && !ambulances.isEmpty()) {
            tableModel.addRow(new String[]{name, location, ambulances});
            saveHospitalData();
            clearFields();
            JOptionPane.showMessageDialog(frame, "Hospital added successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void deleteHospital(ActionEvent e) {
        int selectedRow = hospitalTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.removeRow(selectedRow);
            saveHospitalData();
            JOptionPane.showMessageDialog(frame, "Hospital deleted successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a hospital to delete!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void openUpdateHospitalPage() {
        int selectedRow = hospitalTable.getSelectedRow();
        if (selectedRow != -1) {
            String name = (String) tableModel.getValueAt(selectedRow, 0);
            String location = (String) tableModel.getValueAt(selectedRow, 1);
            String ambulances = (String) tableModel.getValueAt(selectedRow, 2);
            new UpdateHospitalPage(name, location, ambulances, selectedRow, this).createAndShowGUI();
            frame.dispose();
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a hospital to update!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void clearFields() {
        nameField.setText("");
        locationField.setText("");
        ambulanceField.setText("");
    }

    public void refreshTable() {
        tableModel.setRowCount(0);
        loadHospitalData();
    }
}
