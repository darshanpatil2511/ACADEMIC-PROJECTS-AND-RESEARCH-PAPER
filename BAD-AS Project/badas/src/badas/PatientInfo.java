
package badas;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

/**
 * Patient Information Module.
 * Collects basic patient details and passes data to the next step.
 */
public class PatientInfo {
    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("Patient Information");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setSize(400, 300);
            frame.add(new PatientInfoPanel(frame));
            frame.setVisible(true);
        });
    }
}

class PatientInfoPanel extends JPanel {
    private final JTextField nameField;
    private final JTextField ageField;
    private final JTextField contactField;
    private final JFrame parentFrame;

    public PatientInfoPanel(JFrame parentFrame) {
        this.parentFrame = parentFrame;
        this.setLayout(new GridLayout(4, 2, 10, 10));
        this.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));

        JLabel nameLabel = new JLabel("Name:");
        nameField = new JTextField(20);

        JLabel ageLabel = new JLabel("Age:");
        ageField = new JTextField(20);

        JLabel contactLabel = new JLabel("Contact Number:");
        contactField = new JTextField(20);

        JButton nextButton = new JButton("Next");
        nextButton.addActionListener(this::handleNext);

        this.add(nameLabel);
        this.add(nameField);
        this.add(ageLabel);
        this.add(ageField);
        this.add(contactLabel);
        this.add(contactField);
        this.add(new JLabel()); // Empty space
        this.add(nextButton);
    }

    private void handleNext(ActionEvent e) {
        String name = nameField.getText().trim();
        String ageText = ageField.getText().trim();
        String contact = contactField.getText().trim();

        if (name.isEmpty() || ageText.isEmpty() || contact.isEmpty()) {
            JOptionPane.showMessageDialog(parentFrame, "Please fill out all fields.", "Error", JOptionPane.ERROR_MESSAGE);
            return;
        }

        try {
            int age = Integer.parseInt(ageText); // Validate age as a number
            parentFrame.dispose();
            SymptomAnalysis.start(name, age, contact); // Pass data to the next step
        } catch (NumberFormatException ex) {
            JOptionPane.showMessageDialog(parentFrame, "Age must be a valid number.", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }
}
