import Foundation
import EventKit

/// Finds a video-conferencing join URL for a calendar event by collecting the URLs in the
/// event's own `url` field, its location, and its notes, then picking the one that looks
/// most like an actual "join the meeting" link.
enum MeetingLinkExtractor {

    /// Domains treated as known conferencing providers, so a Zoom/Meet/Teams link is
    /// preferred over some unrelated URL that happens to appear in the notes.
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
        "around.co",
        "slack.com/huddle"
    ]

    /// URL shapes that identify the actual join link, as opposed to some other page on the
    /// same conferencing domain.
    private static let joinPathHints = [
        "/l/meetup-join/",  // Teams
        "/meetup-join",     // Teams, without the /l/ prefix
        "/l/meeting/",      // Teams, older invite format
        "/meet/",           // teams.live.com, Webex personal rooms, RingCentral
        "/j/",              // Zoom
        "/w/",              // Zoom webinars
        "/my/",             // Zoom personal meeting rooms
        "/wc/join/",        // Zoom web client
        "/j.php",           // Webex
        "/join"             // Whereby, GoToMeeting, join.me
    ]

    /// Pages that live on conferencing domains but are never the join link. Teams invites
    /// in particular ship a block of these alongside the real one.
    private static let nonJoinPathHints = [
        "meetingoptions",   // Teams "Meeting options"
        "dialin.",          // Teams dial-in numbers / PIN reset
        "/l/channel/",      // a Teams channel, not a meeting
        "/l/chat/",         // a Teams chat
        "/l/team/",         // a Teams team
        "/l/app/",          // a Teams app page
        "/download"         // "get the app" links on any provider
    ]

    /// How much a URL looks like the join link. Ordered worst to best, so `rank` values
    /// can be compared directly.
    private enum Rank: Int, Comparable {
        /// On a conferencing domain, but a page known not to be joinable.
        case knownNonJoinPage
        /// Some other URL entirely — could still be an unrecognized provider.
        case unrecognized
        /// A conferencing domain with nothing more specific to go on.
        case conferencingDomain
        /// A conferencing domain *and* a join-shaped URL.
        case joinLink

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

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

        return bestLink(from: candidates)
    }

    /// Picks the likeliest join link out of `candidates`.
    ///
    /// Document order alone isn't enough to go on, which is what this used to rely on: a
    /// Teams invite body carries several teams.microsoft.com URLs — "Meeting options",
    /// dial-in, the Teams app — and any of them can appear *before* the real meetup-join
    /// URL, so taking the first one on a known conferencing domain opened the wrong page.
    /// Rank by how much each URL looks like a join link instead, and only fall back to
    /// document order to break ties.
    static func bestLink(from candidates: [String]) -> URL? {
        var best: (rank: Rank, urlString: String)?
        for candidate in candidates {
            let rank = rank(of: candidate)
            // Strictly greater, so the earliest candidate wins among equals.
            if best == nil || rank > best!.rank {
                best = (rank, candidate)
            }
        }
        return best.flatMap { URL(string: $0.urlString) }
    }

    private static func rank(of urlString: String) -> Rank {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return .unrecognized
        }
        guard knownDomains.contains(where: { host.contains($0) }) else {
            return .unrecognized
        }

        // Match against host + path + query together: the distinguishing part sits in the
        // path for Teams/Zoom ("/l/meetup-join/", "/j/") but in the host for Teams dial-in
        // ("dialin.teams.microsoft.com") and in the query for Webex ("/j.php?MTID=").
        let haystack = (host + url.path + "?" + (url.query ?? "")).lowercased()
        if nonJoinPathHints.contains(where: { haystack.contains($0) }) {
            return .knownNonJoinPage
        }
        return joinPathHints.contains(where: { haystack.contains($0) }) ? .joinLink : .conferencingDomain
    }

    static func extractURLs(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = urlRegex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            let raw = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
            return unwrapSafeLink(raw)
        }
    }

    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>()"]+"#,
        options: []
    )

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
}
