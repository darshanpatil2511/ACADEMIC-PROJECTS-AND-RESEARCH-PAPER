package com.badas.service;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Generates dispatch reports and saves them to a reports/ folder
 * inside the project directory (user.dir). Cross-platform — no hardcoded paths.
 */
public class ReportService {

    private static final String REPORTS_DIR = System.getProperty("user.dir")
            + File.separator + "reports";
    private static final DateTimeFormatter FILE_FMT  = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss");
    private static final DateTimeFormatter PRINT_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /**
     * Generates a dispatch report file.
     * @return the absolute path of the file created, or null on error.
     */
    public String generateDispatchReport(String patientName, int patientAge, String contact,
                                         String location, String symptoms,
                                         String severity, String ambulanceType,
                                         String dispatchedBy) {
        File dir = new File(REPORTS_DIR);
        if (!dir.exists()) dir.mkdirs();

        String timestamp = LocalDateTime.now().format(FILE_FMT);
        String filename  = "dispatch_" + timestamp + ".txt";
        File   reportFile = new File(dir, filename);

        String now = LocalDateTime.now().format(PRINT_FMT);
        String separator = "=".repeat(60);

        String content = separator + "\n"
                + "        BADAS — DISPATCH REPORT\n"
                + separator + "\n"
                + "Generated     : " + now        + "\n"
                + "Dispatched By : " + dispatchedBy + "\n"
                + separator + "\n"
                + "PATIENT INFORMATION\n"
                + "-------------------\n"
                + "Name          : " + patientName  + "\n"
                + "Age           : " + patientAge   + "\n"
                + "Contact       : " + contact      + "\n"
                + "Location      : " + location     + "\n"
                + separator + "\n"
                + "CLINICAL ASSESSMENT\n"
                + "-------------------\n"
                + "Reported Symptoms : " + symptoms     + "\n"
                + "Severity Level    : " + severity     + "\n"
                + separator + "\n"
                + "DISPATCH DECISION\n"
                + "-----------------\n"
                + "Ambulance Type : " + ambulanceType + "\n"
                + "Status         : Dispatched\n"
                + separator + "\n";

        try (BufferedWriter bw = new BufferedWriter(
                new OutputStreamWriter(new FileOutputStream(reportFile), StandardCharsets.UTF_8))) {
            bw.write(content);
            return reportFile.getAbsolutePath();
        } catch (IOException e) {
            System.err.println("ReportService: Failed to write report — " + e.getMessage());
            return null;
        }
    }
}
