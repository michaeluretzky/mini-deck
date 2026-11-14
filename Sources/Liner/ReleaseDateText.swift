// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Formats catalog dates without changing their precision or applying a local time zone.
enum ReleaseDateText {
    private static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    static func display(_ value: String?) -> String? {
        guard let value else { return nil }
        // Apple's timestamp represents a catalog date, not a local playback instant.
        let date = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "T")[0]
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts[0].count == 4,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(parts[0]), year > 0 else { return nil }
        if parts.count == 1 { return String(parts[0]) }
        guard parts[1].count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        if parts.count == 2 { return "\(months[month - 1]) \(parts[0])" }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard parts[2].count == 2, let day = Int(parts[2]), (1...days[month - 1]).contains(day) else { return nil }
        return "\(months[month - 1]) \(day), \(parts[0])"
    }
}
