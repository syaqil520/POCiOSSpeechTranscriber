//
//  SFSpeechRecognizerTranscriptionManager.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 15/02/2026.
//

import Foundation
import Speech
import AVFoundation

final class SFSpeechRecognizerTranscriptionManager {
    
    enum TranscriptionError: Error {
        case unsupportedLocale
        case recognizerCreationFailed
        case recognizerUnavailable
        case notStarted
    }
    
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func startTranscription(onResult: @escaping (String, Bool) -> Void) async throws {
        let locale = try resolveLocale()
        
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.recognizerCreationFailed
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        stopTranscription()
        
        self.recognizer = recognizer
        recognitionRequest = request
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            }
            
            if error != nil {
                self?.stopTranscription()
            }
        }
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let recognitionRequest else {
            throw TranscriptionError.notStarted
        }
        recognitionRequest.append(buffer)
    }
    
    func stopTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
    }
    
    private func resolveLocale() throws -> Locale {
        let currentLocale = Locale.current
        if SFSpeechRecognizer.supportedLocales().contains(currentLocale) {
            return currentLocale
        }
        
        let fallback = Locale(identifier: "en_US")
        guard SFSpeechRecognizer.supportedLocales().contains(fallback) else {
            throw TranscriptionError.unsupportedLocale
        }
        return fallback
    }
}
