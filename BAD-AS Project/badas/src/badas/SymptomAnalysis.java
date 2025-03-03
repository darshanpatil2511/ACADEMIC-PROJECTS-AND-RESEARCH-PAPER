
package badas;

import javax.swing.*;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.util.Arrays;
import java.util.HashSet;

/**
 * Symptom Analysis Module.
 * Analyzes symptoms and determines severity based on predefined keywords.
 */
public class SymptomAnalysis {
    public static void start(String name, int age, String contact) {
        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("Symptom Analysis");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setSize(600, 400);
            frame.add(new SymptomAnalysisPanel(frame, name, age, contact));
            frame.setVisible(true);
        });
    }
}

class SymptomAnalysisPanel extends JPanel {
    private final JTextArea symptomTextArea;
    private final JLabel resultLabel;
    private final String patientName;
    private final int patientAge;
    private final String patientContact;
    private final JFrame parentFrame;

    public SymptomAnalysisPanel(JFrame parentFrame, String name, int age, String contact) {
        this.parentFrame = parentFrame;
        this.patientName = name;
        this.patientAge = age;
        this.patientContact = contact;
        this.setLayout(new BorderLayout());

        // Header Panel
        JPanel headerPanel = new JPanel();
        headerPanel.setBackground(new Color(51, 153, 255));
        JLabel headerLabel = new JLabel("Symptom Analysis for " + name, SwingConstants.CENTER);
        headerLabel.setFont(new Font("Arial", Font.BOLD, 16));
        headerLabel.setForeground(Color.WHITE);
        headerPanel.add(headerLabel);
        this.add(headerPanel, BorderLayout.NORTH);

        // Input Panel
        JPanel inputPanel = new JPanel(new BorderLayout());
        inputPanel.setBorder(BorderFactory.createTitledBorder("Describe Symptoms"));

        symptomTextArea = new JTextArea(10, 40);
        symptomTextArea.setLineWrap(true);
        symptomTextArea.setWrapStyleWord(true);
        inputPanel.add(new JScrollPane(symptomTextArea), BorderLayout.CENTER);
        this.add(inputPanel, BorderLayout.CENTER);

        // Result Panel
        JPanel resultPanel = new JPanel();
        resultPanel.setBorder(BorderFactory.createTitledBorder("Analysis Result"));
        resultLabel = new JLabel("Enter symptoms and click Analyze.", SwingConstants.CENTER);
        resultLabel.setFont(new Font("Arial", Font.BOLD, 14));
        resultPanel.add(resultLabel);
        this.add(resultPanel, BorderLayout.SOUTH);

        // Button Panel
        JPanel buttonPanel = new JPanel();
        JButton analyzeButton = new JButton("Analyze");
        analyzeButton.setBackground(new Color(0, 153, 76));
        analyzeButton.setForeground(Color.WHITE);
        analyzeButton.setFont(new Font("Arial", Font.BOLD, 14));
        analyzeButton.addActionListener(this::handleAnalyze);
        buttonPanel.add(analyzeButton);

        JButton nextButton = new JButton("Next");
        nextButton.setBackground(new Color(0, 102, 204));
        nextButton.setForeground(Color.WHITE);
        nextButton.setFont(new Font("Arial", Font.BOLD, 14));
        nextButton.addActionListener(this::handleNext);
        buttonPanel.add(nextButton);

        this.add(buttonPanel, BorderLayout.SOUTH);
    }

    private void handleAnalyze(ActionEvent e) {
        String symptoms = symptomTextArea.getText().trim();

        if (symptoms.isEmpty()) {
            resultLabel.setText("Please describe symptoms before analyzing.");
            return;
        }

        // Analyze symptoms
        String analysisResult = analyzeSymptoms(symptoms);
        resultLabel.setText("<html>" + analysisResult.replace("\n", "<br>") + "</html>");
    }

    private void handleNext(ActionEvent e) {
        String symptoms = symptomTextArea.getText().trim();

        if (symptoms.isEmpty()) {
            JOptionPane.showMessageDialog(parentFrame, "Please analyze symptoms before proceeding.", "Error", JOptionPane.ERROR_MESSAGE);
            return;
        }

        String analysisResult = analyzeSymptoms(symptoms);
        parentFrame.dispose();
        AmbulanceRecommendation.start(patientName, patientAge, patientContact, symptoms, analysisResult);
    }

    private String analyzeSymptoms(String symptoms) {
        // Keywords indicating severity
        HashSet<String> criticalKeywords = new HashSet<>(Arrays.asList(
            "chest pain", "shortness of breath", "severe headache", "confusion", "bleeding"
        ));
        HashSet<String> moderateKeywords = new HashSet<>(Arrays.asList(
            "fever", "dizziness", "nausea", "weakness", "rapid heartbeat"
        ));
        HashSet<String> minorKeywords = new HashSet<>(Arrays.asList(
            "cough", "mild fever", "sore throat", "body ache", "fatigue"
        ));

        int criticalCount = 0, moderateCount = 0, minorCount = 0;
        for (String word : symptoms.toLowerCase().split("\s+")) {
            if (criticalKeywords.contains(word)) {
                criticalCount++;
            } else if (moderateKeywords.contains(word)) {
                moderateCount++;
            } else if (minorKeywords.contains(word)) {
                minorCount++;
            }
        }

        // Determine severity
        if (criticalCount > 0) {
            return "Critical Condition\nSeverity: High\nRecommendation: Advanced Life Support Ambulance";
        } else if (moderateCount > 0) {
            return "Moderate Condition\nSeverity: Medium\nRecommendation: Basic Life Support Ambulance";
        } else if (minorCount > 0) {
            return "Minor Condition\nSeverity: Low\nRecommendation: Cab Service or No Immediate Action";
        } else {
            return "No specific condition detected.\nRecommendation: Further evaluation required.";
        }
    }
}
