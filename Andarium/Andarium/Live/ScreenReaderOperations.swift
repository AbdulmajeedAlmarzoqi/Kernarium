// SPDX-License-Identifier: GPL-2.0-or-later

import AndariumCore
import Foundation

/// TalkBack and eSpeak NG as the application carries them: two APKs under
/// `Accessibility/` in its bundle, which the target's "Bundle TalkBack" phase
/// copies from `.build/andarium-accessibility` when they are staged
/// (`scripts/stage-accessibility.py`). A build without them offers TalkBack
/// only to a guest whose system already has it.
nonisolated struct ScreenReaderPayload: Sendable {
    static let directory = "Accessibility"
    static let talkBackName = "TalkBack.apk"
    static let speechEngineName = "eSpeakNG.apk"

    let talkBack: URL
    let speechEngine: URL

    /// The APKs in `bundle`; nil unless both are there.
    static func carried(in bundle: Bundle = .main) -> ScreenReaderPayload? {
        guard let resources = bundle.resourceURL else { return nil }
        let root = resources.appending(path: directory, directoryHint: .isDirectory)
        let payload = ScreenReaderPayload(
            talkBack: root.appending(path: talkBackName), speechEngine: root.appending(path: speechEngineName))
        let files = FileManager.default
        guard files.isReadableFile(atPath: payload.talkBack.path),
              files.isReadableFile(atPath: payload.speechEngine.path) else { return nil }
        return payload
    }
}

nonisolated extension AdbGuestOperations {
    /// TalkBack in the guest; nil when the guest cannot be asked now.
    func screenReader() async -> ScreenReaderState? {
        guard let result = try? await shell(ScreenReader.stateCommand, limit: .seconds(15)) else { return nil }
        return ScreenReader.parse(result)
    }

    /// Turns TalkBack on or off in the guest whose state is `state`, and
    /// returns the state Android reports after.
    func setScreenReader(_ on: Bool, in state: ScreenReaderState) async throws -> ScreenReaderState {
        guard let command = ScreenReader.command(turningOn: on, in: state) else {
            throw AdbFailure(message: ScreenReaderWords.missing)
        }
        let result: ShellResult
        do {
            result = try await shell(command, limit: .seconds(30))
        } catch {
            throw AdbOperationRunner.presented(error, activity: .screenReader)
        }
        guard result.exitCode == 0 else {
            let said = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AdbFailure(message: said.isEmpty ? AdbFailure(.io(EIO), activity: .screenReader).message : said)
        }
        return await screenReader() ?? ScreenReader.state(afterTurningOn: on, state)
    }

    /// Installs what `payload` carries that the guest lacks, eSpeak NG first
    /// so that TalkBack has a voice from its first word, and makes eSpeak NG
    /// the speech engine when nobody has chosen one. Returns the state after;
    /// TalkBack is not turned on.
    func installScreenReader(
        _ payload: ScreenReaderPayload, in state: ScreenReaderState,
        update: @escaping @Sendable (BusyUpdate) -> Void
    ) async throws -> ScreenReaderState {
        // Sending eSpeak NG is the first third of the bar, TalkBack the rest
        // but the moment the settings take.
        if !state.speechEngineInstalled {
            update(BusyUpdate(detail: ScreenReaderWords.installingVoice))
            try await installApk(at: payload.speechEngine, sizeBytes: Self.size(of: payload.speechEngine)) { step in
                // The overlay can stop the TalkBack install that follows, so
                // this one's "no longer cancellable" is not passed on.
                update(BusyUpdate(progress: step.progress.map { $0 * 0.33 }))
            }
        }
        if !state.isInstalled {
            update(BusyUpdate(progress: 0.33, detail: ScreenReaderWords.installingTalkBack))
            try await installApk(at: payload.talkBack, sizeBytes: Self.size(of: payload.talkBack)) { step in
                update(BusyUpdate(progress: step.progress.map { 0.33 + $0 * 0.62 }, cancellable: step.cancellable))
            }
        }
        update(BusyUpdate(progress: 0.95, detail: ScreenReaderWords.turningOn, cancellable: false))
        _ = try? await shell(ScreenReader.speechEngineCommand, limit: .seconds(15))
        guard let after = await screenReader(), after.isInstalled else {
            throw AdbFailure(message: ScreenReaderWords.notFoundAfterInstall)
        }
        return after
    }

    /// Opens Android's Accessibility page on the guest's screen.
    func openAccessibilitySettings() async throws {
        do {
            _ = try await shell(ScreenReader.settingsCommand, limit: .seconds(15))
        } catch {
            throw AdbOperationRunner.presented(error, activity: .screenReader)
        }
    }

    private static func size(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
