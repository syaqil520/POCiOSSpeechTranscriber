//
//  HomeViewModel.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Observation
import Combine
import Dispatch

struct LocaleOption: Identifiable {
    let identifier: String
    let label: String

    var id: String { identifier }
}

@MainActor
final class HomeViewModel: NSObject, ObservableObject {
    static let supportedLocales: [LocaleOption] = [
        LocaleOption(identifier: "ms-MY", label: "Malay (MY)"),
        LocaleOption(identifier: "en-US", label: "English (US)"),
        LocaleOption(identifier: "zh-CN", label: "Chinese (Simplified)"),
        LocaleOption(identifier: "zh-TW", label: "Chinese (Traditional)"),
        LocaleOption(identifier: "ta-IN", label: "Tamil") // not supported
    ]

    let speechToTextService = SpeechToTextServiceImpl(speechRecognitionProvider: SFSpeechRecognizerProvider())

    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    @Published var selectedLocaleIdentifier: String = "en-US" {
        didSet {
            updateRecognizerLocale()
        }
    }

    override init() {
        super.init()
        speechToTextService.delegate = self
        configureDefaultLocale()
        updateRecognizerLocale()
        Task {
            await requestPermissions()
        }
    }

    func requestPermissions() async {
        isAuthorized = await speechToTextService.requestPermissionPermission()
        if !isAuthorized {
            errorMessage = "Please enable Speech Recognition and Microphone access in Settings."
        } else {
            errorMessage = nil
        }
    }

    func toggleRecording() {
        speechToTextService.toggleRecording()
        isListening.toggle()
    }

    func stopRecording() {
        speechToTextService.stopRecording()
    }

    private func configureDefaultLocale() {
        let currentIdentifier = Locale.current.identifier
        let supported = Set(Self.supportedLocales.map(\.identifier))
        if supported.contains(currentIdentifier) {
            selectedLocaleIdentifier = currentIdentifier
        }
    }

    private func updateRecognizerLocale() {
        errorMessage = nil
        transcript = ""
        speechToTextService.setup(
            with: SpeechTranscriptionConfig(
                locale: Locale(identifier: selectedLocaleIdentifier),
                shouldReportPartialResults: true,
                requiresOnDeviceRecognition: false,
                enableEndOfUtterance: false,
            )
        )
    }

    private func handleError(_ error: any Error) {
        if let speechTranscriberError = error as? SpeechTranscriptionError {
            switch speechTranscriberError {
            case .unsupportedLocale:
                errorMessage = "Locale not supported"
            case .recognizerUnavailable:
                errorMessage = "Speech recognition is not available on this device."
            }
            return
        }

        errorMessage = error.localizedDescription

    }
}

extension HomeViewModel: SpeechToTextServiceDelegate {
    nonisolated func didReceiveFinish() {
        Task { @MainActor in
            speechToTextService.stopRecording()
        }
    }
    
    nonisolated func didReceiveResult(transcript: String) {
        Task { @MainActor in
            self.transcript = transcript
        }
    }
    
    nonisolated func didReceiveError(_ error: any Error) {
        Task { @MainActor in
            handleError(error)
            speechToTextService.stopRecording()
            isListening = false
        }
    }
}
