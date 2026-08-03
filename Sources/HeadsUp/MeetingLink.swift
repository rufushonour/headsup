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
            candidates.append(unwrapSafeLink(url.absoluteString))
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
            let raw = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
            return unwrapSafeLink(raw)
        }
    }

    /// Microsoft Defender's Safe Links rewrites every URL in an Outlook/Exchange invite
    /// into an `https://*.safelinks.protection.outlook.com/?url=<encoded original>&...`
    /// wrapper — extremely common in Microsoft 365 orgs. Since the real destination is
    /// then percent-encoded, it never matches `knownDomains` (host is safelinks.protection
    /// .outlook.com, not e.g. teams.microsoft.com) and gets treated as just some
    /// unrecognized URL, so the join link loses its "known domain" priority to whatever
    /// happens to appear first in the invite body. Unwrap it back to the real URL so
    /// domain matching (and the link we actually open) sees the true destination.
    private static func unwrapSafeLink(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              host.contains("safelinks.protection.outlook.com"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let inner = components.queryItems?.first(where: { $0.name == "url" })?.value
        else {
            return urlString
        }
        return inner
    }

    private static func isKnownDomain(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return knownDomains.contains { host.contains($0) }
    }
}
