import SwiftUI
import UIKit

/// Three tabs, in the order the app is meant to be read: alarms first because
/// they're the thing you set and forget, timers next, stopwatch last.
struct RootView: View {

    @Environment(AlarmCenter.self) private var center

    @State private var selection: Screen = .alarms

    /// Deliberately not called `Tab` — that's SwiftUI's own type, and a nested
    /// enum of the same name shadows it inside this view.
    enum Screen: Hashable { case alarms, timer, stopwatch }

    var body: some View {
        @Bindable var center = center

        TabView(selection: $selection) {
            Tab("Alarms", systemImage: "alarm.fill", value: Screen.alarms) {
                AlarmsView()
            }
            Tab("Timer", systemImage: "timer", value: Screen.timer) {
                TimersView()
            }
            Tab("Stopwatch", systemImage: "stopwatch.fill", value: Screen.stopwatch) {
                StopwatchView()
            }
        }
        .tint(tintForSelection)
        .alert(
            center.lastError?.title ?? "Something Went Wrong",
            isPresented: Binding(
                get: { center.lastError != nil },
                set: { if !$0 { center.lastError = nil } }
            ),
            presenting: center.lastError
        ) { error in
            if case .notAuthorized = error {
                Button("Open Settings") { openSettings() }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { error in
            Text(error.message)
        }
    }

    /// The tab bar picks up the accent of whichever screen you're on, so the
    /// three accents each get a moment rather than fighting on one screen.
    private var tintForSelection: Color {
        switch selection {
        case .alarms:    return Blur.pink
        case .timer:     return Blur.green
        case .stopwatch: return Blur.yellow
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
