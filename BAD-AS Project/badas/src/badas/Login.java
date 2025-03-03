package badas;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.io.*;
import java.util.HashMap;
import java.util.Map;

public class Login {
    private JFrame frame;
    private JTextField userField;
    private JPasswordField passField;
    private JButton loginButton, exitButton, darkModeButton;
    private JCheckBox rememberMeCheckBox;
    private JLabel forgotPasswordLabel;
    private boolean isDarkMode = false;

    private Map<String, String> users = new HashMap<>();
    private Map<String, String> roles = new HashMap<>();
    private final String FILE_PATH = "user_accounts.csv";

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new Login().createAndShowGUI());
    }

    public void createAndShowGUI() {
        frame = new JFrame("BADAS Login");
        frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        frame.setSize(500, 600);
        frame.setLocationRelativeTo(null);
        frame.getContentPane().setBackground(new Color(245, 245, 245));
        frame.setLayout(new GridBagLayout());

        GridBagConstraints gbc = new GridBagConstraints();
        gbc.insets = new Insets(15, 15, 15, 15);
        gbc.fill = GridBagConstraints.HORIZONTAL;

        // Title Label
        JLabel titleLabel = new JLabel("Welcome to BADAS");
        titleLabel.setFont(new Font("Arial", Font.BOLD, 32));
        titleLabel.setForeground(Color.DARK_GRAY);
        titleLabel.setHorizontalAlignment(SwingConstants.CENTER);
        gbc.gridwidth = 2;
        gbc.gridx = 0;
        gbc.gridy = 0;
        frame.add(titleLabel, gbc);

        // Username Label
        gbc.gridwidth = 1;
        gbc.gridx = 0;
        gbc.gridy = 1;
        JLabel userLabel = new JLabel("Username:");
        userLabel.setFont(new Font("Arial", Font.PLAIN, 18));
        frame.add(userLabel, gbc);

        // Username Field
        gbc.gridx = 1;
        userField = createRoundedTextField();
        frame.add(userField, gbc);

        // Password Label
        gbc.gridx = 0;
        gbc.gridy = 2;
        JLabel passLabel = new JLabel("Password:");
        passLabel.setFont(new Font("Arial", Font.PLAIN, 18));
        frame.add(passLabel, gbc);

        // Password Field
        gbc.gridx = 1;
        passField = createRoundedPasswordField();
        frame.add(passField, gbc);

        // Remember Me Checkbox
        gbc.gridx = 1;
        gbc.gridy = 3;
        rememberMeCheckBox = new JCheckBox("Remember Me");
        rememberMeCheckBox.setFont(new Font("Arial", Font.PLAIN, 14));
        rememberMeCheckBox.setBackground(new Color(245, 245, 245));
        frame.add(rememberMeCheckBox, gbc);

        // Forgot Password Label
        gbc.gridx = 1;
        gbc.gridy = 4;
        forgotPasswordLabel = createHyperlinkLabel("Forgot Password?");
        frame.add(forgotPasswordLabel, gbc);

        // Login Button
        gbc.gridx = 0;
        gbc.gridy = 5;
        loginButton = createStyledButton("Login");
        loginButton.addActionListener(this::login);
        frame.add(loginButton, gbc);

        // Exit Button
        gbc.gridx = 1;
        exitButton = createStyledButton("Exit");
        exitButton.addActionListener(e -> System.exit(0));
        frame.add(exitButton, gbc);

        // Dark Mode Button
        gbc.gridx = 0;
        gbc.gridy = 6;
        gbc.gridwidth = 2;
        darkModeButton = createStyledButton("Enable Dark Mode");
        darkModeButton.addActionListener(this::toggleDarkMode);
        frame.add(darkModeButton, gbc);

        loadUserAccounts();
        frame.setVisible(true);
    }

    private JTextField createRoundedTextField() {
        JTextField textField = new JTextField(20);
        textField.setFont(new Font("Arial", Font.PLAIN, 18));
        textField.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(new Color(200, 200, 200), 1),
                new EmptyBorder(10, 10, 10, 10)
        ));
        return textField;
    }

    private JPasswordField createRoundedPasswordField() {
        JPasswordField passwordField = new JPasswordField(20);
        passwordField.setFont(new Font("Arial", Font.PLAIN, 18));
        passwordField.setBorder(BorderFactory.createCompoundBorder(
                BorderFactory.createLineBorder(new Color(200, 200, 200), 1),
                new EmptyBorder(10, 10, 10, 10)
        ));
        return passwordField;
    }

    private JButton createStyledButton(String text) {
        JButton button = new JButton(text);
        button.setFont(new Font("Arial", Font.BOLD, 18));
        button.setBackground(new Color(0, 122, 255));
        button.setForeground(Color.WHITE);
        button.setFocusPainted(false);
        button.setBorder(BorderFactory.createEmptyBorder(10, 20, 10, 20));
        button.setCursor(new Cursor(Cursor.HAND_CURSOR));
        return button;
    }

    private JLabel createHyperlinkLabel(String text) {
        JLabel hyperlinkLabel = new JLabel("<html><a href='#'>" + text + "</a></html>");
        hyperlinkLabel.setFont(new Font("Arial", Font.PLAIN, 14));
        hyperlinkLabel.setForeground(new Color(0, 122, 255));
        hyperlinkLabel.setCursor(new Cursor(Cursor.HAND_CURSOR));
        hyperlinkLabel.addMouseListener(new MouseAdapter() {
            @Override
            public void mouseClicked(MouseEvent e) {
                JOptionPane.showMessageDialog(frame, "Password recovery is not implemented yet.", "Forgot Password", JOptionPane.INFORMATION_MESSAGE);
            }
        });
        return hyperlinkLabel;
    }

    private void toggleDarkMode(ActionEvent e) {
        isDarkMode = !isDarkMode;
        Color bgColor = isDarkMode ? Color.DARK_GRAY : new Color(245, 245, 245);
        frame.getContentPane().setBackground(bgColor);
        rememberMeCheckBox.setBackground(bgColor);
        darkModeButton.setText(isDarkMode ? "Disable Dark Mode" : "Enable Dark Mode");
        frame.repaint();
    }

    private void loadUserAccounts() {
        try (BufferedReader br = new BufferedReader(new FileReader(FILE_PATH))) {
            String line;
            br.readLine();
            while ((line = br.readLine()) != null) {
                String[] data = line.split(",");
                if (data.length == 3) {
                    users.put(data[0], data[1]);
                    roles.put(data[0], data[2]);
                }
            }
        } catch (IOException e) {
            JOptionPane.showMessageDialog(frame, "Error loading user accounts!", "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void login(ActionEvent e) {
        String username = userField.getText().trim();
        String password = new String(passField.getPassword()).trim();
    
        if (users.containsKey(username) && users.get(username).equals(password)) {
            String role = roles.get(username);
            JOptionPane.showMessageDialog(frame, "Login successful!", "Success", JOptionPane.INFORMATION_MESSAGE);
            frame.dispose(); // Close the login window
    
            switch (role.toLowerCase()) {
                case "admin":
                    AdminPage.main(new String[]{});
                    break;
                case "dispatcher":
                    PatientInfo.main(new String[]{});
                    break;
                case "doctor":
                    DoctorPage.main(new String[]{});
                    break;
                    case "nurse":
                    NursePage.main(new String[]{});
                    break;
                    case "receptionist":
                    ReceptionistPage.main(new String[]{});
                    break;
                    case "itsupport":
                    ITSupportPage.main(new String[]{});
                    break;               
                case "emergency coordinator":
                    EmergencyCoordinatorPage.main(new String[]{});
                    break;
                default:
                    JOptionPane.showMessageDialog(null, "Role not recognized!", "Error", JOptionPane.ERROR_MESSAGE);
            }
        } else {
            JOptionPane.showMessageDialog(frame, "Invalid username or password!", "Login Failed", JOptionPane.ERROR_MESSAGE);
        }
    }}

    