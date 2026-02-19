//
//  HomeView.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 16/02/2026.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel = HomeViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Speech to Text")
                .font(.title2)
                .bold()

            Text(viewModel.isListening ? "Listening..." : "Idle")
                .foregroundColor(viewModel.isListening ? .green : .secondary)

            Picker("Locale", selection: $viewModel.selectedLocaleIdentifier) {
                ForEach(HomeViewModel.supportedLocales) { locale in
                    Text(locale.label).tag(locale.identifier)
                }
            }
            .pickerStyle(.menu)

//            Picker("Speech Transcriber", selection: ) {
//                ForEach(HomeViewModel.) {
//
//                }
//            }

            ScrollView {
                Text(viewModel.transcript.isEmpty ? "Your transcription will appear here." : viewModel.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
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
                    .background(viewModel.isAuthorized ? Color.accentColor : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!viewModel.isAuthorized)

            Button("Request Permissions") {
                Task {
                    await viewModel.requestPermissions()
                }
            }
            .font(.footnote)
        }
        .padding()
        .onDisappear {
            viewModel.stopRecording()
        }
    }
}

#Preview {
    HomeView()
}
