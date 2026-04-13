package com.badas.ui.common;

import javax.swing.*;
import java.awt.*;
import java.util.prefs.Preferences;

/**
 * Manages light/dark theme switching.
 * Tries to apply FlatLaf if available; falls back to the system L&F gracefully.
 * Theme preference is persisted between sessions via java.util.prefs.
 */
public final class ThemeManager {

    private static final String PREF_KEY = "badas.theme";
    private static final String DARK     = "dark";
    private static final String LIGHT    = "light";

    private static boolean isDark = false;

    private ThemeManager() {}

    /** Call once at startup before any window is created. */
    public static void applyTheme() {
        Preferences prefs = Preferences.userNodeForPackage(ThemeManager.class);
        isDark = DARK.equals(prefs.get(PREF_KEY, LIGHT));
        applyCurrentTheme();
    }

    /** Toggles theme and updates all open windows immediately. */
    public static void toggleTheme() {
        isDark = !isDark;
        Preferences prefs = Preferences.userNodeForPackage(ThemeManager.class);
        prefs.put(PREF_KEY, isDark ? DARK : LIGHT);
        applyCurrentTheme();
        for (Window w : Window.getWindows()) {
            SwingUtilities.updateComponentTreeUI(w);
            w.repaint();
        }
    }

    public static boolean isDark() { return isDark; }

    /** Returns the sidebar background colour adjusted for current theme. */
    public static Color sidebarBg() {
        return isDark ? UIConstants.SIDEBAR_DARK_BG : UIConstants.SIDEBAR_BG;
    }

    /** Returns the sidebar hover colour adjusted for current theme. */
    public static Color sidebarHover() {
        return isDark ? UIConstants.SIDEBAR_DARK_HOVER : UIConstants.SIDEBAR_HOVER;
    }

    /** Returns the sidebar selected colour adjusted for current theme. */
    public static Color sidebarSelected() {
        return isDark ? UIConstants.SIDEBAR_DARK_SELECTED : UIConstants.SIDEBAR_SELECTED;
    }

    // ─────────────────────────────────────────────────────────────────────────

    private static void applyCurrentTheme() {
        try {
            if (isDark) {
                // Try FlatDarkLaf
                Class<?> cls = Class.forName("com.formdev.flatlaf.FlatDarkLaf");
                UIManager.setLookAndFeel((LookAndFeel) cls.getDeclaredConstructor().newInstance());
            } else {
                // Try FlatLightLaf
                Class<?> cls = Class.forName("com.formdev.flatlaf.FlatLightLaf");
                UIManager.setLookAndFeel((LookAndFeel) cls.getDeclaredConstructor().newInstance());
            }
        } catch (ClassNotFoundException e) {
            // FlatLaf not on classpath — fall back to Nimbus (better than Metal)
            applyNimbus();
        } catch (Exception e) {
            applyNimbus();
        }

        // Always apply custom accent colour so FlatLaf buttons use our blue
        UIManager.put("Component.accentColor", UIConstants.PRIMARY);
        UIManager.put("Button.arc", UIConstants.CORNER_RADIUS * 2);
        UIManager.put("TextComponent.arc", UIConstants.CORNER_RADIUS * 2);
        UIManager.put("Table.rowHeight", UIConstants.ROW_HEIGHT);
    }

    private static void applyNimbus() {
        try {
            for (UIManager.LookAndFeelInfo info : UIManager.getInstalledLookAndFeels()) {
                if ("Nimbus".equals(info.getName())) {
                    UIManager.setLookAndFeel(info.getClassName());
                    return;
                }
            }
        } catch (Exception ignored) {}
        // Final fallback — cross-platform L&F
        try {
            UIManager.setLookAndFeel(UIManager.getCrossPlatformLookAndFeelClassName());
        } catch (Exception ignored) {}
    }
}
