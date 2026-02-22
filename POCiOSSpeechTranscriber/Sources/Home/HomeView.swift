//
//  HomeView.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import SwiftUI

enum SpeechRecognizerProviderType {
    case speechAnalyzer
    case sfSpeechRecognizer
}

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    var loadingView: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(red: 0.06, green: 0.44, blue: 0.88))
                    .scaleEffect(1.25)

                Text("Setting Up Recognizer...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.16, green: 0.23, blue: 0.35))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 10)
        }
        .transition(.opacity)
    }

    init(providerType: SpeechRecognizerProviderType) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(providerType: providerType))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.9, green: 0.94, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Speech to Text")
                    .font(.title2)
                    .bold()

                VoiceWaveView(level: CGFloat(viewModel.voiceLevel), isListening: viewModel.isListening)

                Picker("Locale", selection: $viewModel.selectedLocaleIdentifier) {
                    ForEach(HomeViewModel.supportedLocales) { locale in
                        Text(locale.label).tag(locale.identifier)
                    }
                }
                .disabled(viewModel.isListening || !viewModel.isAuthorized)
                .pickerStyle(.menu)

                ScrollView {
                    Text(viewModel.transcript.isEmpty ? "Your transcription will appear here." : viewModel.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
                .frame(maxHeight: 280)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button(action: viewModel.toggleRecording) {
                    Text(viewModel.isListening ? "Stop" : "Start Listening")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((viewModel.isAuthorized && viewModel.isRecognizerAvailable) ? (viewModel.isListening ? Color.red : Color.accentColor) : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!viewModel.isAuthorized || !viewModel.isRecognizerAvailable)

                Button("Enable permission") {
                    viewModel.goToSetting()
                }
                .disabled(viewModel.isAuthorized)
                .font(.footnote)
            }
            .padding()
            .onDisappear {
                viewModel.stopRecording()
            }

            if viewModel.isLoading {
                loadingView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
    }
}

private struct VoiceWaveView: View {
    let level: CGFloat
    let isListening: Bool

    private let multipliers: [CGFloat] = [0.35, 0.65, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(isListening ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: barHeight(multiplier: multiplier))
            }
        }
        .frame(height: 36)
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.easeInOut(duration: 0.2), value: isListening)
    }

    private func barHeight(multiplier: CGFloat) -> CGFloat {
        let base: CGFloat = 6
        let maxHeight: CGFloat = 28
        let adjustedLevel = min(max(level, 0), 1)
        if !isListening {
            return base
        }
        return base + (maxHeight - base) * adjustedLevel * multiplier
    }
}

#Preview {
    HomeView(providerType: .sfSpeechRecognizer)
}
