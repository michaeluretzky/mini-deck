// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Window integration checks use their own executable's defaults, never the app's data.
import AppKit
import SwiftUI

@main
struct WindowChecks {
    @MainActor
    static func main() throws {
        precondition(Bundle.main.bundleIdentifier != "app.minideck.player")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = UserDefaults.standard
        let keys = [PrefKey.anchor, "minideck.restingFrame", "minideck.restingArea",
                    "minideck.homeScreen", "minideck.horizontalAnchor", "minideck.verticalAnchor"]
        for key in keys { store.removeObject(forKey: key) }
        defer { for key in keys { store.removeObject(forKey: key) } }
        var checks = 0
        var failures = 0
        func expect(_ value: Bool, _ message: String) {
            checks += 1
            if !value { failures += 1; print("FAIL: \(message)") }
        }
        func build() -> (Stage, NSWindow) {
            let existing = Set(app.windows.map(\.windowNumber))
            let stage = Stage()
            stage.build(Text("Mini Deck layout checks").padding(), scroll: { _ in false }, pointer: { _ in })
            let window = app.windows.first { $0 is DeckPanel && !existing.contains($0.windowNumber) }!
            return (stage, window)
        }
        let (stage, window) = build()
        guard let display = window.screen ?? NSScreen.main else { fatalError("No test display") }
        let area = WindowGeometry.playArea(visibleFrame: display.visibleFrame, gap: Metrics.screenGap)
        for corner in Corner.allCases {
            stage.fit(height: 218, width: 488, growDown: false)
            stage.park(at: corner)
            let normal = window.frame
            expect(area.contains(normal), "\(corner): full normal glow inside work area")
            for _ in 0..<10 {
                stage.fit(height: 163, width: 340, growDown: false)
                let compact = window.frame
                switch corner {
                case .topLeading, .bottomLeading:
                    expect(compact.minX == normal.minX, "\(corner): left edge preserved")
                case .top, .bottom:
                    expect(compact.midX == normal.midX, "\(corner): center preserved")
                case .topTrailing, .bottomTrailing:
                    expect(compact.maxX == normal.maxX, "\(corner): right edge preserved")
                }
                stage.fit(height: min(700, area.height), width: 340, growDown: true)
                expect(area.contains(window.frame), "\(corner): expanded glow inside work area")
                stage.settle()
                stage.fit(height: 163, width: 340, growDown: false)
                expect(window.frame == compact, "\(corner): settle while expanded does not overwrite rest position")
                stage.fit(height: 218, width: 488, growDown: false)
                expect(window.frame == normal, "\(corner): round trip does not drift")
            }
        }
        // Reported issue: switching from compact to normal, AppKit widened the window from
        // its left edge before fit() ran, and fit() skipped the move because the size matched.
        for corner in Corner.allCases {
            stage.fit(height: 218, width: 488, growDown: false)
            stage.park(at: corner)
            let normal = window.frame
            stage.fit(height: 163, width: 340, growDown: false)
            let compact = window.frame
            window.setFrame(NSRect(x: compact.minX, y: compact.maxY - 218, width: 488, height: 218), display: false)
            stage.fit(height: 218, width: 488, growDown: false)
            expect(window.frame == normal, "\(corner): pre-widened window returns to its anchored normal frame")
            expect(area.contains(window.frame), "\(corner): pre-widened window stays on screen")
            window.setFrame(NSRect(x: normal.minX, y: normal.maxY - 163, width: 340, height: 163), display: false)
            stage.fit(height: 163, width: 340, growDown: false)
            expect(window.frame == compact, "\(corner): pre-narrowed window returns to its anchored compact frame")
        }
        // The hosting view must not resize the window when the card's width changes.
        expect(window.contentView.map { type(of: $0) == NSView.self && $0.subviews.count == 1 } ?? false,
               "window size is owned by a plain container")

        // Reported issue: a double-click starts a tiny drag, then the size switch
        // rebuilds the card before the drag ends. The card must stay on screen.
        stage.fit(height: 163, width: 340, growDown: false)
        stage.park(at: .topTrailing)
        let compactRight = window.frame
        stage.dragMoved()
        stage.fit(height: 218, width: 488, growDown: false)
        expect(area.contains(window.frame), "interrupted drag: normal view stays on screen")
        expect(window.frame.maxX == compactRight.maxX, "interrupted drag: right edge preserved")
        stage.dragMoved()
        stage.cancelDrag()
        stage.fit(height: 163, width: 340, growDown: false)
        expect(window.frame == compactRight, "cancelled drag: compact returns to the same place")
        for corner in Corner.allCases {
            stage.park(at: corner)
            for size in [(218.0, 488.0), (163.0, 340.0), (218.0, 488.0)] {
                stage.dragMoved()
                stage.fit(height: size.0, width: size.1, growDown: false)
                expect(area.contains(window.frame), "\(corner): size switch during drag stays on screen")
            }
        }
        // Dragging past any edge must stop at the margin, both during and after the drag.
        for size in [(218.0, 488.0), (163.0, 340.0)] {
            stage.fit(height: size.0, width: size.1, growDown: false)
            for push in [CGPoint(x: 3000, y: 0), CGPoint(x: -3000, y: 0), CGPoint(x: 0, y: 3000),
                         CGPoint(x: 0, y: -3000), CGPoint(x: 3000, y: 3000), CGPoint(x: -3000, y: -3000)] {
                stage.park(at: .top)
                let start = NSPoint(x: window.frame.midX, y: window.frame.midY)
                stage.dragMoved(to: start)
                stage.dragMoved(to: NSPoint(x: start.x + push.x / 2, y: start.y + push.y / 2))
                expect(area.contains(window.frame), "drag \(push) width \(size.1): stays on screen mid-drag")
                stage.dragMoved(to: NSPoint(x: start.x + push.x, y: start.y + push.y))
                expect(area.contains(window.frame), "drag \(push) width \(size.1): stays on screen at the edge")
                stage.dragEnded()
                expect(area.contains(window.frame), "drag \(push) width \(size.1): stays on screen after release")
            }
        }
        stage.fit(height: 218, width: 488, growDown: false)
        stage.park(at: .topTrailing)

        let saved = window.frame
        stage.hide()
        let (reopened, reopenedWindow) = build()
        expect(reopenedWindow.frame == saved, "relaunch restores complete resting frame")
        reopened.hide()

        // Reproduce the reported gap with a legacy position, outside exact edge snapping.
        for key in keys { store.removeObject(forKey: key) }
        let legacy = CGRect(x: area.maxX - 488 - 24, y: area.maxY - 218 - 70, width: 488, height: 218)
        store.set(NSStringFromPoint(CGPoint(x: legacy.minX, y: legacy.maxY)), forKey: PrefKey.anchor)
        let (migrated, migratedWindow) = build()
        migrated.fit(height: 218, width: 488, growDown: false)
        let before = migratedWindow.frame
        migrated.fit(height: 163, width: 340, growDown: false)
        expect(migratedWindow.frame.maxX == before.maxX, "legacy off-snap right gap preserved")
        expect(migratedWindow.frame.maxY == before.maxY, "legacy off-snap top gap preserved")
        let compactSaved = migratedWindow.frame
        migrated.hide()
        let (compactReopened, compactWindow) = build()
        expect(compactWindow.frame == compactSaved, "compact relaunch preserves size and side gap")
        compactReopened.hide()

        // Optional preview uses the actual production component and synthetic fixtures.
        if let index = CommandLine.arguments.firstIndex(of: "--preview"), index + 1 < CommandLine.arguments.count {
            var report = ListeningReport()
            report.song.add([StatTile(value: "53", caption: "12,345 songs heard", symbol: "play.circle",
                                     supplement: "plays")], from: "Preview")
            report.artist.add([StatTile(value: "219", caption: "2,345 artists heard", symbol: "play.circle",
                                       supplement: "plays")], from: "Preview")
            report.album.add([StatTile(value: "86", caption: "6,789 albums heard", symbol: "play.circle",
                                      supplement: "plays")], from: "Preview")
            let view = VStack(alignment: .leading, spacing: 10) {
                Heading(text: "Your Spotify")
                SummaryRow(report: report, tint: Color(red: 0.55, green: 0.52, blue: 0.9))
                Text("Layout preview · sample data").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(12).frame(width: 448)
            .background(Color(red: 0.16, green: 0.16, blue: 0.23))
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Preview rendering failed")
            }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        // Notch preview: closed and open, on a 13-inch MacBook Air sized notch, with sample data.
        if let index = CommandLine.arguments.firstIndex(of: "--notch-preview"), index + 1 < CommandLine.arguments.count {
            let deck = Deck()
            let art = NSImage(size: NSSize(width: 168, height: 168), flipped: false) { rect in
                NSGradient(colors: [NSColor(red: 0.95, green: 0.55, blue: 0.3, alpha: 1),
                                    NSColor(red: 0.45, green: 0.25, blue: 0.7, alpha: 1)])?.draw(in: rect, angle: -60)
                return true
            }
            deck.preview(Snapshot(source: .spotify, state: .paused, title: "Sample Song Title", artist: "Sample Artist",
                                  album: "Sample Album", trackID: "spotify:track:sample", position: 74, length: 212), cover: art)
            let notchSize = CGSize(width: 185, height: 32)
            func frame(_ open: Bool) -> some View {
                let state = NotchState()
                state.notch = notchSize
                state.expanded = open
                state.open = CGSize(width: NotchGeometry.expandedWidth, height: notchSize.height + NotchGeometry.expandedBody)
                return ZStack(alignment: .top) {
                    // Menu bar strip and the camera notch, for context.
                    Rectangle().fill(Color(white: 0.85).opacity(0.25)).frame(height: notchSize.height)
                    NotchRoot(state: state, deck: deck, pointer: Pointer(), spectrum: Spectrum(), soundBars: true,
                              actions: NotchActions())
                }
                .frame(width: 560, height: open ? 176 : 56, alignment: .top)
                .background(LinearGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.5, green: 0.35, blue: 0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            let view = VStack(spacing: 14) { frame(false); frame(true) }
                .padding(14).background(Color(white: 0.1)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Notch preview rendering failed")
            }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        // Animation frames for the README: the notch opening on the same spring the app uses.
        if let index = CommandLine.arguments.firstIndex(of: "--notch-frames"), index + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let deck = Deck()
            let art = NSImage(size: NSSize(width: 168, height: 168), flipped: false) { rect in
                NSGradient(colors: [NSColor(red: 0.95, green: 0.55, blue: 0.3, alpha: 1),
                                    NSColor(red: 0.45, green: 0.25, blue: 0.7, alpha: 1)])?.draw(in: rect, angle: -60)
                return true
            }
            deck.preview(Snapshot(source: .spotify, state: .paused, title: "Sample Song Title", artist: "Sample Artist",
                                  album: "Sample Album", trackID: "spotify:track:sample", position: 74, length: 212), cover: art)
            let notch = CGSize(width: 185, height: 32)
            let open = CGSize(width: NotchGeometry.expandedWidth, height: notch.height + NotchGeometry.expandedBody)
            let flare = NotchGeometry.flare
            let state = NotchState()
            state.notch = notch
            state.open = open
            // Damped spring with response 0.28 s and damping 0.8, sampled at 30 frames a second.
            func spring(_ t: Double) -> Double {
                let w = 2 * Double.pi / 0.28, z = 0.8, wd = w * (1 - z * z).squareRoot()
                return 1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
            }
            for frameIndex in 0..<16 {
                let p = CGFloat(spring(Double(frameIndex) / 30))
                let closedWidth = notch.width + 2 * NotchGeometry.wing
                let width = closedWidth + (open.width - closedWidth) * p + 2 * flare
                let height = notch.height + (open.height - notch.height) * p
                let bottom = min(10, notch.height / 3) + (24 - min(10, notch.height / 3)) * p
                let view = ZStack(alignment: .top) {
                    Rectangle().fill(Color(white: 0.85).opacity(0.25)).frame(height: notch.height)
                    ZStack(alignment: .top) {
                        NotchOutline(bottom: bottom).fill(Color.black).frame(width: width, height: height)
                        if frameIndex == 0 {
                            NotchWings(deck: deck, spectrum: Spectrum(), soundBars: true, height: notch.height, gap: notch.width)
                        } else {
                            NotchPlayer(state: state, deck: deck, pointer: Pointer(), spectrum: Spectrum(), soundBars: true,
                                        actions: NotchActions())
                                .frame(width: open.width, height: open.height, alignment: .top)
                                .scaleEffect(0.55 + 0.45 * min(1, p), anchor: .top)
                                .opacity(Double(min(1, p * 1.4)))
                        }
                    }
                    .mask(alignment: .top) { NotchOutline(bottom: bottom).frame(width: width, height: height) }
                    .frame(width: open.width + 2 * flare, height: open.height, alignment: .top)
                }
                .frame(width: 560, height: 176, alignment: .top)
                .background(LinearGradient(colors: [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.5, green: 0.35, blue: 0.45)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    fatalError("Notch frame rendering failed")
                }
                try png.write(to: folder.appendingPathComponent(String(format: "frame%02d.png", frameIndex)))
            }
        }
        print("\(checks - failures)/\(checks) native window checks passed")
        if failures > 0 { exit(1) }
    }
}
