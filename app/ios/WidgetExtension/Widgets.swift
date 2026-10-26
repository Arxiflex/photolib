import SwiftUI
import UIKit
import WidgetKit

/// Photolib's home screen widgets (docs/10 §6.4, ADR-0153). They read only what the app writes into the App Group's
/// Widgets/ (app/lib/core/widget_snapshot.dart), never the replica, and the app has WidgetKit reload them after it
/// writes. Memories and backup status join once the app has them.
@main
struct PhotolibWidgets: WidgetBundle {
  var body: some Widget {
    OnThisDay()
  }
}

/// `snapshot.json`, in the folder of the PNGs it names.
struct Snapshot: Decodable {
  struct Shown: Decodable {
    let year: Int
    let image: String
  }

  let version: Int
  let date: String
  let onThisDay: [Shown]

  static let folder = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.org.photolib.photolib")?
    .appendingPathComponent("Widgets", isDirectory: true)

  private static let day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  /// The snapshot of [now]'s day: one of another day says nothing about it.
  static func of(_ now: Date) -> Snapshot? {
    guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent("snapshot.json")),
      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
      snapshot.version == 1, snapshot.date == day.string(from: now)
    else { return nil }
    return snapshot
  }
}

/// A photo of this day in an earlier year, or none; [written] is false until the app wrote this day's snapshot.
struct Memory: TimelineEntry {
  let date: Date
  let year: Int?
  let image: URL?
  let written: Bool
}

/// This day's years, newest first, an hour each and round again until midnight, when the day changes.
struct OnThisDayTimeline: TimelineProvider {
  func placeholder(in context: Context) -> Memory { Memory(date: Date(), year: nil, image: nil, written: true) }

  func getSnapshot(in context: Context, completion: @escaping (Memory) -> Void) {
    completion(entries(until: Date())[0])
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Memory>) -> Void) {
    let now = Date()
    let calendar = Calendar.current
    let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
      ?? now.addingTimeInterval(3600)
    completion(Timeline(entries: entries(until: midnight), policy: .after(midnight)))
  }

  /// At least one.
  private func entries(until end: Date) -> [Memory] {
    let now = Date()
    guard let snapshot = Snapshot.of(now), let folder = Snapshot.folder else {
      return [Memory(date: now, year: nil, image: nil, written: false)]
    }
    let years = snapshot.onThisDay
    guard !years.isEmpty else { return [Memory(date: now, year: nil, image: nil, written: true)] }
    let hours = max(1, Int((end.timeIntervalSince(now) / 3600).rounded(.up)))
    return (0..<hours).map { hour in
      let shown = years[hour % years.count]
      return Memory(
        date: now.addingTimeInterval(TimeInterval(hour) * 3600), year: shown.year,
        image: folder.appendingPathComponent(shown.image), written: true)
    }
  }
}

struct OnThisDay: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "org.photolib.onThisDay", provider: OnThisDayTimeline()) { memory in
      OnThisDayView(memory: memory)
    }
    .configurationDisplayName("On this day")
    .description("Photos taken on this day in earlier years.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct OnThisDayView: View {
  let memory: Memory

  var body: some View {
    if #available(iOS 17.0, *) {
      label.containerBackground(for: .widget) { photo }
    } else {
      ZStack {
        photo
        label.padding()
      }
    }
  }

  private var label: some View {
    VStack {
      Spacer()
      HStack {
        if let year = memory.year {
          Text(verbatim: String(year)).font(.headline).foregroundStyle(.white).shadow(radius: 3)
        } else if memory.written {
          Text("No photos from this day in earlier years").font(.footnote)
        } else {
          Text("Open Photolib to see this day's photos").font(.footnote)
        }
        Spacer()
      }
    }
  }

  /// Fills the widget, cropped.
  private var photo: some View {
    Color(uiColor: .secondarySystemBackground)
      .overlay {
        if let path = memory.image?.path, let image = UIImage(contentsOfFile: path) {
          Image(uiImage: image).resizable().scaledToFill()
        }
      }
      .clipped()
  }
}
