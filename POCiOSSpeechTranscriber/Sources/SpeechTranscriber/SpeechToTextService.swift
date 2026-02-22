//
//  SpeechToTextService.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Speech
import Accelerate

enum SpeechToTextEvent {
    case transcript(String)
    case audioLevel(Float)
    case finished
    case error(any Error)
}

protocol SpeechToTextService {
    var events: AsyncStream<SpeechToTextEvent> { get }

    func requestPermissionPermission() async -> Bool
    func setup(with config: SpeechTranscriptionConfig) async throws
    func toggleRecording()
    func startRecording()
    func stopRecording()
}

final class SpeechToTextServiceImpl: SpeechToTextService {

    private let audioManager: AudioManager = AudioManager()
    private let speechRecognizerProvider: SpeechRecognizerProvider

    let events: AsyncStream<SpeechToTextEvent>
    private let eventContinuation: AsyncStream<SpeechToTextEvent>.Continuation

    private var endOfUtteranceTicker: DispatchSourceTimer?
    private var lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
    private var recordingStartTime: CFAbsoluteTime?
    private var silenceStartTime: CFAbsoluteTime?

    private var endOfUtteranceRemaining: Double?
    private var maxSpeechRemaining: Double?

    private var isListening = false
    private var isAuthorized = false
    private var speechConfig: SpeechTranscriptionConfig?

    // const
    let minRMS: Float = 0.0035
    let minVoiceDB: Float = -52.0

    init(speechRecognitionProvider: SpeechRecognizerProvider) {
        let (stream, continuation) = AsyncStream<SpeechToTextEvent>.makeStream()
        self.events = stream
        self.eventContinuation = continuation
        self.speechRecognizerProvider = speechRecognitionProvider
    }

    func isAuthorized() async -> Bool {
        return false
    }

    func requestPermissionPermission() async -> Bool {
        let microphoneStatus = await audioManager.requestMicrophonePermission()
        let speechRecognizerStatus = await speechRecognizerProvider.requestSpeechPermission()
        isAuthorized = microphoneStatus && speechRecognizerStatus
        return isAuthorized
    }

    func setup(with config: SpeechTranscriptionConfig) async throws {
        if isListening {
            stopRecording()
        }

        try await speechRecognizerProvider.setupRecognizer(with: config)
        self.speechConfig = config
    }

    func toggleRecording() {
        if isListening {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard isAuthorized else { return }
        do {
            try audioManager.setupAudioSession()
            try speechRecognizerProvider.startTranscription { [weak self] transcript, isFinal, error in
                guard let self else { return }
                if let transcript, !transcript.isEmpty {
                    eventContinuation.yield(.transcript(transcript))
                }

                if let error {
                    eventContinuation.yield(.error(error))
                } else if isFinal == true {
                    eventContinuation.yield(.finished)
                }
            }

            try audioManager.startAudioStream { [weak self] buffer in
                guard let self else { return }
                speechRecognizerProvider.processAudioBuffer(buffer)
                let rms = buffer.calculateRMS()
                eventContinuation.yield(.audioLevel(normalizedAudioLevel(for: rms)))
                if speechConfig?.enableEndOfUtterance == true {
                    updateVoiceActivity(hasVoice: hasVoiceActivity(for: rms))
                }
            }

            if speechConfig?.enableEndOfUtterance == true {
                startCheckEndOfUtterance()
            }
            isListening = true
        } catch {
            eventContinuation.yield(.error(error))
        }
    }

    func stopRecording() {
        guard isListening else { return }
        do {
            speechRecognizerProvider.stopTranscription()
            try audioManager.stopAudioStream()
            isListening = false
        } catch {
            eventContinuation.yield(.error(error))
        }
    }
}

private extension SpeechToTextServiceImpl {
    func startCheckEndOfUtterance () {
        recordingStartTime = CFAbsoluteTimeGetCurrent()
        maxSpeechRemaining = speechConfig?.maxSpeechDuration ?? 8.0
        lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
        silenceStartTime = nil
        endOfUtteranceRemaining = nil

        startEndOfUtteranceTicker()
    }

    func startEndOfUtteranceTicker() {
        stopEndOfUtteranceTicker()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()

            if let recordingStartTime {
                let speakingElapsed = now - recordingStartTime
                maxSpeechRemaining = max(0, speechConfig?.maxSpeechDuration ?? 8.0 - speakingElapsed)
                if speakingElapsed >= speechConfig?.maxSpeechDuration ?? 8.0 {
                    stopRecording()
                    return
                }
            }

            if let silenceStartTime {
                let silenceElapsed = now - silenceStartTime
                let remaining = max(0, speechConfig?.endOfUtteranceTimeout ?? 3.0 - silenceElapsed)
                endOfUtteranceRemaining = remaining
                if remaining <= 0 {
                    stopRecording()
                }
            }
        }

        endOfUtteranceTicker = timer
        timer.resume()
    }

    func stopEndOfUtteranceTicker() {
        endOfUtteranceTicker?.cancel()
        endOfUtteranceTicker = nil
    }

    func hasVoiceActivity(for rms: Float?) -> Bool {
        guard let rms else { return false }
        let decibel = 20.0 * log10(max(rms, 0.000_001))
        return rms > speechConfig?.minRMS ?? minRMS || decibel > speechConfig?.minDecibel ?? minVoiceDB
    }

    func updateVoiceActivity(hasVoice: Bool) {
        guard isListening else { return }

        if hasVoice {
            lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
            silenceStartTime = nil
            endOfUtteranceRemaining = nil
        } else {
            silenceStartTime = CFAbsoluteTimeGetCurrent()
            endOfUtteranceRemaining = speechConfig?.endOfUtteranceTimeout ?? 3.0
        }
    }

    func normalizedAudioLevel(for rms: Float?) -> Float {
        guard let rms else { return 0 }
        let db = 20.0 * log10(max(rms, 0.000_001))
        let minDB = speechConfig?.minDecibel ?? minVoiceDB
        let maxDB: Float = -10.0
        let normalized = (db - minDB) / (maxDB - minDB)
        return min(max(normalized, 0), 1)
    }
}

extension AVAudioPCMBuffer {
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
