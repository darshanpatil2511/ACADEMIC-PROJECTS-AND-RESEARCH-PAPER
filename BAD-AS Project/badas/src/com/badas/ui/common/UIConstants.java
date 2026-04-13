package com.badas.ui.common;

import java.awt.*;

/**
 * Central source of all UI measurements, colours, and fonts.
 * Colours are defined once here; all UI classes reference these constants.
 */
public final class UIConstants {

    private UIConstants() {}

    // ─── Primary brand palette ───────────────────────────────────────────────
    public static final Color PRIMARY          = new Color(21,  101, 192);   // #1565C0 deep medical blue
    public static final Color PRIMARY_DARK     = new Color(13,   71, 161);   // #0D47A1
    public static final Color PRIMARY_LIGHT    = new Color(66,  165, 245);   // #42A5F5
    public static final Color SECONDARY        = new Color(2,   136, 209);   // #0288D1 sky blue

    // ─── Semantic colours ────────────────────────────────────────────────────
    public static final Color ACCENT_RED       = new Color(229,  57,  53);   // #E53935 emergency
    public static final Color SUCCESS          = new Color(46,  125,  50);   // #2E7D32
    public static final Color WARNING          = new Color(245, 127,  23);   // #F57F17
    public static final Color INFO             = new Color(2,   136, 209);

    // ─── Sidebar ─────────────────────────────────────────────────────────────
    public static final Color SIDEBAR_BG       = new Color(21,  101, 192);
    public static final Color SIDEBAR_HOVER    = new Color(13,   71, 161);
    public static final Color SIDEBAR_SELECTED = new Color(5,   39, 103);
    public static final Color SIDEBAR_TEXT     = Color.WHITE;
    public static final Color SIDEBAR_SUB_TEXT = new Color(187, 222, 251);   // #BBDEFB

    // ─── Dark-mode sidebar ───────────────────────────────────────────────────
    public static final Color SIDEBAR_DARK_BG       = new Color(13,  27,  42);  // #0D1B2A
    public static final Color SIDEBAR_DARK_HOVER    = new Color(22,  45,  70);
    public static final Color SIDEBAR_DARK_SELECTED = new Color(30,  58,  95);

    // ─── Header ──────────────────────────────────────────────────────────────
    public static final Color HEADER_BG        = new Color(13,  71, 161);
    public static final Color HEADER_TEXT      = Color.WHITE;

    // ─── Status bar ──────────────────────────────────────────────────────────
    public static final Color STATUS_BAR_BG    = new Color(236, 239, 241);
    public static final Color STATUS_BAR_TEXT  = new Color(84,  110, 122);

    // ─── Table ───────────────────────────────────────────────────────────────
    public static final Color TABLE_HEADER_BG  = new Color(21,  101, 192);
    public static final Color TABLE_HEADER_FG  = Color.WHITE;
    public static final Color TABLE_ROW_ALT    = new Color(232, 240, 254);   // light blue tint
    public static final Color TABLE_SELECTION  = new Color(100, 160, 230);

    // ─── Role badge colours ──────────────────────────────────────────────────
    public static final Color ROLE_ADMIN       = new Color(183,  28,  28);
    public static final Color ROLE_DOCTOR      = new Color(21,  101, 192);
    public static final Color ROLE_NURSE       = new Color(0,   131, 143);
    public static final Color ROLE_RECEPTIONIST= new Color(81,   45, 168);
    public static final Color ROLE_DISPATCHER  = new Color(230,  81,   0);
    public static final Color ROLE_COORDINATOR = new Color(0,   105,  92);
    public static final Color ROLE_ITSUPPORT   = new Color(55,   71,  79);

    // ─── Severity colours ────────────────────────────────────────────────────
    public static final Color SEV_CRITICAL     = new Color(229,  57,  53);
    public static final Color SEV_MODERATE     = new Color(245, 127,  23);
    public static final Color SEV_MINOR        = new Color(46,  125,  50);
    public static final Color SEV_UNKNOWN      = new Color(117, 117, 117);

    // ─── Fonts ───────────────────────────────────────────────────────────────
    public static final Font FONT_APP_TITLE    = new Font("Segoe UI", Font.BOLD,  22);
    public static final Font FONT_PAGE_TITLE   = new Font("Segoe UI", Font.BOLD,  18);
    public static final Font FONT_SECTION      = new Font("Segoe UI", Font.BOLD,  14);
    public static final Font FONT_BODY         = new Font("Segoe UI", Font.PLAIN, 13);
    public static final Font FONT_BODY_BOLD    = new Font("Segoe UI", Font.BOLD,  13);
    public static final Font FONT_SMALL        = new Font("Segoe UI", Font.PLAIN, 11);
    public static final Font FONT_NAV          = new Font("Segoe UI", Font.PLAIN, 13);
    public static final Font FONT_NAV_BOLD     = new Font("Segoe UI", Font.BOLD,  13);
    public static final Font FONT_BUTTON       = new Font("Segoe UI", Font.BOLD,  13);
    public static final Font FONT_BADGE        = new Font("Segoe UI", Font.BOLD,  11);

    // ─── Dimensions ──────────────────────────────────────────────────────────
    public static final int SIDEBAR_WIDTH      = 220;
    public static final int HEADER_HEIGHT      = 56;
    public static final int STATUS_HEIGHT      = 28;
    public static final int ROW_HEIGHT         = 32;
    public static final int BUTTON_HEIGHT      = 34;
    public static final int FIELD_HEIGHT       = 34;
    public static final int CORNER_RADIUS      = 6;

    // ─── Spacing ─────────────────────────────────────────────────────────────
    public static final int GAP_XS = 4;
    public static final int GAP_SM = 8;
    public static final int GAP_MD = 12;
    public static final int GAP_LG = 20;
    public static final int GAP_XL = 32;

    // ─── Helpers ─────────────────────────────────────────────────────────────

    /** Returns the badge colour for a given role string (case-insensitive). */
    public static Color roleColor(String role) {
        if (role == null) return ROLE_ITSUPPORT;
        return switch (role.toLowerCase()) {
            case "admin"                -> ROLE_ADMIN;
            case "doctor"               -> ROLE_DOCTOR;
            case "nurse"                -> ROLE_NURSE;
            case "receptionist"         -> ROLE_RECEPTIONIST;
            case "dispatcher"           -> ROLE_DISPATCHER;
            case "emergency coordinator"-> ROLE_COORDINATOR;
            case "it support"           -> ROLE_ITSUPPORT;
            default                     -> ROLE_ITSUPPORT;
        };
    }

    /** Returns the severity badge colour. */
    public static Color severityColor(String level) {
        if (level == null) return SEV_UNKNOWN;
        return switch (level.toLowerCase()) {
            case "critical"             -> SEV_CRITICAL;
            case "severe", "moderate"   -> SEV_MODERATE;
            case "minor"                -> SEV_MINOR;
            default                     -> SEV_UNKNOWN;
        };
    }
}
