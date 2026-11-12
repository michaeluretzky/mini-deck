// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Accelerate
import CoreMedia
import ScreenCaptureKit
import SwiftUI

/// Splits audio into five bands with a bank of band-pass filters and follows each band's loudness.
final class BandAnalyzer {
    static let centers: [Double] = [55, 170, 520, 1700, 5600]
    private var filters: [vDSP.Biquad<Float>] = []
    private var ceilings = [Float](repeating: 1e-4, count: BandAnalyzer.centers.count)
    private var shown = [Float](repeating: 0, count: BandAnalyzer.centers.count)
    private var rate: Double = 0

    private func design(rate: Double) {
        filters = Self.centers.compactMap { center in
            let w = 2 * Double.pi * min(center, rate * 0.45) / rate
            let alpha = sin(w) / (2 * 1.1)
            let a0 = 1 + alpha
            let coefficients = [alpha / a0, 0, -alpha / a0, (-2 * cos(w)) / a0, (1 - alpha) / a0]
            return vDSP.Biquad(coefficients: coefficients, channelCount: 1, sectionCount: 1, ofType: Float.self)
        }
        self.rate = rate
    }

    func process(_ samples: [Float], rate: Double) -> [Float] {
        if rate != self.rate || filters.count != Self.centers.count { design(rate: rate) }
        let overall = vDSP.rootMeanSquare(samples)
        for i in filters.indices {
            let band = filters[i].apply(input: samples)
            let energy = vDSP.rootMeanSquare(band)
            ceilings[i] = max(energy, ceilings[i] * 0.996, 1e-5)          // adapts to quiet and loud tracks
            var level: Float = overall < 0.001 ? 0 : min(1, energy / ceilings[i])
            level = powf(level, 1.4)
            shown[i] = level >= shown[i] ? level : shown[i] * 0.82 + level * 0.18   // rise fast, fall soft
        }
        return shown
    }
}

/// Listens only to the music app's sound through ScreenCaptureKit. Nothing is recorded or saved.
final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var session: SCStream?
    private let queue = DispatchQueue(label: "app.minideck.audio")
    private let analyzer = BandAnalyzer()
    private var lastSend: CFAbsoluteTime = 0
    private let onLevels: @Sendable ([Float]) -> Void
    private let onStop: @Sendable () -> Void
    private let bundle: String

    init(bundle: String, onLevels: @escaping @Sendable ([Float]) -> Void, onStop: @escaping @Sendable () -> Void) {
        self.onLevels = onLevels
        self.onStop = onStop
        self.bundle = bundle
    }

    func begin() async throws -> Bool {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first,
              let app = content.applications.first(where: { $0.bundleIdentifier == bundle }) else { return false }
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2                     // sound only; the picture is ignored
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        config.showsCursor = false
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        session = stream
        return true
    }

    func end() {
        let stream = session
        session = nil
        stream?.stopCapture { _ in }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop() }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, buffer.isValid else { return }
        var rate = 48_000.0
        if let format = CMSampleBufferGetFormatDescription(buffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee, asbd.mSampleRate > 0 {
            rate = asbd.mSampleRate
        }
        var mono: [Float] = []
        try? buffer.withAudioBufferList { list, _ in
            let channels = list.map { b in
                UnsafeBufferPointer(start: b.mData?.assumingMemoryBound(to: Float.self),
                                    count: Int(b.mDataByteSize) / MemoryLayout<Float>.stride)
            }
            guard let left = channels.first, left.count > 0 else { return }
            if channels.count > 1, channels[1].count == left.count {
                mono = vDSP.multiply(Float(0.5), vDSP.add(left, channels[1]))
            } else {
                mono = Array(left)
            }
        }
        guard !mono.isEmpty else { return }
        let levels = analyzer.process(mono, rate: rate)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastSend >= 1.0 / 30 {
            lastSend = now
            onLevels(levels)
        }
    }
}

@MainActor @Observable
final class Spectrum {
    enum Feed { case off, live, imitation }

    private(set) var feed: Feed = .off
    private(set) var bands = [Float](repeating: 0, count: BandAnalyzer.centers.count)

    @ObservationIgnored private var capture: AudioCapture?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var idleTimer: Task<Void, Never>?
    @ObservationIgnored private var retryAfter = Date.distantPast
    @ObservationIgnored private var bundle = ""

    /// Called whenever the setting, the play state or the followed app changes.
    func want(_ on: Bool, playing: Bool, bundle: String) {
        if bundle != self.bundle {
            self.bundle = bundle
            retryAfter = .distantPast
            close()
        }
        enabled = on
        guard on else {
            idleTimer?.cancel()
            idleTimer = nil
            close()
            feed = .off
            return
        }
        if feed == .off { feed = .imitation }
        if playing {
            idleTimer?.cancel()
            idleTimer = nil
            open()
        } else if capture != nil, idleTimer == nil {
            // stop listening a little after pausing (track changes briefly report "paused")
            idleTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.idleTimer = nil
                self.close()
            }
        }
    }

    private func open() {
        guard capture == nil, !opening, Date() >= retryAfter else { return }
        let store = UserDefaults.standard
        if !CGPreflightScreenCaptureAccess() && !store.bool(forKey: PrefKey.askedCapture) {
            store.set(true, forKey: PrefKey.askedCapture)
            CGRequestScreenCaptureAccess()
        }
        opening = true
        let cap = AudioCapture(bundle: bundle, onLevels: { [weak self] levels in Task { @MainActor in self?.receive(levels) } },
                               onStop: { [weak self] in Task { @MainActor in self?.lost() } })
        let wanted = bundle
        Task { [weak self] in
            let ok = (try? await cap.begin()) ?? false
            guard let self else { cap.end(); return }
            self.opening = false
            if ok && self.enabled && wanted == self.bundle {
                self.capture = cap
                self.feed = .live
            } else {
                cap.end()
                self.retryAfter = Date().addingTimeInterval(20)
                if self.enabled { self.feed = .imitation }
            }
        }
    }

    private func receive(_ levels: [Float]) {
        guard feed == .live else { return }
        bands = levels
    }

    private func lost() {
        capture = nil
        bands = bands.map { _ in 0 }
        if enabled { feed = .imitation }
    }

    private func close() {
        capture?.end()
        capture = nil
        bands = bands.map { _ in 0 }
        if enabled && feed == .live { feed = .imitation }
    }
}

/// Smooth pseudo-random motion used when live sound isn't available.
enum Imitation {
    static func levels(at t: Double) -> [Float] {
        (0..<BandAnalyzer.centers.count).map { i in
            let band = Double(i)
            let speed: Double = 2.2 + band * 0.6
            let phase: Double = t * speed + band * 17.3
            let level: Double = 0.12 + 0.88 * noise(phase)
            return Float(level)
        }
    }

    private static func hash(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 29
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }

    private static func noise(_ x: Double) -> Double {
        let i = Int(floor(x))
        let f = x - floor(x)
        let u = f * f * (3 - 2 * f)
        return hash(i) * (1 - u) + hash(i + 1) * u
    }
}
