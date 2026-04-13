package com.badas.ui.common;

import com.badas.model.User;
import com.badas.service.AuthService;
import com.badas.ui.auth.LoginFrame;

import javax.swing.*;
import javax.swing.border.EmptyBorder;
import java.awt.*;
import java.awt.event.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Shared frame layout for all role-based dashboards.
 *
 * Layout:
 *   ┌─────────────────────────────────────────┐
 *   │  HEADER  (logo + user info + theme btn) │
 *   ├──────────┬──────────────────────────────┤
 *   │ SIDEBAR  │  CONTENT AREA                │
 *   │ (nav)    │  (filled by subclass)         │
 *   ├──────────┴──────────────────────────────┤
 *   │  STATUS BAR                             │
 *   └─────────────────────────────────────────┘
 *
 * Subclasses implement:
 *   - getSidebarItems()       — nav item labels
 *   - getDefaultItem()        — which item is selected on open
 *   - showPanel(String item)  — swap content for the chosen nav item
 */
public abstract class BaseFrame extends JFrame {

    protected final User currentUser;
    protected JPanel contentWrapper;
    private   JLabel statusLabel;
    private   JLabel clockLabel;
    private   JPanel sidebarPanel;
    private   String selectedItem;
    private   JToggleButton themeToggle;

    private static final DateTimeFormatter CLOCK_FMT =
            DateTimeFormatter.ofPattern("HH:mm:ss  dd MMM yyyy");

    protected BaseFrame(String pageTitle) {
        this.currentUser = AuthService.getInstance().getCurrentUser();
        setTitle("BADAS \u2014 " + pageTitle);
        setDefaultCloseOperation(EXIT_ON_CLOSE);
        setSize(1200, 720);
        setMinimumSize(new Dimension(960, 640));
        setLocationRelativeTo(null);
        buildLayout();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Abstract API for subclasses
    // ─────────────────────────────────────────────────────────────────────────

    protected abstract String[] getSidebarItems();

    protected abstract String getDefaultItem();

    /** Subclass swaps the content of contentWrapper here. */
    protected abstract void showPanel(String navItem);

    // ─────────────────────────────────────────────────────────────────────────
    //  Layout assembly
    // ─────────────────────────────────────────────────────────────────────────

    private void buildLayout() {
        setLayout(new BorderLayout());
        add(buildHeader(),    BorderLayout.NORTH);
        add(buildCenter(),    BorderLayout.CENTER);
        add(buildStatusBar(), BorderLayout.SOUTH);

        // Defer showPanel() until after the subclass constructor finishes initializing its fields
        selectedItem = getDefaultItem();
        refreshSidebarHighlight();
        SwingUtilities.invokeLater(() -> {
            showPanel(selectedItem);
            refreshSidebarHighlight();
        });
    }

    // ─── Header ──────────────────────────────────────────────────────────────

    private JPanel buildHeader() {
        JPanel header = new JPanel(new BorderLayout());
        header.setPreferredSize(new Dimension(0, UIConstants.HEADER_HEIGHT));
        header.setBackground(UIConstants.HEADER_BG);
        header.setBorder(new EmptyBorder(0, UIConstants.GAP_LG, 0, UIConstants.GAP_LG));

        // Left: logo + name
        JPanel left = new JPanel(new FlowLayout(FlowLayout.LEFT, UIConstants.GAP_SM, 0));
        left.setOpaque(false);

        JLabel cross = new JLabel("\u2665");               // heart / medical symbol
        cross.setFont(new Font("Segoe UI", Font.BOLD, 22));
        cross.setForeground(new Color(255, 100, 100));

        JLabel appName = new JLabel("  BADAS");
        appName.setFont(UIConstants.FONT_APP_TITLE);
        appName.setForeground(UIConstants.HEADER_TEXT);

        JLabel tagline = new JLabel("  Boston Aid & Dispatch System");
        tagline.setFont(UIConstants.FONT_SMALL);
        tagline.setForeground(new Color(187, 222, 251));

        left.add(cross);
        left.add(appName);
        left.add(tagline);
        header.add(left, BorderLayout.WEST);

        // Right: role badge + username + theme toggle
        JPanel right = new JPanel(new FlowLayout(FlowLayout.RIGHT, UIConstants.GAP_MD, 0));
        right.setOpaque(false);

        if (currentUser != null) {
            JLabel roleBadge = createRoleBadge(currentUser.getRole());
            right.add(roleBadge);

            JLabel username = new JLabel(currentUser.getUsername());
            username.setFont(UIConstants.FONT_BODY_BOLD);
            username.setForeground(UIConstants.HEADER_TEXT);
            right.add(username);
        }

        // Theme toggle button
        themeToggle = new JToggleButton(ThemeManager.isDark() ? "\u2600" : "\u263D");
        themeToggle.setFont(new Font("Segoe UI", Font.PLAIN, 16));
        themeToggle.setFocusPainted(false);
        themeToggle.setBorderPainted(false);
        themeToggle.setContentAreaFilled(false);
        themeToggle.setForeground(Color.WHITE);
        themeToggle.setSelected(ThemeManager.isDark());
        themeToggle.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        themeToggle.setToolTipText("Toggle dark/light mode");
        themeToggle.addActionListener(e -> {
            ThemeManager.toggleTheme();
            themeToggle.setText(ThemeManager.isDark() ? "\u2600" : "\u263D");
            refreshSidebarColors();
        });
        right.add(themeToggle);

        header.add(right, BorderLayout.EAST);
        return header;
    }

    // ─── Center = sidebar + content ──────────────────────────────────────────

    private JPanel buildCenter() {
        JPanel center = new JPanel(new BorderLayout());
        sidebarPanel = buildSidebar();
        center.add(sidebarPanel, BorderLayout.WEST);

        contentWrapper = new JPanel(new BorderLayout());
        contentWrapper.setBorder(new EmptyBorder(UIConstants.GAP_LG, UIConstants.GAP_LG,
                UIConstants.GAP_LG, UIConstants.GAP_LG));
        center.add(contentWrapper, BorderLayout.CENTER);
        return center;
    }

    // ─── Sidebar ─────────────────────────────────────────────────────────────

    private JPanel buildSidebar() {
        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        panel.setPreferredSize(new Dimension(UIConstants.SIDEBAR_WIDTH, 0));
        panel.setBackground(ThemeManager.sidebarBg());

        // User identity block
        JPanel userBlock = new JPanel();
        userBlock.setLayout(new BoxLayout(userBlock, BoxLayout.Y_AXIS));
        userBlock.setOpaque(false);
        userBlock.setBorder(new EmptyBorder(UIConstants.GAP_LG, UIConstants.GAP_MD,
                UIConstants.GAP_LG, UIConstants.GAP_MD));
        userBlock.setMaximumSize(new Dimension(UIConstants.SIDEBAR_WIDTH, 100));

        if (currentUser != null) {
            JLabel avatar = new JLabel(getAvatarLabel(currentUser.getUsername()),
                    SwingConstants.CENTER);
            avatar.setFont(new Font("Segoe UI", Font.BOLD, 28));
            avatar.setForeground(Color.WHITE);
            avatar.setAlignmentX(Component.CENTER_ALIGNMENT);
            userBlock.add(avatar);
            userBlock.add(Box.createVerticalStrut(UIConstants.GAP_SM));

            JLabel nameLabel = new JLabel(currentUser.getUsername());
            nameLabel.setFont(UIConstants.FONT_BODY_BOLD);
            nameLabel.setForeground(Color.WHITE);
            nameLabel.setAlignmentX(Component.CENTER_ALIGNMENT);
            userBlock.add(nameLabel);
        }
        panel.add(userBlock);

        // Divider
        JSeparator sep = new JSeparator();
        sep.setForeground(new Color(255, 255, 255, 50));
        sep.setBackground(new Color(255, 255, 255, 50));
        sep.setMaximumSize(new Dimension(UIConstants.SIDEBAR_WIDTH, 1));
        panel.add(sep);
        panel.add(Box.createVerticalStrut(UIConstants.GAP_SM));

        // Nav items
        for (String item : getSidebarItems()) {
            panel.add(buildNavButton(item, panel));
        }

        panel.add(Box.createVerticalGlue());

        // Logout button at bottom
        JButton logoutBtn = buildLogoutButton();
        panel.add(logoutBtn);
        panel.add(Box.createVerticalStrut(UIConstants.GAP_MD));

        return panel;
    }

    private JButton buildNavButton(String label, JPanel sidebar) {
        JButton btn = new JButton(label);
        btn.setFont(UIConstants.FONT_NAV);
        btn.setForeground(UIConstants.SIDEBAR_TEXT);
        btn.setOpaque(true);
        btn.setBackground(ThemeManager.sidebarBg());
        btn.setBorderPainted(false);
        btn.setFocusPainted(false);
        btn.setHorizontalAlignment(SwingConstants.LEFT);
        btn.setBorder(new EmptyBorder(UIConstants.GAP_SM, UIConstants.GAP_LG,
                UIConstants.GAP_SM, UIConstants.GAP_MD));
        btn.setMaximumSize(new Dimension(UIConstants.SIDEBAR_WIDTH, 40));
        btn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));

        btn.addMouseListener(new MouseAdapter() {
            @Override public void mouseEntered(MouseEvent e) {
                if (!label.equals(selectedItem))
                    btn.setBackground(ThemeManager.sidebarHover());
            }
            @Override public void mouseExited(MouseEvent e) {
                if (!label.equals(selectedItem))
                    btn.setBackground(ThemeManager.sidebarBg());
            }
        });

        btn.addActionListener(e -> {
            selectedItem = label;
            refreshSidebarHighlight();
            showPanel(label);
        });

        return btn;
    }

    private JButton buildLogoutButton() {
        JButton btn = new JButton("Logout");
        btn.setFont(UIConstants.FONT_NAV_BOLD);
        btn.setForeground(new Color(255, 180, 180));
        btn.setBackground(ThemeManager.sidebarBg());
        btn.setOpaque(true);
        btn.setBorderPainted(false);
        btn.setFocusPainted(false);
        btn.setHorizontalAlignment(SwingConstants.LEFT);
        btn.setBorder(new EmptyBorder(UIConstants.GAP_SM, UIConstants.GAP_LG,
                UIConstants.GAP_SM, UIConstants.GAP_MD));
        btn.setMaximumSize(new Dimension(UIConstants.SIDEBAR_WIDTH, 40));
        btn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        btn.addActionListener(e -> logout());
        return btn;
    }

    // ─── Status bar ──────────────────────────────────────────────────────────

    private JPanel buildStatusBar() {
        JPanel bar = new JPanel(new BorderLayout());
        bar.setPreferredSize(new Dimension(0, UIConstants.STATUS_HEIGHT));
        bar.setBackground(UIConstants.STATUS_BAR_BG);
        bar.setBorder(new EmptyBorder(0, UIConstants.GAP_LG, 0, UIConstants.GAP_LG));

        String role = currentUser != null ? currentUser.getRole() : "—";
        String user = currentUser != null ? currentUser.getUsername() : "—";
        statusLabel = new JLabel("  User: " + user + "   |   Role: " + role + "   |   BADAS v2.0");
        statusLabel.setFont(UIConstants.FONT_SMALL);
        statusLabel.setForeground(UIConstants.STATUS_BAR_TEXT);
        bar.add(statusLabel, BorderLayout.WEST);

        clockLabel = new JLabel();
        clockLabel.setFont(UIConstants.FONT_SMALL);
        clockLabel.setForeground(UIConstants.STATUS_BAR_TEXT);
        bar.add(clockLabel, BorderLayout.EAST);

        // Live clock
        Timer clock = new Timer(1000, e -> clockLabel.setText(
                LocalDateTime.now().format(CLOCK_FMT) + "  "));
        clock.start();
        clockLabel.setText(LocalDateTime.now().format(CLOCK_FMT) + "  ");

        return bar;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private void refreshSidebarHighlight() {
        if (sidebarPanel == null) return;
        for (Component c : sidebarPanel.getComponents()) {
            if (c instanceof JButton btn) {
                boolean sel = btn.getText().equals(selectedItem);
                btn.setBackground(sel ? ThemeManager.sidebarSelected() : ThemeManager.sidebarBg());
                btn.setFont(sel ? UIConstants.FONT_NAV_BOLD : UIConstants.FONT_NAV);
            }
        }
    }

    private void refreshSidebarColors() {
        if (sidebarPanel == null) return;
        sidebarPanel.setBackground(ThemeManager.sidebarBg());
        for (Component c : sidebarPanel.getComponents()) {
            if (c instanceof JButton btn) {
                boolean sel = btn.getText().equals(selectedItem);
                btn.setBackground(sel ? ThemeManager.sidebarSelected() : ThemeManager.sidebarBg());
            }
        }
    }

    private void selectNavItem(String item) {
        selectedItem = item;
        showPanel(item);
    }

    private JLabel createRoleBadge(String role) {
        JLabel badge = new JLabel("  " + role + "  ") {
            @Override protected void paintComponent(Graphics g) {
                Graphics2D g2 = (Graphics2D) g.create();
                g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
                g2.setColor(UIConstants.roleColor(role));
                g2.fillRoundRect(0, 0, getWidth(), getHeight(), 12, 12);
                g2.dispose();
                super.paintComponent(g);
            }
        };
        badge.setFont(UIConstants.FONT_BADGE);
        badge.setForeground(Color.WHITE);
        badge.setOpaque(false);
        badge.setBorder(new EmptyBorder(3, 6, 3, 6));
        return badge;
    }

    private String getAvatarLabel(String username) {
        if (username == null || username.isBlank()) return "?";
        return String.valueOf(Character.toUpperCase(username.charAt(0)));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Navigation helpers available to subclasses
    // ─────────────────────────────────────────────────────────────────────────

    /** Replaces the content wrapper with the given panel. */
    protected void setContent(JPanel panel) {
        contentWrapper.removeAll();
        contentWrapper.add(panel, BorderLayout.CENTER);
        contentWrapper.revalidate();
        contentWrapper.repaint();
    }

    /** Builds a styled section-title label for use inside content panels. */
    protected JLabel pageTitle(String text) {
        JLabel lbl = new JLabel(text);
        lbl.setFont(UIConstants.FONT_PAGE_TITLE);
        lbl.setBorder(new EmptyBorder(0, 0, UIConstants.GAP_MD, 0));
        return lbl;
    }

    /** Styled primary action button (blue). */
    protected JButton primaryButton(String text) {
        JButton btn = new JButton(text);
        btn.setFont(UIConstants.FONT_BUTTON);
        btn.setBackground(UIConstants.PRIMARY);
        btn.setForeground(Color.WHITE);
        btn.setFocusPainted(false);
        btn.setBorderPainted(false);
        btn.setCursor(Cursor.getPredefinedCursor(Cursor.HAND_CURSOR));
        btn.setPreferredSize(new Dimension(btn.getPreferredSize().width, UIConstants.BUTTON_HEIGHT));
        return btn;
    }

    /** Styled danger button (red). */
    protected JButton dangerButton(String text) {
        JButton btn = primaryButton(text);
        btn.setBackground(UIConstants.ACCENT_RED);
        return btn;
    }

    /** Styled success button (green). */
    protected JButton successButton(String text) {
        JButton btn = primaryButton(text);
        btn.setBackground(UIConstants.SUCCESS);
        return btn;
    }

    /** Applies standard styling to a JTable. */
    protected void styleTable(JTable table) {
        table.setRowHeight(UIConstants.ROW_HEIGHT);
        table.setFont(UIConstants.FONT_BODY);
        table.setGridColor(new Color(220, 220, 220));
        table.setSelectionBackground(UIConstants.TABLE_SELECTION);
        table.setSelectionForeground(Color.WHITE);
        table.setShowVerticalLines(false);
        table.setIntercellSpacing(new Dimension(0, 1));
        table.getTableHeader().setFont(UIConstants.FONT_BODY_BOLD);
        table.getTableHeader().setBackground(UIConstants.TABLE_HEADER_BG);
        table.getTableHeader().setForeground(UIConstants.TABLE_HEADER_FG);
        table.getTableHeader().setPreferredSize(
                new Dimension(0, UIConstants.ROW_HEIGHT + 4));
        table.setDefaultRenderer(Object.class, new javax.swing.table.DefaultTableCellRenderer() {
            @Override
            public Component getTableCellRendererComponent(JTable t, Object value,
                    boolean isSelected, boolean hasFocus, int row, int col) {
                Component c = super.getTableCellRendererComponent(t, value, isSelected, hasFocus, row, col);
                if (!isSelected) {
                    c.setBackground(row % 2 == 0 ? Color.WHITE : UIConstants.TABLE_ROW_ALT);
                }
                setBorder(new EmptyBorder(0, UIConstants.GAP_SM, 0, UIConstants.GAP_SM));
                return c;
            }
        });
    }

    /** Styled text field. */
    protected JTextField styledField(int columns) {
        JTextField f = new JTextField(columns);
        f.setFont(UIConstants.FONT_BODY);
        f.setPreferredSize(new Dimension(f.getPreferredSize().width, UIConstants.FIELD_HEIGHT));
        return f;
    }

    /** Logout and return to login screen. */
    protected void logout() {
        int confirm = JOptionPane.showConfirmDialog(this,
                "Are you sure you want to logout?", "Logout", JOptionPane.YES_NO_OPTION);
        if (confirm == JOptionPane.YES_OPTION) {
            AuthService.getInstance().logout();
            dispose();
            SwingUtilities.invokeLater(() -> new LoginFrame().setVisible(true));
        }
    }
}
