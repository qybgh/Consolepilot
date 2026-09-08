import Foundation

struct DependencyContainer: Sendable {
    let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }
}
