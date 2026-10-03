#!/usr/bin/env python3
"""Exercise the production audio coordinator with a deterministic session double.
Runs on macOS without a simulator, recording permission or audible output.
"""
from pathlib import Path
import subprocess
import tempfile
import platform

root = Path(__file__).resolve().parents[1]
source = (root / 'Moments/Utilities/MomentsAudioSession.swift').read_text()
source = source.replace('import AVFoundation', 'import Foundation')
mock = r'''
import Foundation
import Synchronization
let AVAudioSessionInterruptionTypeKey = "type"
let AVAudioSessionRouteChangeReasonKey = "reason"
final class AVAudioSession: Sendable {
    enum Category: String, Sendable { case ambient, soloAmbient, playback, playAndRecord, record }
    enum Mode: String, Sendable { case `default`, moviePlayback, voiceChat }
    struct CategoryOptions: OptionSet, Sendable { let rawValue: Int }
    struct SetActiveOptions: OptionSet, Sendable {
        let rawValue: Int
        static let notifyOthersOnDeactivation = Self(rawValue: 1)
    }
    enum InterruptionType: UInt { case began = 1, ended = 0 }
    enum RouteChangeReason: UInt { case oldDeviceUnavailable = 2 }
    static let interruptionNotification = Notification.Name("interruption")
    static let routeChangeNotification = Notification.Name("route")
    static let mediaServicesWereResetNotification = Notification.Name("reset")
    private struct State {
        var category = Category.soloAmbient
        var mode = Mode.default
        var options = CategoryOptions(rawValue: 0)
        var active = false
        var deactivations = 0
        var failNextActivation = false
    }
    private let state = Mutex(State())
    static let instance = AVAudioSession()
    static func sharedInstance() -> AVAudioSession { instance }
    var category: Category { state.withLock { $0.category } }
    var mode: Mode { state.withLock { $0.mode } }
    var categoryOptions: CategoryOptions { state.withLock { $0.options } }
    var active: Bool { state.withLock { $0.active } }
    var deactivations: Int { state.withLock { $0.deactivations } }
    func failNextActivation() { state.withLock { $0.failNextActivation = true } }
    func setCategory(_ category: Category, mode: Mode, options: CategoryOptions) throws {
        state.withLock { $0.category = category; $0.mode = mode; $0.options = options }
    }
    func setActive(_ active: Bool, options: SetActiveOptions = []) throws {
        try state.withLock { value in
            if active && value.failNextActivation {
                value.failNextActivation = false
                throw NSError(domain: "AudioSessionTest", code: 1)
            }
            value.active = active
            if !active { value.deactivations += 1 }
        }
    }
}
'''
tests = r'''
@main struct Tests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func main() async {
        let session = AVAudioSession.sharedInstance()
        await MomentsAudioSession.prepareMutedPlayback()
        check(session.category == .ambient && !session.active, "Muted preparation must not activate audio")
        let movie = MomentsAudioSessionLease()
        let recording = MomentsAudioSessionLease()
        let secondary = MomentsAudioSessionLease()
        let movieStarted = await movie.activate(mode: .moviePlayback)
        check(movieStarted && session.category == .playback, "Explicit playback should claim audio")
        let recordingStarted = await recording.activate(category: .playAndRecord)
        check(recordingStarted && session.category == .playAndRecord, "Recording should retain its input category")
        let secondaryStarted = await secondary.activate(category: .ambient)
        check(secondaryStarted && session.category == .playAndRecord, "Secondary audio must not replace recording configuration")
        let count = session.deactivations
        movie.deactivate()
        secondary.deactivate()
        await MomentsAudioSession.prepareMutedPlayback() // flush the production queue
        check(session.active && session.category == .playAndRecord && session.deactivations == count,
              "Closing older producers must not deactivate the current recording")
        recording.deactivate()
        await MomentsAudioSession.prepareMutedPlayback()
        check(!session.active && session.category == .ambient, "Last release must restore passive mixing")
        let pending = Task { await movie.activate() }
        pending.cancel()
        let pendingStarted = await pending.value
        await MomentsAudioSession.prepareMutedPlayback()
        check(!pendingStarted && !session.active, "Cancelled work must not claim the audio session")
        let resumed = await movie.activate()
        check(resumed, "A released producer should be able to play again")
        session.failNextActivation()
        let failed = await secondary.activate(category: .playAndRecord)
        check(!failed && session.category == .playback && session.active,
              "Activation failure must preserve the existing owner's configuration")
        movie.deactivate()
        secondary.deactivate()
        await MomentsAudioSession.prepareMutedPlayback()
        check(!session.active, "Failed producers must not leave a retained claim")
        let owner = UUID()
        let newest = await MomentsAudioSession.activate(owner: owner, generation: 42, category: .playback,
                                                        mode: .default, options: [], isCurrent: { true })
        check(newest, "Newest generation should activate")
        MomentsAudioSession.deactivate(owner: owner, throughGeneration: 41)
        await MomentsAudioSession.prepareMutedPlayback()
        check(session.active, "A delayed release must not remove a newer generation of the same producer")
        MomentsAudioSession.deactivate(owner: owner, throughGeneration: 42)
        await MomentsAudioSession.prepareMutedPlayback()
        check(!session.active, "Current generation should release normally")
        print("PASS: muted startup, playback, recording priority, independent release, cancellation, resume, rollback and delayed release")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='moments-audio-tests-') as directory:
    file = Path(directory) / 'AudioSessionTests.swift'
    binary = Path(directory) / 'audio-tests'
    file.write_text(mock + '\n' + source + '\n' + tests)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-target', platform.machine() + '-apple-macosx15.0', '-module-cache-path', str(Path(directory) / 'modules'), str(file), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
