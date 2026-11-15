// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts. They use the standard hot-key service,
/// so no Accessibility or Input Monitoring permission is needed, and no other keys are read.
@MainActor
final class HotKeys {
    enum Action: UInt32, CaseIterable {
        case playPause = 1, next, previous, togglePlayer

        var title: String {
            switch self {
            case .playPause: "Play or Pause"
            case .next: "Next Track"
            case .previous: "Previous Track"
            case .togglePlayer: "Show or Hide Player"
            }
        }

        /// Control-Option plus a letter or bracket. Arrow keys are left alone because
        /// window managers often use Control-Option-arrows.
        var keyCode: UInt32 {
            switch self {
            case .playPause: UInt32(kVK_ANSI_P)
            case .next: UInt32(kVK_ANSI_RightBracket)
            case .previous: UInt32(kVK_ANSI_LeftBracket)
            case .togglePlayer: UInt32(kVK_ANSI_M)
            }
        }

        var keys: String {
            switch self {
            case .playPause: "⌃⌥P"
            case .next: "⌃⌥]"
            case .previous: "⌃⌥["
            case .togglePlayer: "⌃⌥M"
            }
        }
    }

    /// The Carbon callback can't capture context, so it reaches the active instance here.
    nonisolated(unsafe) private static var current: HotKeys?
    private static let signature: OSType = 0x4D44_4B31 // "MDK1"

    var perform: ((Action) -> Void)?
    private(set) var unavailable: [Action] = []
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    var isEnabled: Bool { !refs.isEmpty }

    func enable() {
        guard refs.isEmpty else { return }
        Self.current = self
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == HotKeys.signature,
                      let action = HotKeys.Action(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKeys.current?.perform?(action) }
                }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        unavailable = []
        for action in Action.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            let status = RegisterEventHotKey(action.keyCode, UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { unavailable.append(action) }
        }
    }

    func disable() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []
        unavailable = []
    }
}
