/// The small, closed vocabulary of Boston parking signs.
enum Vocabulary {
    /// Spelling on the sign -> canonical keyword.
    static let keywords: [String: String] = {
        var map: [String: String] = [:]
        let canonical = ["NO", "PARKING", "STOPPING", "STANDING", "TOW", "ZONE", "STREET", "CLEANING",
                         "SWEEPING", "HOUR", "MIN", "RESIDENT", "PERMIT", "ONLY", "EXCEPT", "ANY", "TIME",
                         "ALL", "LOADING", "SNOW", "EMERGENCY", "DAILY", "LIMIT",
                         "STICKER", "COMMERCIAL", "PICK", "UP", "DROP", "OFF", "METER"]
        for word in canonical { map[word] = word }
        let aliases = ["HR": "HOUR", "HRS": "HOUR", "HOURS": "HOUR",
                       "MINS": "MIN", "MINUTE": "MIN", "MINUTES": "MIN",
                       "RESIDENTS": "RESIDENT", "PERMITS": "PERMIT", "TIMES": "TIME",
                       "STICKERS": "STICKER", "METERS": "METER", "METERED": "METER", "PICKUP": "PICK"]
        for (alias, word) in aliases { map[alias] = word }
        return map
    }()

    /// Words that often appear on signs but don't change the rule. They count as understood.
    static let fillers: Set<String> = [
        "VEHICLES", "VEHICLE", "WILL", "BE", "TOWED", "AT", "OWNER", "OWNERS", "EXPENSE",
        "ROUTE", "OF", "THE", "MONTH", "EACH", "EVERY", "AWAY", "THIS", "AREA",
        // "DURING SNOW EMERGENCY", "PAY MULTI-SPACE METER TO PARK", "AS DEFINED BY B.T.D.",
        // "DRIVER MUST STAY WITH VEHICLE"
        "DURING", "PAY", "MULTI", "SPACE", "PARK", "AS", "DEFINED", "BY", "BTD",
        "DRIVER", "MUST", "STAY", "WITH",
    ]

    static let days: [String: Weekday] = [
        "SUN": .sun, "SUNDAY": .sun, "SUNDAYS": .sun,
        "MON": .mon, "MONDAY": .mon, "MONDAYS": .mon,
        "TUE": .tue, "TUES": .tue, "TUESDAY": .tue, "TUESDAYS": .tue,
        "WED": .wed, "WEDS": .wed, "WEDNESDAY": .wed, "WEDNESDAYS": .wed,
        "THU": .thu, "THUR": .thu, "THURS": .thu, "THURSDAY": .thu, "THURSDAYS": .thu,
        "FRI": .fri, "FRIDAY": .fri, "FRIDAYS": .fri,
        "SAT": .sat, "SATURDAY": .sat, "SATURDAYS": .sat,
    ]

    static let months: [String: Int] = [
        "JAN": 1, "JANUARY": 1, "FEB": 2, "FEBRUARY": 2, "MAR": 3, "MARCH": 3,
        "APR": 4, "APRIL": 4, "MAY": 5, "JUN": 6, "JUNE": 6, "JUL": 7, "JULY": 7,
        "AUG": 8, "AUGUST": 8, "SEP": 9, "SEPT": 9, "SEPTEMBER": 9, "OCT": 10, "OCTOBER": 10,
        "NOV": 11, "NOVEMBER": 11, "DEC": 12, "DECEMBER": 12,
    ]

    /// Words the normalizer rewrites itself (ranges, noon, midnight).
    static let specialWords: Set<String> = ["NOON", "MIDNIGHT", "TO", "THRU", "THROUGH", "AND", "ANYTIME"]

    /// Every word an OCR-damaged token may be corrected to.
    static let all: Set<String> = Set(keywords.keys)
        .union(fillers)
        .union(days.keys)
        .union(months.keys)
        .union(specialWords)
}
