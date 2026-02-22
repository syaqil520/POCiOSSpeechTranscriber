//
//  HomeViewModel.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import SwiftUI

struct LocaleOption: Identifiable {
    let identifier: String
    let label: String

    var id: String { identifier }
}

@MainActor
final class HomeViewModel: ObservableObject {
    static let supportedLocales: [LocaleOption] = [
        LocaleOption(identifier: "ms-MY", label: "Malay (MY)"),
        LocaleOption(identifier: "en-US", label: "English (US)"),
        LocaleOption(identifier: "zh-CN", label: "Chinese (Simplified)"),
        LocaleOption(identifier: "zh-TW", label: "Chinese (Traditional)"),
        LocaleOption(identifier: "ta-IN", label: "Tamil") // not supported
    ]

    let speechToTextService: SpeechToTextService
    private var eventTask: Task<Void, Never>?

    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var isRecognizerAvailable = false
    @Published var errorMessage: String?
    @Published var voiceLevel: Float = 0
    @Published var isLoading: Bool = false

    @Published var selectedLocaleIdentifier: String = "en-US" {
        didSet {
            updateRecognizerLocale()
        }
    }

    init(providerType: SpeechRecognizerProviderType) {
        switch providerType {
        case .speechAnalyzer:
            if #available(iOS 26.0, *) {
                speechToTextService = SpeechToTextServiceImpl(speechRecognitionProvider: SpeechAnalyzerProvider())
            } else {
                fatalError("speechAnalyzer only available for ios 26.0+")
            }
        case .sfSpeechRecognizer:
            speechToTextService = SpeechToTextServiceImpl(speechRecognitionProvider: SFSpeechRecognizerProvider())
        }

        configureDefaultLocale()
        updateRecognizerLocale()
        observeEvents()
        Task {
            await requestPermissions()
        }
    }

    deinit {
        eventTask?.cancel()
    }

    func toggleRecording() {
        errorMessage = nil
        speechToTextService.toggleRecording()
        isListening.toggle()
    }

    func stopRecording() {
        speechToTextService.stopRecording()
        isListening = false
        voiceLevel = 0
    }

    func goToSetting() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
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
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            errorMessage = nil
            transcript = ""
            do {
                try await speechToTextService.setup(
                    with: SpeechTranscriptionConfig(
                        locale: Locale(identifier: selectedLocaleIdentifier),
                        shouldReportPartialResults: true,
                        requiresOnDeviceRecognition: false,
                        enableEndOfUtterance: false
                    )
                )
                isRecognizerAvailable = true
            } catch {
                handleError(error)
                isRecognizerAvailable = false
            }
        }
    }

    private func requestPermissions() async {
        isAuthorized = await speechToTextService.requestPermissionPermission()
        if !isAuthorized {
            errorMessage = "Please enable Speech Recognition and Microphone access in Settings."
        } else {
            errorMessage = nil
        }
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

    private func observeEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in speechToTextService.events {
                switch event {
                case .transcript(let transcript):
                    self.transcript = transcript
                case .audioLevel(let level):
                    self.voiceLevel = level
                case .finished:
                    self.speechToTextService.stopRecording()
                    self.isListening = false
                    self.voiceLevel = 0
                case .error(let error):
                    self.handleError(error)
                    self.speechToTextService.stopRecording()
                    self.isListening = false
                    self.voiceLevel = 0
                }
            }
        }
    }
}
