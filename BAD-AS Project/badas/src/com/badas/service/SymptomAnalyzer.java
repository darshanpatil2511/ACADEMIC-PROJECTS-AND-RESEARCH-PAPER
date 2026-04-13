package com.badas.service;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Stateless service for keyword-based symptom severity analysis.
 * Severity levels: CRITICAL, MODERATE, MINOR, UNKNOWN.
 */
public class SymptomAnalyzer {

    public enum Severity { CRITICAL, MODERATE, MINOR, UNKNOWN }

    private static final Set<String> CRITICAL_KEYWORDS = new HashSet<>(Arrays.asList(
        "chest pain", "shortness of breath", "stroke", "unconscious", "unresponsive",
        "severe bleeding", "bleeding", "heart attack", "cardiac arrest", "seizure",
        "severe headache", "loss of consciousness", "difficulty breathing", "confusion"
    ));

    private static final Set<String> MODERATE_KEYWORDS = new HashSet<>(Arrays.asList(
        "fever", "dizziness", "nausea", "vomiting", "weakness", "rapid heartbeat",
        "fracture", "broken bone", "abdominal pain", "high fever", "allergic reaction",
        "head injury", "back pain", "difficulty walking"
    ));

    private static final Set<String> MINOR_KEYWORDS = new HashSet<>(Arrays.asList(
        "cough", "mild fever", "sore throat", "body ache", "fatigue", "cold",
        "runny nose", "mild headache", "mild pain", "sprain", "bruise", "rash"
    ));

    /**
     * Analyzes a free-text symptom description and returns the determined severity.
     */
    public Severity analyze(String symptomText) {
        if (symptomText == null || symptomText.isBlank()) return Severity.UNKNOWN;
        String lower = symptomText.toLowerCase();

        // Check multi-word keywords first (exact phrase matching)
        for (String kw : CRITICAL_KEYWORDS) {
            if (lower.contains(kw)) return Severity.CRITICAL;
        }
        for (String kw : MODERATE_KEYWORDS) {
            if (lower.contains(kw)) return Severity.MODERATE;
        }
        for (String kw : MINOR_KEYWORDS) {
            if (lower.contains(kw)) return Severity.MINOR;
        }

        return Severity.UNKNOWN;
    }

    /**
     * Returns the recommended ambulance type based on severity and patient age.
     */
    public String recommendAmbulance(Severity severity, int age) {
        boolean highRiskAge = age < 10 || age > 60;

        return switch (severity) {
            case CRITICAL -> "Advanced Life Support (ALS) Ambulance";
            case MODERATE -> highRiskAge
                    ? "Advanced Life Support (ALS) Ambulance"
                    : "Basic Life Support (BLS) Ambulance";
            case MINOR    -> highRiskAge
                    ? "Basic Life Support (BLS) Ambulance"
                    : "Non-Emergency Medical Transport";
            case UNKNOWN  -> "Clinical evaluation required before dispatch";
        };
    }

    /**
     * Returns a human-readable label for the severity level.
     */
    public String severityLabel(Severity severity) {
        return switch (severity) {
            case CRITICAL -> "Critical";
            case MODERATE -> "Moderate";
            case MINOR    -> "Minor";
            case UNKNOWN  -> "Undetermined";
        };
    }

    /**
     * Returns a detailed analysis summary string for display in the UI.
     */
    public String buildSummary(Severity severity, int age, String ambulanceType) {
        return "Severity Level : " + severityLabel(severity) + "\n"
             + "Patient Age    : " + age + " years\n"
             + "Recommendation : " + ambulanceType;
    }
}
