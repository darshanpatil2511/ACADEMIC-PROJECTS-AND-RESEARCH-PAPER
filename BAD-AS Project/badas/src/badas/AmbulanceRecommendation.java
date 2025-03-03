package badas;

import javax.swing.*;
import java.awt.*;
import java.io.FileWriter;
import java.io.IOException;

/**
 * Ambulance Recommendation Module.
 * Provides final recommendations based on patient details and symptom analysis.
 */
public class AmbulanceRecommendation {
    public static void start(String name, int age, String contact, String symptoms, String analysisResult) {
        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("Ambulance Recommendation");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setSize(600, 400);
            frame.add(new AmbulanceRecommendationPanel(frame, name, age, contact, symptoms, analysisResult));
            frame.setVisible(true);
        });
    }
}

class AmbulanceRecommendationPanel extends JPanel {
    private final JLabel recommendationLabel;
    private final String patientName;
    private final int patientAge;
    private final String patientContact;
    private final String patientSymptoms;
    private final String analysisResult;
    private final JFrame parentFrame;

    public AmbulanceRecommendationPanel(JFrame parentFrame, String name, int age, String contact, String symptoms, String analysisResult) {
        this.parentFrame = parentFrame;
        this.patientName = name;
        this.patientAge = age;
        this.patientContact = contact;
        this.patientSymptoms = symptoms;
        this.analysisResult = analysisResult;
        this.setLayout(new BorderLayout());

        // Header Panel
        JPanel headerPanel = new JPanel();
        headerPanel.setBackground(new Color(51, 153, 255));
        JLabel headerLabel = new JLabel("Final Ambulance Recommendation for " + name, SwingConstants.CENTER);
        headerLabel.setFont(new Font("Arial", Font.BOLD, 16));
        headerLabel.setForeground(Color.WHITE);
        headerPanel.add(headerLabel);
        this.add(headerPanel, BorderLayout.NORTH);

        // Analysis Result Panel
        JPanel analysisPanel = new JPanel(new BorderLayout());
        analysisPanel.setBorder(BorderFactory.createTitledBorder("Symptom Analysis Result"));
        JLabel analysisLabel = new JLabel("<html>" + analysisResult.replace("\\n", "<br>") + "</html>");
        analysisPanel.add(analysisLabel, BorderLayout.CENTER);
        this.add(analysisPanel, BorderLayout.CENTER);

        // Recommendation Panel
        JPanel recommendationPanel = new JPanel(new BorderLayout());
        recommendationPanel.setBorder(BorderFactory.createTitledBorder("Ambulance Recommendation"));
        recommendationLabel = new JLabel("Generating recommendation...", SwingConstants.CENTER);
        recommendationLabel.setFont(new Font("Arial", Font.BOLD, 14));
        recommendationPanel.add(recommendationLabel, BorderLayout.CENTER);
        this.add(recommendationPanel, BorderLayout.SOUTH);

        // Generate recommendation on initialization
        generateRecommendation();
    }

    private void generateRecommendation() {
        // Determine ambulance recommendation based on age and severity
        String recommendation;
        if (patientAge < 10 || patientAge > 50) {
            if (analysisResult.contains("Critical Condition")) {
                recommendation = "Advanced Life Support Ambulance";
            } else if (analysisResult.contains("Moderate Condition")) {
                recommendation = "Basic Life Support Ambulance";
            } else {
                recommendation = "Cab Service is sufficient";
            }
        } else {
            if (analysisResult.contains("Critical Condition")) {
                recommendation = "Basic Life Support Ambulance";
            } else if (analysisResult.contains("Moderate Condition")) {
                recommendation = "Cab Service is sufficient";
            } else {
                recommendation = "No immediate action required";
            }
        }

        // Update the label
        recommendationLabel.setText("<html>Final Recommendation: " + recommendation + "</html>");

        // Generate a report
        try {
            generateReport(recommendation);
        } catch (IOException e) {
            recommendationLabel.setText("<html>Error generating report: " + e.getMessage() + "</html>");
        }
    }

    private void generateReport(String recommendation) throws IOException {
        String report = "Dispatch Report:\\n"
                + "Patient Name: " + patientName + "\\n"
                + "Age: " + patientAge + "\\n"
                + "Contact: " + patientContact + "\\n"
                + "Symptoms: " + patientSymptoms + "\\n"
                + "Analysis Result: " + analysisResult + "\\n"
                + "Final Recommendation: " + recommendation + "\\n";

        String filePath = "D:/Netbeans Project/badas/dispatch_report.txt";
        try (FileWriter writer = new FileWriter(filePath)) {
            writer.write(report);
        }

        JOptionPane.showMessageDialog(parentFrame,
                "<html>Report generated successfully at:<br>" + filePath + "</html>",
                "Report Generated", JOptionPane.INFORMATION_MESSAGE);
    }
}
