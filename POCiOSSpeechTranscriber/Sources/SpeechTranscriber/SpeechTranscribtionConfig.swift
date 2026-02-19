//
//  SpeechTranscribtionConfig.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 19/02/2026.
//

import Foundation

struct SpeechTranscriptionConfig {
    let locale: Locale
    let shouldReportPartialResults: Bool
    let requiresOnDeviceRecognition: Bool
    let enableEndOfUtterance: Bool
    let endOfUtteranceTimeout: Double
    let maxSpeechDuration: Double
    let minRMS: Float
    let minDecibel: Float

    init(
        locale: Locale,
        shouldReportPartialResults: Bool,
        requiresOnDeviceRecognition: Bool,
        enableEndOfUtterance: Bool = false,
        endofUtteranceTimeout: Double = 3.0,
        maxSpeechDuration: Double = 8.0,
        minRMS: Float = 0.0035,
        minDecibel: Float = -52.0
    ) {
        self.locale = locale
        self.shouldReportPartialResults = shouldReportPartialResults
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.enableEndOfUtterance = enableEndOfUtterance
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

struct SpeechTranscribtionResult {
    let transcript: String?
    let isFinal: Bool?
    let error: (any Error)?
}
