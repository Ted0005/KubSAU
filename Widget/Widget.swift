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
    var start: Date? { Lesson.fmt.date(from: "\(d) \(s)") }
    var end: Date? { Lesson.fmt.date(from: "\(d) \(e)") }
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
        let sorted: [Date] = Array(Set(dates)).sorted()
        var entries: [Entry] = []
        for d in sorted.prefix(24) {
            entries.append(Entry(date: d, snap: snap))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
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
        let now = entry.date
        var list: [Lesson] = []
        for l in s.lessons {
            if let e = l.end, e > now { list.append(l) }
        }
        list.sort { (a: Lesson, b: Lesson) -> Bool in
            let x: Date = a.start ?? Date.distantFuture
            let y: Date = b.start ?? Date.distantFuture
            return x < y
        }
        return list
    }

    var nextTask: TaskItem? {
        guard let s = entry.snap else { return nil }
        let nowMs: Double = entry.date.timeIntervalSince1970 * 1000
        var list: [TaskItem] = []
        for t in s.tasks {
            if t.due > nowMs { list.append(t) }
        }
        list.sort { (a: TaskItem, b: TaskItem) -> Bool in a.due < b.due }
        return list.first
    }

    func dayLabel(_ l: Lesson) -> String {
        guard let st = l.start else { return "" }
        if Calendar.current.isDate(st, inSameDayAs: entry.date) { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "E"
        let w: String = f.string(from: st).capitalized
        return "\(w) "
    }

    func timeRange(_ l: Lesson) -> String {
        let day: String = dayLabel(l)
        return "\(day)\(l.s)–\(l.e)"
    }

    func timeAndRoom(_ l: Lesson) -> String {
        let t: String = timeRange(l)
        if l.r.isEmpty { return t }
        return "\(t) · \(l.r)"
    }

    func state(_ l: Lesson) -> String {
        if let st = l.start, st <= entry.date { return "Сейчас" }
        return "Далее"
    }

    func taskLine(_ t: TaskItem) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        let when: String = f.string(from: Date(timeIntervalSince1970: t.due / 1000))
        return "\(t.ty): \(t.t) · \(when)"
    }

    func row(_ l: Lesson) -> some View {
        let barColor: Color = (l.k == "lec") ? lecColor : muted
        let line2: String = timeAndRoom(l)
        return HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(barColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.n)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(line2)
                    .font(.system(size: 12))
                    .foregroundColor(muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Учёба").font(.headline).foregroundColor(accent)
            Text("Откройте приложение, чтобы здесь появились пары и сроки.")
                .font(.system(size: 12))
                .foregroundColor(muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let l = upcoming.first {
                Text(state(l))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accent)
                Text(l.n)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                Text(timeRange(l))
                    .font(.system(size: 13))
                    .foregroundColor(muted)
                if !l.r.isEmpty {
                    Text(l.r)
                        .font(.system(size: 13))
                        .foregroundColor(muted)
                        .lineLimit(1)
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
    }

    var mediumView: some View {
        let shown: [Lesson] = Array(upcoming.prefix(3))
        return VStack(alignment: .leading, spacing: 6) {
            if shown.isEmpty {
                Text("Пар больше нет")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            } else {
                ForEach(0..<shown.count, id: \.self) { i in
                    row(shown[i])
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
    }

    @ViewBuilder var content: some View {
        if entry.snap == nil {
            emptyView
        } else if family == .systemSmall {
            smallView
        } else {
            mediumView
        }
    }

    var body: some View {
        content.widgetBG(bgColor)
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
