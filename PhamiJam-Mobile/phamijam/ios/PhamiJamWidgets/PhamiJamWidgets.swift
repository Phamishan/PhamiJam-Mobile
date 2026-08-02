import SwiftUI
import WidgetKit

private let appGroupId = "group.phamishan.phamijam.widget"
private let minutesKey = "minutes_played"
private let yearKey = "wrapped_year"

struct MinutesEntry: TimelineEntry {
    let date: Date
    let minutes: Int
    let year: Int
}

struct MinutesProvider: TimelineProvider {
    func placeholder(in context: Context) -> MinutesEntry {
        MinutesEntry(date: Date(), minutes: 0, year: currentYear())
    }

    func getSnapshot(in context: Context, completion: @escaping (MinutesEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MinutesEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry()], policy: .never)
        completion(timeline)
    }

    private func currentYear() -> Int {
        Calendar.current.component(.year, from: Date())
    }

    private func currentEntry() -> MinutesEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let minutes = defaults?.integer(forKey: minutesKey) ?? 0
        let year = defaults?.integer(forKey: yearKey) ?? currentYear()
        return MinutesEntry(date: Date(), minutes: minutes, year: year)
    }
}

private let widgetGold = Color(red: 0.86, green: 0.64, blue: 0.23)
private let widgetDark = Color(red: 0.11, green: 0.11, blue: 0.10)

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
            .containerBackground(for: .widget) { widgetGold }
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
            .containerBackground(for: .widget) { widgetGold }
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

@main
struct PhamiJamWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PhamiJamMinutesWidget()
    }
}
