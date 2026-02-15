//
//  AudioManager.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 11/02/2026.
//

import Foundation
import AVFoundation

final class AudioManager {

    private let audioEngine = AVAudioEngine()
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioTapInstalled = false
    
    func setupAudioSession() throws {
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func startAudioStream(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !audioTapInstalled else { return }
        
        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: audioEngine.inputNode.outputFormat(forBus: 0)
        ) { buffer, _ in
            onBuffer(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        audioTapInstalled = true
    }
    
    func stopAudioStream() {
        guard audioTapInstalled else { return }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        audioTapInstalled = false
    }
}
