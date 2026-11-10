// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing

@testable import AndariumCore

struct ScreenReaderTests {
    private let talkBack = ScreenReader.services[0]
    private let googleTalkBack = ScreenReader.services[1]
    private let switchAccess = "com.example.switch/.SwitchService"

    // MARK: Reading

    @Test func readsAGuestWithTalkBackOn() throws {
        let output = """
            package:com.android.talkback
            package:com.reecedunn.espeak
            services=\(switchAccess):\(talkBack)
            """
        let state = try #require(ScreenReader.parse(output))
        #expect(state.installedService == talkBack)
        #expect(state.enabledServices == [switchAccess, talkBack])
        #expect(state.speechEngineInstalled)
        #expect(state.isOn)
    }

    @Test func readsAGuestThatNeverHadAService() throws {
        let state = try #require(ScreenReader.parse("services=null\n"))
        #expect(state.installedService == nil)
        #expect(state.enabledServices.isEmpty)
        #expect(!state.speechEngineInstalled)
        #expect(!state.isOn && !state.isInstalled)
    }

    @Test func recognisesGooglesTalkBack() throws {
        let state = try #require(ScreenReader.parse("package:com.google.android.marvin.talkback\nservices=\n"))
        #expect(state.installedService == googleTalkBack)
        #expect(!state.isOn)
    }

    @Test func prefersTheCarriedBuildWhenBothAreInstalled() throws {
        let output = "package:com.google.android.marvin.talkback\npackage:com.android.talkback\nservices=\(googleTalkBack)"
        let state = try #require(ScreenReader.parse(output))
        #expect(state.installedService == talkBack)
        // The Google build is on, not the one the switch drives.
        #expect(!state.isOn)
    }

    @Test func anotherPackageNamedLikeTalkBackIsNotTalkBack() throws {
        let state = try #require(ScreenReader.parse("package:com.example.talkbackhelper\nservices=null"))
        #expect(!state.isInstalled)
    }

    @Test func outputWithoutTheSettingIsNotAState() {
        #expect(ScreenReader.parse("") == nil)
        #expect(ScreenReader.parse("package:com.android.talkback\n") == nil)
        #expect(ScreenReader.parse(ShellResult(stdout: Data("services=null".utf8), exitCode: 1)) == nil)
        #expect(ScreenReader.parse(ShellResult(stdout: Data("services=null".utf8), exitCode: 0)) != nil)
    }

    @Test func theListIgnoresEmptyEntries() {
        #expect(ScreenReader.serviceList(" null \n") == [])
        #expect(ScreenReader.serviceList("a/.A::b/.B:") == ["a/.A", "b/.B"])
    }

    // MARK: Turning on and off

    @Test func turningOnAddsTalkBackAfterTheOtherServices() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [switchAccess], speechEngineInstalled: true)
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command == "settings put secure enabled_accessibility_services '\(switchAccess):\(talkBack)' && settings put secure accessibility_enabled 1")
        #expect(ScreenReader.state(afterTurningOn: true, state).enabledServices == [switchAccess, talkBack])
    }

    @Test func turningOnTwiceDoesNotListTalkBackTwice() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack], speechEngineInstalled: true)
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command.contains("'\(talkBack)'"))
        #expect(ScreenReader.state(afterTurningOn: true, state).enabledServices == [talkBack])
    }

    @Test func turningOffKeepsTheOtherServicesOn() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack, switchAccess], speechEngineInstalled: true)
        let command = try #require(ScreenReader.command(turningOn: false, in: state))
        #expect(command == "settings put secure enabled_accessibility_services '\(switchAccess)' && settings put secure accessibility_enabled 1")
        #expect(!ScreenReader.state(afterTurningOn: false, state).isOn)
    }

    @Test func turningOffTheLastServiceTurnsAccessibilityOff() throws {
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack, googleTalkBack], speechEngineInstalled: false)
        let command = try #require(ScreenReader.command(turningOn: false, in: state))
        #expect(command == "settings delete secure enabled_accessibility_services >/dev/null; settings put secure accessibility_enabled 0")
        #expect(ScreenReader.state(afterTurningOn: false, state).enabledServices.isEmpty)
    }

    @Test func thereIsNothingToTurnOnWithoutTalkBack() {
        let state = ScreenReaderState(installedService: nil, enabledServices: [], speechEngineInstalled: false)
        #expect(ScreenReader.command(turningOn: true, in: state) == nil)
    }

    @Test func aServiceNameCannotBreakOutOfTheCommand() throws {
        let hostile = "x/.Y';reboot;'"
        let state = ScreenReaderState(installedService: talkBack, enabledServices: [hostile], speechEngineInstalled: true)
        let command = try #require(ScreenReader.command(turningOn: true, in: state))
        #expect(command.contains("'x/.Y'\\'';reboot;'\\''"))
    }

    @Test func theSpeechEngineIsChosenOnlyWhenNoneIs() {
        #expect(ScreenReader.speechEngineCommand.contains("= null ]"))
        #expect(ScreenReader.speechEngineCommand.hasSuffix("; true"))
    }

    // MARK: The Accessibility key

    @Test func theKeyOffersWhatTheGuestHas() {
        let off = ScreenReaderState(installedService: talkBack, enabledServices: [], speechEngineInstalled: true)
        let on = ScreenReaderState(installedService: talkBack, enabledServices: [talkBack], speechEngineInstalled: true)
        let none = ScreenReaderState(installedService: nil, enabledServices: [], speechEngineInstalled: false)
        #expect(ScreenReaderOffer(state: nil, carriesScreenReader: true) == .unknown)
        #expect(ScreenReaderOffer(state: on, carriesScreenReader: false) == .on)
        #expect(ScreenReaderOffer(state: off, carriesScreenReader: false) == .off)
        #expect(ScreenReaderOffer(state: none, carriesScreenReader: true) == .installable)
        #expect(ScreenReaderOffer(state: none, carriesScreenReader: false) == .unavailable)
    }

    @Test func aFirstStartUnderVoiceOverTurnsTalkBackOn() {
        #expect(ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .installable))
        #expect(ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .off))
        // Already on, nothing to install from, or not known yet: nothing to do.
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .on))
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .unavailable))
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: true, offer: .unknown))
        // Without VoiceOver, or on a later start, the person decides.
        #expect(!ScreenReader.turnsOnByItself(firstStart: true, voiceOverRunning: false, offer: .installable))
        #expect(!ScreenReader.turnsOnByItself(firstStart: false, voiceOverRunning: true, offer: .off))
    }

    @Test func onlyAKnownStateCanBeChanged() {
        #expect(ScreenReaderOffer.on.canChange && ScreenReaderOffer.off.canChange && ScreenReaderOffer.installable.canChange)
        #expect(!ScreenReaderOffer.unknown.canChange && !ScreenReaderOffer.unavailable.canChange)
        #expect(ScreenReaderOffer.on.isOn && !ScreenReaderOffer.installable.isOn)
        #expect(ScreenReaderOffer.on.detail == nil && ScreenReaderOffer.installable.detail != nil)
    }
}
