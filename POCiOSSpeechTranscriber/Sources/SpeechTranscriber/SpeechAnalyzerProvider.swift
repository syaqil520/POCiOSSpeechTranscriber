//
//  SpeechAnalyzerProvider.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 11/02/2026.
//

import Foundation
import Speech

@available(iOS 26.0, *)
final class SpeechAnalyzerProvider: SpeechRecognizerProvider {

    private let audioBufferConverter = AudioBufferConverter()

    private var reservedLocale: Locale?

    private var speechTranscriber: SpeechTranscriber?
    private var dictationTranscriber: DictationTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    private var analyzerTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var isTranscriptionRunning = false

    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func setupRecognizer(with config: SpeechTranscriptionConfig) async throws {
        guard await setupTranscriber(for: config)
        else {
            throw SpeechTranscriptionError.unsupportedLocale
        }

        let transcriber: any SpeechModule
        if let speechTranscriber {
            transcriber = speechTranscriber
        } else if let dictationTranscriber {
            transcriber = dictationTranscriber
        } else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        try await ensureAssetsInstalled(for: [transcriber])
        try await reserve(locale: config.locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        guard let format else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        self.analyzer = analyzer
        self.analyzerFormat = format
    }

    func startTranscription(onReceive: @escaping (String?, Bool?, Error?) -> Void) throws {
        guard let analyzer else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        guard speechTranscriber != nil || dictationTranscriber != nil else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }

        if isTranscriptionRunning {
            stopTranscription()
        }

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder
        isTranscriptionRunning = true

        if let speechTranscriber {
            resultTask = Task { [weak self] in
                do {
                    for try await result in speechTranscriber.results {
                        onReceive(String(result.text.characters), result.isFinal, nil)
                    }
                } catch {
                    onReceive(nil, nil, error)
                }
                self?.isTranscriptionRunning = false
            }
        } else if let dictationTranscriber {
            resultTask = Task { [weak self] in
                do {
                    for try await result in dictationTranscriber.results {
                        onReceive(String(result.text.characters), result.isFinal, nil)
                    }
                } catch {
                    onReceive(nil, nil, error)
                }
                self?.isTranscriptionRunning = false
            }
        }

        analyzerTask = Task {
            do {
                try await analyzer.start(inputSequence: inputSequence)
            } catch {
                onReceive(nil, nil, error)
            }
        }
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let inputBuilder, let analyzerFormat else { return }
        do {
            let converted = try audioBufferConverter.convertBuffer(buffer, to: analyzerFormat)
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        } catch {
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func stopTranscription() {
        guard isTranscriptionRunning || inputBuilder != nil else { return }

        inputBuilder?.finish()
        inputBuilder = nil

        analyzerTask?.cancel()
        analyzerTask = nil

        resultTask?.cancel()
        resultTask = nil

        if let analyzer {
            Task {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        }

        isTranscriptionRunning = false
    }
}

@available(iOS 26.0, *)
private extension SpeechAnalyzerProvider {
    func setupTranscriber(for config: SpeechTranscriptionConfig) async -> Bool {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: config.locale) {
            speechTranscriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            dictationTranscriber = nil
            return true
        }

        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: config.locale) {
            dictationTranscriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            speechTranscriber = nil
            return true
        }

        return false
    }

    func reserve(locale: Locale) async throws {
        if reservedLocale == locale {
            return
        }

        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }

        let _ = try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale
    }

    func ensureAssetsInstalled(for modules: [any SpeechModule]) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
            return
        }
        try await request.downloadAndInstall()
    }
}
