//
//  HomeViewModel.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Observation
import Speech
import Combine
import Accelerate

struct LocaleOption: Identifiable {
    let identifier: String
    let label: String

    var id: String { identifier }
}

enum VoiceDetectorMode: String, CaseIterable, Identifiable {
    case original = "ChatGPT" // chatgpt
    case rms = "RMS (vDSP)" // get from Transcriber library

    var id: String { rawValue }
}

@MainActor
final class HomeViewModel: NSObject, ObservableObject {
    enum VoiceDetectorMode: String, CaseIterable, Identifiable {
        case original = "Original"
        case rms = "RMS (vDSP)"

        var id: String { rawValue }
    }

    static let supportedLocales: [LocaleOption] = [
        LocaleOption(identifier: "ms-MY", label: "Malay (MY)"),
        LocaleOption(identifier: "en-US", label: "English (US)"),
        LocaleOption(identifier: "zh-CN", label: "Chinese (Simplified)"),
        LocaleOption(identifier: "zh-TW", label: "Chinese (Traditional)"),
        LocaleOption(identifier: "ta-IN", label: "Tamil")
    ]

    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var endOfUtteranceTimeout: Double = 2.0
    @Published var maxSpeakingDuration: Double = 8.0
    @Published var maxSpeakingRemaining: Double?
    @Published var endOfUtteranceRemaining: Double?
    @Published var voiceDetectorMode: VoiceDetectorMode = .original
    @Published var selectedLocaleIdentifier: String = "en-US" {
        didSet {
            updateRecognizerLocale()
        }
    }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var endOfUtteranceTicker: DispatchSourceTimer?
    private var lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
    private var recordingStartTime: CFAbsoluteTime?
    private var silenceStartTime: CFAbsoluteTime?

    override init() {
        super.init()
        configureDefaultLocale()
        updateRecognizerLocale()
        Task {
            await requestPermissions()
        }
    }

    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        isAuthorized = speechStatus == .authorized && micGranted
        if !isAuthorized {
            errorMessage = "Please enable Speech Recognition and Microphone access in Settings."
        } else {
            errorMessage = nil
        }
    }

    func toggleRecording() {
        if isListening {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard isAuthorized else {
            errorMessage = "Permissions are required before recording."
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer is not available right now."
            return
        }

        do {
            try configureAudioSession()
            try beginRecognition(with: speechRecognizer)
            isListening = true
            errorMessage = nil
        } catch {
            stopRecording()
            errorMessage = error.localizedDescription
        }
    }

    private func configureDefaultLocale() {
        let currentIdentifier = Locale.current.identifier
        let supported = Set(Self.supportedLocales.map(\.identifier))
        if supported.contains(currentIdentifier) {
            selectedLocaleIdentifier = currentIdentifier
        }
    }

    private func updateRecognizerLocale() {
        if isListening {
            stopRecording()
        }
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLocaleIdentifier))
    }

    func stopRecording() {
        stopEndOfUtteranceTicker()
        recordingStartTime = nil
        maxSpeakingRemaining = nil
        silenceStartTime = nil
        endOfUtteranceRemaining = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func beginRecognition(with recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }

        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let detectorMode = voiceDetectorMode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            let hasVoice = Self.hasVoiceActivity(in: buffer, mode: detectorMode)
            Task { @MainActor [weak self] in
                self?.updateVoiceActivity(hasVoice: hasVoice)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        maxSpeakingRemaining = maxSpeakingDuration
        lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
        silenceStartTime = nil
        endOfUtteranceRemaining = nil
        startEndOfUtteranceTicker()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.transcript = result.bestTranscription.formattedString
            }

            if let error {
                self.errorMessage = error.localizedDescription
            }

            if error != nil || (result?.isFinal ?? false) {
                self.stopRecording()
            }
        }
    }

    private func updateVoiceActivity(hasVoice: Bool) {
        guard isListening else { return }
        if hasVoice {
            lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
            silenceStartTime = nil
            endOfUtteranceRemaining = nil
        } else if silenceStartTime == nil {
            silenceStartTime = CFAbsoluteTimeGetCurrent()
            endOfUtteranceRemaining = endOfUtteranceTimeout
        }
    }

    private func startEndOfUtteranceTicker() {
        stopEndOfUtteranceTicker()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, self.isListening else { return }
            let now = CFAbsoluteTimeGetCurrent()

            if let recordingStartTime = self.recordingStartTime {
                let speakingElapsed = now - recordingStartTime
                self.maxSpeakingRemaining = max(0, self.maxSpeakingDuration - speakingElapsed)
                if speakingElapsed >= self.maxSpeakingDuration {
                    self.stopRecording()
                    return
                }
            }

            if let silenceStartTime = self.silenceStartTime {
                let silenceElapsed = now - silenceStartTime
                let remaining = max(0, self.endOfUtteranceTimeout - silenceElapsed)
                self.endOfUtteranceRemaining = remaining
                if remaining <= 0 {
                    self.stopRecording()
                }
            }
        }
        endOfUtteranceTicker = timer
        timer.resume()
    }

    private func stopEndOfUtteranceTicker() {
        endOfUtteranceTicker?.cancel()
        endOfUtteranceTicker = nil
    }

    nonisolated private static func hasVoiceActivity(in buffer: AVAudioPCMBuffer, mode: VoiceDetectorMode) -> Bool {
        switch mode {
        case .original:
            return hasVoiceActivityOriginal(in: buffer)
        case .rms:
            return hasVoiceActivityUsingRMS(in: buffer)
        }
    }

    nonisolated private static func hasVoiceActivityUsingRMS(in buffer: AVAudioPCMBuffer) -> Bool {
        let minRMS: Float = 0.0035
        let minVoiceDB: Float = -52.0

        guard let rms = buffer.calculateRMS() else { return false }
        let db = 20.0 * log10(max(rms, 0.000_001))
        return rms > minRMS || db > minVoiceDB
    }

    nonisolated private static func hasVoiceActivityOriginal(in buffer: AVAudioPCMBuffer) -> Bool {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return false }
        let minRMS: Float = 0.0035
        let minVoiceDB: Float = -52.0

        if let channelData = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20.0 * log10(max(rms, 0.000_001))
            return rms > minRMS || db > minVoiceDB
        }

        if let channelData = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = Float(channelData[i]) / Float(Int16.max)
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20.0 * log10(max(rms, 0.000_001))
            return rms > minRMS || db > minVoiceDB
        }

        if let channelData = buffer.int32ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameCount {
                let sample = Float(channelData[i]) / Float(Int32.max)
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20.0 * log10(max(rms, 0.000_001))
            return rms > minRMS || db > minVoiceDB
        }

        return false
    }
}

private extension AVAudioPCMBuffer {
    func calculateRMS() -> Float? {
        guard let channelData = floatChannelData else { return nil }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(self.frameLength)
        guard channelCount > 0, frameLength > 0 else { return nil }

        var squareSum: Float = 0
        var tempBuffer = [Float](repeating: 0, count: frameLength)

        for channel in 0..<channelCount {
            var localSum: Float = 0
            vDSP_vsq(channelData[channel], 1, &tempBuffer, 1, vDSP_Length(frameLength))
            vDSP_sve(&tempBuffer, 1, &localSum, vDSP_Length(frameLength))
            squareSum += localSum
        }

        let avgSquare = squareSum / Float(frameLength * channelCount)
        return sqrt(avgSquare)
    }
}
