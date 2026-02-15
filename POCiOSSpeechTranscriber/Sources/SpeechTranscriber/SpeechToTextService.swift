//
//  SpeechToTextService.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import Foundation
import Speech

public protocol SpeechToTextService {
    func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus
}

final class SpeechToTextServiceImpl: SpeechToTextService {

    func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

}
