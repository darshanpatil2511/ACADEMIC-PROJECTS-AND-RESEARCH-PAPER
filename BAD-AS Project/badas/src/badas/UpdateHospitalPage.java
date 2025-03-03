package badas;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ActionEvent;

public class UpdateHospitalPage {
    private JFrame frame;
    private JTextField nameField, locationField, ambulanceField;
    private int selectedRow;
    private AdminPage adminPage;

    public UpdateHospitalPage(String name, String location, String ambulances, int selectedRow, AdminPage adminPage) {
        this.selectedRow = selectedRow;
        this.adminPage = adminPage;

        nameField = new JTextField(name);
        locationField = new JTextField(location);
        ambulanceField = new JTextField(ambulances);
    }

    public void createAndShowGUI() {
        frame = new JFrame("Update Hospital Details");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(400, 250);
        frame.setLayout(new GridLayout(4, 2, 10, 10));

        frame.add(new JLabel("Hospital Name:"));
        frame.add(nameField);

        frame.add(new JLabel("Location:"));
        frame.add(locationField);

        frame.add(new JLabel("Number of Ambulances:"));
        frame.add(ambulanceField);

        JButton updateButton = new JButton("Update");
        updateButton.addActionListener(this::updateHospital);
        frame.add(updateButton);

        JButton cancelButton = new JButton("Cancel");
        cancelButton.addActionListener(e -> {
            frame.dispose();
            adminPage.createAndShowGUI();
        });
        frame.add(cancelButton);

        frame.setVisible(true);
    }

    private void updateHospital(ActionEvent e) {
        String newName = nameField.getText().trim();
        String newLocation = locationField.getText().trim();
        String newAmbulances = ambulanceField.getText().trim();

        if (!newName.isEmpty() && !newLocation.isEmpty() && !newAmbulances.isEmpty()) {
            adminPage.getTableModel().setValueAt(newName, selectedRow, 0);
adminPage.getTableModel().setValueAt(newLocation, selectedRow, 1);
adminPage.getTableModel().setValueAt(newAmbulances, selectedRow, 2);
adminPage.saveHospitalData();

            JOptionPane.showMessageDialog(frame, "Hospital updated successfully!", "Success", JOptionPane.INFORMATION_MESSAGE);
            frame.dispose();
            adminPage.createAndShowGUI();
        } else {
            JOptionPane.showMessageDialog(frame, "All fields are required!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
