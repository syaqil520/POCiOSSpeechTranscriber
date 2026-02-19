//
//  HomeViewModel.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Observation
import Speech
import Combine
import Accelerate
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
        LocaleOption(identifier: "ta-IN", label: "Tamil")
    ]

    let speechToTextService = SpeechToTextServiceImpl()

    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    @Published var maxSpeakingRemaining: Double?
    @Published var endOfUtteranceRemaining: Double?

    @Published var endOfUtteranceTimeout: Double = 3.0
    @Published var maxSpeakingDuration: Double = 8.0

    @Published var selectedLocaleIdentifier: String = "en-US" {
        didSet {
            updateRecognizerLocale()
        }
    }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    private var endOfUtteranceTicker: DispatchSourceTimer?
    private var lastVoiceActivityTime = CFAbsoluteTimeGetCurrent()
    private var recordingStartTime: CFAbsoluteTime?
    private var silenceStartTime: CFAbsoluteTime?

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
        speechToTextService.setup(
            with: SpeechTranscriptionConfig(
                locale: Locale(identifier: selectedLocaleIdentifier),
                shouldReportPartialResults: true,
                requiresOnDeviceRecognition: true,
                endofUtteranceTimeout: endOfUtteranceTimeout,
                maxSpeechDuration: maxSpeakingDuration

            )
        )
    }
}

extension HomeViewModel: SpeechToTextServiceDelegate {
    nonisolated func didReceiveResult(transcript: String, isFinal: Bool) {
        Task { @MainActor in
            self.transcript = transcript
            print("HomeViewModel transcript: \(transcript)")
            if isFinal {
                isListening = false
                errorMessage = nil
            }
        }
    }
    
    nonisolated func didReceiveError(_ error: any Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            speechToTextService.stopRecording()
            isListening = false
        }
    }
}
