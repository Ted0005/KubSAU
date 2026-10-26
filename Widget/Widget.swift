import WidgetKit
import SwiftUI

// Виджет «Учёба»: ближайшие пары и сроки. Данные приложение кладёт в общее хранилище (App Group).

private let groupID = "group.ru.arman.uchyoba"

struct Lesson: Codable {
    var d: String   // дата yyyy-MM-dd
    var s: String   // начало HH:mm
    var e: String   // конец HH:mm
    var n: String   // предмет
    var r: String   // аудитория
    var k: String   // lec / pr

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    var start: Date? { Lesson.fmt.date(from: d + " " + s) }
    var end: Date? { Lesson.fmt.date(from: d + " " + e) }
}

struct TaskItem: Codable {
    var t: String
    var s: String
    var ty: String
    var due: Double
}

struct Snapshot: Codable {
    var lessons: [Lesson]
    var tasks: [TaskItem]
    var updated: Double
}

func loadSnapshot() -> Snapshot? {
    guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID),
          let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.json")) else { return nil }
    return try? JSONDecoder().decode(Snapshot.self, from: data)
}

struct Entry: TimelineEntry {
    let date: Date
    let snap: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snap: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snap = loadSnapshot()
        let now = Date()
        var dates: [Date] = [now]
        if let s = snap {
            for l in s.lessons {
                for d in [l.start, l.end] {
                    if let d = d, d > now, d < now.addingTimeInterval(86400) { dates.append(d) }
                }
            }
        }
        let sorted = Array(Set(dates)).sorted().prefix(24)
        let entries = sorted.map { Entry(date: $0, snap: snap) }
        completion(Timeline(entries: Array(entries), policy: .after(now.addingTimeInterval(3600))))
    }
}

private let bgColor = Color(red: 0.102, green: 0.114, blue: 0.106)
private let accent = Color(red: 0.298, green: 0.686, blue: 0.314)
private let lecColor = Color(red: 0.784, green: 0.525, blue: 0.051)
private let muted = Color(red: 0.663, green: 0.682, blue: 0.667)

extension View {
    @ViewBuilder func widgetBG(_ c: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(c, for: .widget)
        } else {
            self.background(c)
        }
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var upcoming: [Lesson] {
        guard let s = entry.snap else { return [] }
        return s.lessons
            .filter { ($0.end ?? Date.distantPast) > entry.date }
            .sorted { ($0.start ?? Date.distantFuture) < ($1.start ?? Date.distantFuture) }
    }

    var nextTask: TaskItem? {
        guard let s = entry.snap else { return nil }
        return s.tasks
            .filter { Date(timeIntervalSince1970: $0.due / 1000) > entry.date }
            .sorted { $0.due < $1.due }
            .first
    }

    func dayLabel(_ l: Lesson) -> String {
        guard let st = l.start else { return "" }
        if Calendar.current.isDate(st, inSameDayAs: entry.date) { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "E"
        return f.string(from: st).capitalized + " "
    }

    func state(_ l: Lesson) -> String {
        if let st = l.start, st <= entry.date { return "Сейчас" }
        return "Далее"
    }

    func taskLine(_ t: TaskItem) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return t.ty + ": " + t.t + " · " + f.string(from: Date(timeIntervalSince1970: t.due / 1000))
    }

    func row(_ l: Lesson) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(l.k == "lec" ? lecColor : muted)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.n)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(dayLabel(l) + l.s + "–" + l.e + (l.r.isEmpty ? "" : " · " + l.r))
                    .font(.system(size: 12))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        if entry.snap == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Учёба").font(.headline).foregroundColor(accent)
                Text("Откройте приложение, чтобы здесь появились пары и сроки.")
                    .font(.system(size: 12))
                    .foregroundColor(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBG(bgColor)
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 4) {
                if let l = upcoming.first {
                    Text(state(l))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                    Text(l.n)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(3)
                    Text(dayLabel(l) + l.s + "–" + l.e)
                        .font(.system(size: 13))
                        .foregroundColor(muted)
                    if !l.r.isEmpty {
                        Text(l.r).font(.system(size: 13)).foregroundColor(muted).lineLimit(1)
                    }
                } else {
                    Text("Пар больше нет")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    if let t = nextTask {
                        Text(taskLine(t))
                            .font(.system(size: 12))
                            .foregroundColor(muted)
                            .lineLimit(4)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBG(bgColor)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if upcoming.isEmpty {
                    Text("Пар больше нет")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { _, l in
                        row(l)
                    }
                }
                Spacer(minLength: 0)
                if let t = nextTask {
                    Text(taskLine(t))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accent)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBG(bgColor)
        }
    }
}

@main
struct UchyobaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UchyobaWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Учёба")
        .description("Ближайшие пары и сроки")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
