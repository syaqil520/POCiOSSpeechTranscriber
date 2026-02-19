//
//  SpeechToTextViewModel.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 11/02/2026.
//

import Foundation
import AVFoundation
import SwiftUI
import Transcriber

@MainActor
class SpeechToTextViewModel: ObservableObject {

    @Published private(set) var model = TranscriptionModel()
    @Published private(set) var errorMessage: String?
    private let audioManager = AudioManager()
    private let transcriptionManager = SFSpeechRecognizerTranscriptionManager()
    private let transcriber = Transcriber(
        config: .init(
            silenceThreshold: 0.01,
            requiresOnDeviceRecognition: true
        ),
        debugLogging: true
    )

    
    private func requestPermissions() async -> Bool {
        let speechPermission = await transcriptionManager.requestSpeechPermission()
        let micPermission = await audioManager.requestMicrophonePermission()
        return speechPermission && micPermission
    }
    
    func toggleRecording() {
        if model.isRecording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording() }
        }
    }
    
    func clearTranscript() {
        model.finalizedText = ""
        model.currentText = ""
        errorMessage = nil
    }
    
    private func startRecording() async {
        // Initialize with default configuration
        guard let transcriber else {
            return
        }

        // Request authorization
        let status = await transcriber.requestAuthorization()
        guard status == .authorized else {
            return
        }

        // Start recording and receive transcriptions
        do {
            let stream = try await transcriber.startStream()
            model.isRecording = true
            for try await transcription in stream {
                switch transcription {
                case .rms:
                    print("test")
                case .transcription(let string):
                    self.model.currentText = string

                }
            }

            model.isRecording = false
        } catch {
            errorMessage = error.localizedDescription
            await stopRecording()
        }
//        guard await requestPermissions() else {
//            errorMessage = "Permissions not granted"
//            return
//        }
//        
//        do {
//            try audioManager.setupAudioSession()
//            
//            try await transcriptionManager.startTranscription { [weak self] text, isFinal in
//                Task { @MainActor in
//                    guard let self = self else { return }
//                    if isFinal {
//                        self.model.finalizedText += text + " "
//                        self.model.currentText = ""
//                    } else {
//                        self.model.currentText = text
//                    }
//                }
//            }
//            
//            try audioManager.startAudioStream { [weak self] buffer in
//                try? self?.transcriptionManager.processAudioBuffer(buffer)
//            }
//
//            model.isRecording = true
//            errorMessage = nil
//        } catch {
//            errorMessage = error.localizedDescription
//        }

    }
    
    // 6.
    private func stopRecording() async {
        try? audioManager.stopAudioStream()
        transcriptionManager.stopTranscription()
        model.isRecording = false
        await transcriber?.stopStream()
    }
    
}
