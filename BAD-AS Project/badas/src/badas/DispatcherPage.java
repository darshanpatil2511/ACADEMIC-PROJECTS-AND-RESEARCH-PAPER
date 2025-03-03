package badas;

import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.io.*;
import java.util.Vector;

public class DispatcherPage {
    private JFrame frame;
    private JTable dispatchTable;
    private DefaultTableModel tableModel;
    private final String FILE_PATH = "dispatch_requests.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new DispatcherPage().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("Dispatcher - Ambulance Dispatch Management");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(800, 500);
        frame.setLayout(new BorderLayout());

        // Title Label
        JLabel titleLabel = new JLabel("Ambulance Dispatch Management", SwingConstants.CENTER);
        titleLabel.setFont(new Font("Arial", Font.BOLD, 24));
        frame.add(titleLabel, BorderLayout.NORTH);

        // Table for Dispatch Requests
        String[] columnNames = {"Patient Name", "Location", "Symptoms", "Status"};
        tableModel = new DefaultTableModel(columnNames, 0);
        dispatchTable = new JTable(tableModel);
        loadDispatchData();

        JScrollPane tableScrollPane = new JScrollPane(dispatchTable);
        frame.add(tableScrollPane, BorderLayout.CENTER);

        // Button Panel
        JPanel buttonPanel = new JPanel();

        JButton dispatchButton = new JButton("Dispatch Ambulance");
        dispatchButton.addActionListener(this::dispatchAmbulance);
        buttonPanel.add(dispatchButton);

        JButton cancelButton = new JButton("Cancel Dispatch");
        cancelButton.addActionListener(this::cancelDispatch);
        buttonPanel.add(cancelButton);

        JButton backButton = new JButton("Back to Login");
        backButton.addActionListener(e -> {
            frame.dispose();
            Login.main(new String[]{});
        });
        buttonPanel.add(backButton);

        JButton homeButton = new JButton("Home");
        homeButton.addActionListener(e -> {
            frame.dispose();
            new DispatcherPage().createAndShowGUI();
        });
        buttonPanel.add(homeButton);

        frame.add(buttonPanel, BorderLayout.SOUTH);

        frame.setVisible(true);
    }

    // Load dispatch data from CSV file
    private void loadDispatchData() {
        File file = new File(FILE_PATH);
        System.out.println("Looking for file at: " + file.getAbsolutePath());

        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            while ((line = br.readLine()) != null) {
                if (!line.trim().isEmpty()) {
                    String[] data = line.split(",");
                    tableModel.addRow(data);
                }
            }
        } catch (FileNotFoundException e) {
            System.out.println("File not found: " + file.getAbsolutePath());
            JOptionPane.showMessageDialog(frame, "Dispatch file not found!", "Error", JOptionPane.ERROR_MESSAGE);
        } catch (IOException e) {
            e.printStackTrace();
            JOptionPane.showMessageDialog(frame, "Error reading dispatch file!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Save dispatch data to CSV file
    private void saveDispatchData() {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(FILE_PATH))) {
            for (int i = 0; i < tableModel.getRowCount(); i++) {
                Vector<?> row = tableModel.getDataVector().elementAt(i);
                bw.write(String.join(",", row.toArray(new String[0])));
                bw.newLine();
            }
        } catch (IOException e) {
            e.printStackTrace();
            JOptionPane.showMessageDialog(frame, "Error saving dispatch data!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Dispatch an ambulance
    private void dispatchAmbulance(ActionEvent e) {
        int selectedRow = dispatchTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.setValueAt("Dispatched", selectedRow, 3);
            saveDispatchData();
            JOptionPane.showMessageDialog(frame, "Ambulance dispatched successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a dispatch request to proceed!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    // Cancel a dispatch
    private void cancelDispatch(ActionEvent e) {
        int selectedRow = dispatchTable.getSelectedRow();
        if (selectedRow != -1) {
            tableModel.setValueAt("Cancelled", selectedRow, 3);
            saveDispatchData();
            JOptionPane.showMessageDialog(frame, "Dispatch cancelled successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
        } else {
            JOptionPane.showMessageDialog(frame, "Please select a dispatch request to cancel!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
