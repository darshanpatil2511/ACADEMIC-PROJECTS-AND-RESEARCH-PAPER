package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class ITSupportPage {
    private JFrame frame;
    private JTable userTable;
    private DefaultTableModel tableModel;
    private JTextField usernameField, passwordField, roleField;
    private final String FILE_PATH = "D:\\Netbeans Project\\badas\\src\\user_accounts.csv"; // File path for the uploaded CSV

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new ITSupportPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("IT Support - User Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(900, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("User Account Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for User Accounts
        String[] columnNames = {"Username", "Password", "Role"};
        tableModel = new DefaultTableModel(columnNames, 0);
        userTable = new JTable(tableModel);
        loadUserData(); // Load data from CSV into the table

        JScrollPane tableScrollPane = new JScrollPane(userTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Form Panel for Adding/Updating Users
        JPanel formPanel = new JPanel(new GridLayout(4, 2, 10, 10));
        formPanel.setBorder(BorderFactory.createEmptyBorder(10, 10, 10, 10));

        formPanel.add(new JLabel("Username:"));
        usernameField = new JTextField();
        formPanel.add(usernameField);

        formPanel.add(new JLabel("Password:"));
        passwordField = new JTextField();
        formPanel.add(passwordField);

        formPanel.add(new JLabel("Role:"));
        roleField = new JTextField();
        formPanel.add(roleField);

        JButton addButton = new JButton("Add User");
        addButton.addActionListener(this::addUser);
        formPanel.add(addButton);

        JButton updateButton = new JButton("Update User");
        updateButton.addActionListener(this::updateUser);
        formPanel.add(updateButton);

        frame.add(formPanel, BorderLayout.SOUTH);

        // Button Panel for Navigation and Deletion
        JPanel buttonPanel = new JPanel();

        JButton deleteButton = new JButton("Delete User");
        deleteButton.addActionListener(this::deleteUser);
        buttonPanel.add(deleteButton);

        JButton backButton = new JButton("Back to Login");
        backButton.addActionListener(e -> {
            frame.dispose();
            Login.main(new String[]{});  // Go back to the login screen
        });
        buttonPanel.add(backButton);

        frame.add(buttonPanel, BorderLayout.WEST);

        frame.setVisible(true);
    }

    // Load user data from CSV file
    private void loadUserData() {
        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] data = line.split(",");
                tableModel.addRow(data);
            }
        } catch (IOException e) {
            JOptionPane.showMessageDialog(frame, "Error loading user data: " + e.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Save user data to CSV file
    private void saveUserData() {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(FILE_PATH))) {
            for (int i = 0; i < tableModel.getRowCount(); i++) {
                Vector<?> row = tableModel.getDataVector().elementAt(i);
                bw.write(String.join(",", row.toArray(new String[0])));
                bw.newLine();
            }
        } catch (IOException e) {
            JOptionPane.showMessageDialog(frame, "Error saving user data: " + e.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Add a new user
    private void addUser(ActionEvent e) {
        String username = usernameField.getText().trim();
        String password = passwordField.getText().trim();
        String role = roleField.getText().trim();

        if (!username.isEmpty() && !password.isEmpty() && !role.isEmpty()) {
            tableModel.addRow(new String[]{username, password, role});
            saveUserData();
            clearFields();
            JOptionPane.showMessageDialog(frame, "User added successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Update an existing user
    private void updateUser(ActionEvent e) {
        int selectedRow = userTable.getSelectedRow();
        if (selectedRow != -1) {
            String username = usernameField.getText().trim();
            String password = passwordField.getText().trim();
            String role = roleField.getText().trim();

            if (!username.isEmpty() && !password.isEmpty() && !role.isEmpty()) {
                tableModel.setValueAt(username, selectedRow, 0);
                tableModel.setValueAt(password, selectedRow, 1);
                tableModel.setValueAt(role, selectedRow, 2);
                saveUserData();
                clearFields();
                JOptionPane.showMessageDialog(frame, "User updated successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
            } else {
                JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
            }
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a user to update!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Delete a user
    private void deleteUser(ActionEvent e) {
        int selectedRow = userTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.removeRow(selectedRow);
            saveUserData();
            JOptionPane.showMessageDialog(frame, "User deleted successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a user to delete!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Clear input fields
    private void clearFields() {
        usernameField.setText("");
        passwordField.setText("");
        roleField.setText("");
    }
}
