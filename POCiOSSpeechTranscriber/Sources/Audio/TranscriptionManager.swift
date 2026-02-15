//
//  TranscriptionManager.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 11/02/2026.
//

import Foundation
import Speech

struct TranscriptionModel {
    var finalizedText: String = ""
    var currentText: String = ""
    var isRecording: Bool = false
    
    var displayText: String {
        return finalizedText + currentText
    }
}

protocol AudioBufferTranscriberService {

}

@available(iOS 26.0, *)
final class TranscriptionManager {
    
    enum TranscriptionError: Error {
        case failedToReserveLocale
    }

    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<(), Error>?
    private var analyzerFormat: AVAudioFormat?
    private var reservedLocale: Locale?
    private var converter = BufferConverter()
    
    func requestSpeechPermission() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }
    
    func startTranscription(onResult: @escaping (String, Bool) -> Void) async throws {
        let currentLocale = Locale.current
        let locale: Locale = await SpeechTranscriber.supportedLocale(equivalentTo: currentLocale) ?? Locale(
            identifier: "en_US"
        )
        
        try await reserve(locale: locale)
        
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        analyzer = SpeechAnalyzer(modules: [transcriber!])
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber!])
        
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder
        
        recognizerTask = Task {
            for try await result in transcriber!.results {
                let text = String(result.text.characters)
                onResult(text, result.isFinal)
            }
        }
        
        try await analyzer?.start(inputSequence: inputSequence)
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else { return }
        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }
    
    func stopTranscription() async {
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil
        
        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
    }
    
    private func reserve(locale: Locale) async throws {
        if reservedLocale == locale {
            return
        }
        
        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
        
        let didReserve = try await AssetInventory.reserve(locale: locale)
        guard didReserve else {
            throw TranscriptionError.failedToReserveLocale
        }
        reservedLocale = locale
    }
}
