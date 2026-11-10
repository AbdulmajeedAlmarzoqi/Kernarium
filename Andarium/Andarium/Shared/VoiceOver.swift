// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

/// What Andarium tells VoiceOver of its own accord: a new screen, an operation
/// that began or ended, TalkBack turning on or off. Each call does nothing
/// while VoiceOver is off.
enum VoiceOver {
    /// Speaks `text`. A queued announcement waits for what VoiceOver is
    /// saying; otherwise it interrupts it.
    static func announce(_ text: String, queued: Bool = false) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let words = NSAttributedString(
            string: text, attributes: [.accessibilitySpeechQueueAnnouncement: queued])
        UIAccessibility.post(notification: .announcement, argument: words)
    }

    /// The screen changed as a whole: VoiceOver moves to its first element,
    /// and says `text` instead when it is given.
    static func screenChanged(_ text: String? = nil) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .screenChanged, argument: text)
    }
}

/// The words of TalkBack in the side keys, the busy overlay and the guest's
/// display.
nonisolated enum ScreenReaderWords {
    static let name = "TalkBack"
    static let keyLabel = "Accessibility"
    static let keyHint = "Turns TalkBack, Android\u{2019}s screen reader, on or off"
    static let settings = "Accessibility settings"
    static let settingsDetail = "Opens Android\u{2019}s accessibility settings"

    static let installTitle = "Installing TalkBack"
    static let installFailure = "TalkBack not installed"
    static let installingVoice = "Installing the eSpeak NG voice\u{2026}"
    static let installingTalkBack = "Installing TalkBack\u{2026}"
    static let turningOn = "Turning TalkBack on\u{2026}"
    static let installedTitle = "TalkBack is on"
    static let installedDetail = "Android speaks what you touch: double-tap to open an item, and swipe right or left to move between items. Turn TalkBack off with the Accessibility key of the side keys."
    static let turningOnForVoiceOver = "VoiceOver is on, so Andarium is turning on TalkBack, Android\u{2019}s screen reader."
    static let missing = "Android has no TalkBack to turn on."
    static let notFoundAfterInstall = "Android didn\u{2019}t list TalkBack after the install. Try again."

    static func changeFailure(turningOn on: Bool) -> String {
        on ? "TalkBack didn\u{2019}t turn on" : "TalkBack didn\u{2019}t turn off"
    }

    static func announcement(on: Bool) -> String { on ? "TalkBack on" : "TalkBack off" }

    /// What VoiceOver calls Android's screen, and what it says of it.
    static let displayLabel = "Android screen"
    static let displayHintDirect = "TalkBack is on. Touches go straight to Android, and TalkBack speaks."
    static let displayHint = "Turn on TalkBack with the side keys\u{2019} Accessibility key to use Android with a screen reader."
}
