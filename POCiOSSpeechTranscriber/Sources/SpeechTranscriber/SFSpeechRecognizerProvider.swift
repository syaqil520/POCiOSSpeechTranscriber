//
//  SFSpeechRecognizerProvider.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Speech

enum SpeechTranscriptionError: Error {
    case unsupportedLocale
    case recognizerUnavailable
    case setupFailure
    case notStarted
}

struct SpeechTranscriptionConfig {
    let locale: Locale
    let shouldReportPartialResults: Bool
    let requiresOnDeviceRecognition: Bool
    let endOfUtteranceTimeout: Double
    let maxSpeechDuration: Double
    let minRMS: Float
    let minDecibel: Float

    init(
        locale: Locale,
        shouldReportPartialResults: Bool,
        requiresOnDeviceRecognition: Bool,
        endofUtteranceTimeout: Double = 3.0,
        maxSpeechDuration: Double = 8.0,
        minRMS: Float = 0.0035,
        minDecibel: Float = -50.0

    ) {
        self.locale = locale
        self.shouldReportPartialResults = shouldReportPartialResults
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.endOfUtteranceTimeout = endofUtteranceTimeout
        self.maxSpeechDuration = maxSpeechDuration
        if minRMS > 1 || minRMS < 0 {
            self.minRMS = 0.0035
        } else {
            self.minRMS = minRMS
        }
        self.minDecibel = minDecibel
    }
}

final class SFSpeechRecognizerProvider {

    private let audioBufferConverter: AudioBufferConverter = AudioBufferConverter()

    private var config: SpeechTranscriptionConfig?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var isTranscriptionRunning = false
    private var recognizerCache: [Locale: SFSpeechRecognizer] = [:]

    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func setupRecognizer(with config: SpeechTranscriptionConfig) throws {
        guard checkLocaleAvailability(for: config.locale) else {
            throw SpeechTranscriptionError.unsupportedLocale
        }

        if let recognizer = recognizerCache[config.locale] {
            speechRecognizer = recognizer
        } else {
            let recognizer = SFSpeechRecognizer(locale: config.locale)
            recognizerCache[config.locale] = recognizer
            speechRecognizer = recognizer
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            speechRecognizer = nil
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        self.config = config
    }

    func startTranscription(onReceive: @escaping (String?, Bool?, Error?) -> Void) throws {
        guard let speechRecognizer, let config else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = config.shouldReportPartialResults
        recognitionRequest?.requiresOnDeviceRecognition = config.requiresOnDeviceRecognition

        guard let recognitionRequest else { throw SpeechTranscriptionError.setupFailure }
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            onReceive(result?.bestTranscription.formattedString, result?.isFinal, error)
        }

        isTranscriptionRunning = true
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let recognitionRequest else { return }
        do {
            let converted = try audioBufferConverter.convertBuffer(buffer, to: recognitionRequest.nativeAudioFormat)
            recognitionRequest.append(converted)
        } catch {
            recognitionRequest.append(buffer)
//            print("error convert buffer \(error)")
        }
    }

    func stopTranscription() {
        guard isTranscriptionRunning else { return }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
    }
}

private extension SFSpeechRecognizerProvider {
    func checkLocaleAvailability(for locale: Locale) -> Bool {
        return SFSpeechRecognizer.supportedLocales().contains(locale)
    }
}
