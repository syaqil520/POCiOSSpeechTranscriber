//
//  SFSpeechRecognizerProvider.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Speech

protocol SpeechRecognizerProvider {
    func requestSpeechPermission() async -> Bool
    func setupRecognizer(with config: SpeechTranscriptionConfig) async throws
    func startTranscription(onReceive: @escaping (String?, Bool?, Error?) -> Void) throws
    func stopTranscription()
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)
}

final class SFSpeechRecognizerProvider: SpeechRecognizerProvider {

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

    func setupRecognizer(with config: SpeechTranscriptionConfig) async throws {
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

        guard let recognitionRequest else { return }
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
        }
    }

    func stopTranscription() {
        guard isTranscriptionRunning else { return }

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil
    }
}

private extension SFSpeechRecognizerProvider {
    func checkLocaleAvailability(for locale: Locale) -> Bool {
        return SFSpeechRecognizer.supportedLocales().contains(locale)
    }
}
