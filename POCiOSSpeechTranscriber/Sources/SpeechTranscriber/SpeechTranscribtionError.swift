//
//  SpeechTranscribtionError.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 19/02/2026.
//

import Foundation

enum SpeechTranscriptionError: Error {
    case unsupportedLocale
    case recognizerUnavailable
}
