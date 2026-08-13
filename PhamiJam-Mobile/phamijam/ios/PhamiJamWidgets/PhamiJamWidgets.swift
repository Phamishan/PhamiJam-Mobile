import SwiftUI
import WidgetKit

private let appGroupId = "group.phamishan.phamijam.widget"
private let minutesKey = "minutes_played"
private let yearKey = "wrapped_year"
private let accentColorKey = "accent_color"
private let streakDaysKey = "streak_days"
private let topSongTitleKey = "top_song_title"
private let topSongArtistKey = "top_song_artist"
private let nowPlayingTitleKey = "now_playing_title"
private let nowPlayingArtistKey = "now_playing_artist"
private let nowPlayingLabelKey = "now_playing_label"

private let widgetGold = Color(red: 0.86, green: 0.64, blue: 0.23)
private let widgetDark = Color(red: 0.11, green: 0.11, blue: 0.10)

private func currentYear() -> Int {
    Calendar.current.component(.year, from: Date())
}

private func accentColor(from defaults: UserDefaults?) -> Color {
    let packed = defaults?.integer(forKey: accentColorKey) ?? 0
    if packed == 0 { return widgetGold }
    let value = UInt32(bitPattern: Int32(truncatingIfNeeded: packed))
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

// MARK: - Minutes widget

struct MinutesEntry: TimelineEntry {
    let date: Date
    let minutes: Int
    let year: Int
    let accentColor: Color
}

struct MinutesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinutesEntry {
        MinutesEntry(date: Date(), minutes: 0, year: currentYear(), accentColor: widgetGold)
    }

    func getSnapshot(in context: Context, completion: @escaping (MinutesEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinutesEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentEntry() -> MinutesEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let minutes = defaults?.integer(forKey: minutesKey) ?? 0
        let year = defaults?.integer(forKey: yearKey) ?? currentYear()
        return MinutesEntry(date: Date(), minutes: minutes, year: year, accentColor: accentColor(from: defaults))
    }
}

struct PhamiJamMinutesWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: MinutesEntry

    var body: some View {
        switch family {
        case .systemLarge:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .foregroundColor(widgetDark)
                    Text("Wrapphamied")
                        .font(.subheadline)
                        .foregroundColor(widgetDark)
                }
                Spacer()
                Text("\(entry.minutes)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(widgetDark)
                Text("minutes listened in \(String(entry.year))")
                    .font(.subheadline)
                    .foregroundColor(widgetDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .containerBackground(for: .widget) { entry.accentColor }
        default:
            VStack(spacing: 2) {
                Text("\(entry.minutes)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(widgetDark)
                Text("min this year")
                    .font(.caption2)
                    .foregroundColor(widgetDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
            .containerBackground(for: .widget) { entry.accentColor }
        }
    }
}

struct PhamiJamMinutesWidget: Widget {
    let kind: String = "PhamiJamMinutesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MinutesProvider()) { entry in
            PhamiJamMinutesWidgetView(entry: entry)
        }
        .configurationDisplayName("Wrapphamied Minutes")
        .description("Shows how many minutes you've listened to this year.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Now Playing widget

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let label: String
    let accentColor: Color
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), title: "Nothing playing yet", artist: "", label: "Now Playing", accentColor: widgetGold)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentEntry() -> NowPlayingEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let title = defaults?.string(forKey: nowPlayingTitleKey) ?? ""
        let artist = defaults?.string(forKey: nowPlayingArtistKey) ?? ""
        let label = defaults?.string(forKey: nowPlayingLabelKey) ?? "Now Playing"
        return NowPlayingEntry(
            date: Date(),
            title: title.isEmpty ? "Nothing playing yet" : title,
            artist: artist,
            label: label,
            accentColor: accentColor(from: defaults)
        )
    }
}

struct PhamiJamNowPlayingWidgetView: View {
    var entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.label)
                .font(.caption)
                .foregroundColor(widgetDark)
            Spacer()
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(widgetDark)
            if !entry.artist.isEmpty {
                Text(entry.artist)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(widgetDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(for: .widget) { entry.accentColor }
    }
}

struct PhamiJamNowPlayingWidget: Widget {
    let kind: String = "PhamiJamNowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            PhamiJamNowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows what you're currently listening to, or the last song you played.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Streak widget

struct StreakEntry: TimelineEntry {
    let date: Date
    let days: Int
    let accentColor: Color
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), days: 0, accentColor: widgetGold)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentEntry() -> StreakEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let days = defaults?.integer(forKey: streakDaysKey) ?? 0
        return StreakEntry(date: Date(), days: days, accentColor: accentColor(from: defaults))
    }
}

struct PhamiJamStreakWidgetView: View {
    var entry: StreakEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundColor(widgetDark)
                Text("Streak")
                    .font(.subheadline)
                    .foregroundColor(widgetDark)
            }
            Spacer()
            Text("\(entry.days)")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(widgetDark)
            Text(entry.days == 1 ? "day streak" : "day streak")
                .font(.subheadline)
                .foregroundColor(widgetDark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(for: .widget) { entry.accentColor }
    }
}

struct PhamiJamStreakWidget: Widget {
    let kind: String = "PhamiJamStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            PhamiJamStreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Listening Streak")
        .description("Shows how many days in a row you've listened to music.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

// MARK: - Top Song This Week widget

struct TopSongEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let accentColor: Color
}

struct TopSongProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopSongEntry {
        TopSongEntry(date: Date(), title: "No plays yet this week", artist: "", accentColor: widgetGold)
    }

    func getSnapshot(in context: Context, completion: @escaping (TopSongEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopSongEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentEntry() -> TopSongEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let title = defaults?.string(forKey: topSongTitleKey) ?? ""
        let artist = defaults?.string(forKey: topSongArtistKey) ?? ""
        return TopSongEntry(
            date: Date(),
            title: title.isEmpty ? "No plays yet this week" : title,
            artist: artist,
            accentColor: accentColor(from: defaults)
        )
    }
}

struct PhamiJamTopSongWidgetView: View {
    var entry: TopSongEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top Song This Week")
                .font(.caption)
                .foregroundColor(widgetDark)
            Spacer()
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)
                .foregroundColor(widgetDark)
            if !entry.artist.isEmpty {
                Text(entry.artist)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(widgetDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .containerBackground(for: .widget) { entry.accentColor }
    }
}

struct PhamiJamTopSongWidget: Widget {
    let kind: String = "PhamiJamTopSongWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TopSongProvider()) { entry in
            PhamiJamTopSongWidgetView(entry: entry)
        }
        .configurationDisplayName("Top Song This Week")
        .description("Shows your most-played song this week.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct PhamiJamWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PhamiJamMinutesWidget()
        PhamiJamNowPlayingWidget()
        PhamiJamStreakWidget()
        PhamiJamTopSongWidget()
    }
}
