import SwiftUI

@main
struct BlurApp: App {

    @State private var alarmCenter = AlarmCenter.shared
    @State private var alarmStore = AlarmStore()
    @State private var timerStore = TimerStore()
    @State private var stopwatch = StopwatchModel()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(alarmCenter)
                .environment(alarmStore)
                .environment(timerStore)
                .environment(stopwatch)
                // The design is light-mode only; this keeps it that way even if
                // the Info.plist style is ever changed.
                .preferredColorScheme(.light)
                .tint(Blur.pink)
                .task {
                    await alarmCenter.ensureAuthorized()
                    await alarmStore.reconcile()
                    timerStore.reconcile()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Re-assert scheduling every time we come back: this is what
                // makes an enabled toggle mean "this will actually ring".
                stopwatch.refreshAfterForeground()
                Task {
                    await alarmStore.reconcile()
                    timerStore.reconcile()
                }
            case .background:
                stopwatch.pauseDisplayForBackground()
            default:
                break
            }
        }
    }
}
