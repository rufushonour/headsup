import Foundation
import EventKit

/// Finds a video-conferencing join URL for a calendar event by checking, in order,
/// the event's own `url` field, then its location, then its notes.
enum MeetingLinkExtractor {

    /// Domains treated as known conferencing providers, checked first so a Zoom/Meet/Teams
    /// link is preferred over some unrelated URL that happens to appear in the notes.
    private static let knownDomains = [
        "zoom.us", "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
        "gotomeeting.com",
        "bluejeans.com",
        "whereby.com",
        "chime.aws",
        "meet.jit.si",
        "skype.com", "join.skype.com",
        "meetings.hubspot.com",
        "meet.ringcentral.com",
        "8x8.vc",
        "join.me",
        "app.livestorm.co",
        "vonage.com",
        "loom.com/meet",
        "around.co",
        "slack.com/huddle"
    ]

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>()"]+"#,
        options: []
    )

    static func link(for event: EKEvent) -> URL? {
        var candidates: [String] = []

        if let url = event.url {
            candidates.append(url.absoluteString)
        }
        if let location = event.location {
            candidates.append(contentsOf: extractURLs(from: location))
        }
        if let notes = event.notes {
            candidates.append(contentsOf: extractURLs(from: notes))
        }

        // Prefer a known conferencing domain if one is present.
        if let known = candidates.first(where: { isKnownDomain($0) }) {
            return URL(string: known)
        }
        // Otherwise fall back to the first URL found (e.g. event.url itself).
        if let first = candidates.first {
            return URL(string: first)
        }
        return nil
    }

    private static func extractURLs(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = urlRegex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
        }
    }

    private static func isKnownDomain(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return knownDomains.contains { host.contains($0) }
    }
}
