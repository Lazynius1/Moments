import Foundation
import os

/// Signposts para perfilar feed, vídeo y stories en Instruments.
enum PerformanceSignposts {
    private static let log = OSLog(subsystem: "com.moments.app", category: "Performance")

    static func begin(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: log, name: name, signpostID: id)
    }

    static func end(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }

    @discardableResult
    static func makeID() -> OSSignpostID {
        OSSignpostID(log: log)
    }
}
