//
//  SpeechToTextService.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Speech
import Accelerate

protocol SpeechToTextServiceDelegate: AnyObject {
    func didReceiveResult(transcript: String)
    func didReceiveError(_ error: Error)
    func didReceiveFinish()
}

protocol SpeechToTextService {
    func requestPermissionPermission() async -> Bool
    func setup(with config: SpeechTranscriptionConfig)
    func toggleRecording()
    func startRecording()
    func stopRecording()
}

final class SpeechToTextServiceImpl: SpeechToTextService {

    private let audioManager: AudioManager = AudioManager()
    private let speechRecognizerProvider: SpeechRecognizerProvider

    weak var delegate: SpeechToTextServiceDelegate?

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
        self.speechRecognizerProvider = speechRecognitionProvider
    }

    func requestPermissionPermission() async -> Bool {
        let microphoneStatus = await audioManager.requestMicrophonePermission()
        let speechRecognizerStatus = await speechRecognizerProvider.requestSpeechPermission()
        isAuthorized = microphoneStatus && speechRecognizerStatus
        return isAuthorized
    }

    func setup(with config: SpeechTranscriptionConfig) {
        if isListening {
            stopRecording()
        }

        do {
            try speechRecognizerProvider.setupRecognizer(with: config)
            self.speechConfig = config
        } catch {
            delegate?.didReceiveError(error)
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
        guard isAuthorized else { return }
        do {
            try audioManager.setupAudioSession()
            try speechRecognizerProvider.startTranscription { [weak self] transcript, isFinal, error in
                guard let self else { return }
                if let transcript, !transcript.isEmpty {
                    delegate?.didReceiveResult(transcript: transcript)
                }

                if let error {
                    delegate?.didReceiveError(error)
                } else if isFinal == true {
                    delegate?.didReceiveFinish()
                }
            }

            try audioManager.startAudioStream { [weak self] buffer in
                guard let self else { return }
                speechRecognizerProvider.processAudioBuffer(buffer)
                if speechConfig?.enableEndOfUtterance == true {
                    checkVoiceActivity(for: buffer)
                }
            }

            if speechConfig?.enableEndOfUtterance == true {
                startCheckEndOfUtterance()
            }
            isListening = true
        } catch {
            delegate?.didReceiveError(error)
        }
    }

    func stopRecording() {
        guard isListening else { return }
        do {
            speechRecognizerProvider.stopTranscription()
            try audioManager.stopAudioStream()
            isListening = false
        } catch {
            delegate?.didReceiveError(error)
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

    func checkVoiceActivity(for buffer: AVAudioPCMBuffer) {
        let hasVoice = hasVoiceActivity(for: buffer)
        updateVoiceActivity(hasVoice: hasVoice)
    }

    func hasVoiceActivity(for buffer: AVAudioPCMBuffer) -> Bool {
        guard let rms = buffer.calculateRMS() else { return false }
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
