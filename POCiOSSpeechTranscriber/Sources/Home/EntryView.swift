//
//  EntryView.swift
//  POCiOSSpeechTranscriber
//
//  Created by Syaqil Aizat on 20/02/2026.
//

import SwiftUI
import Speech

struct EntryView: View {
    private var isSpeechAnalyzerSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 0.9, green: 0.94, blue: 0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose a Transcriber")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.32))

                    Text("Pick the speech engine you want to test.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        HomeView(providerType: .sfSpeechRecognizer)
                    } label: {
                        EntryCard(
                            title: "SFSpeechRecognizer",
                            subtitle: "Legacy Api support from iOS 10 above, has online server support",
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        HomeView(providerType: .speechAnalyzer)
                    } label: {
                        EntryCard(
                            title: "SpeechAnalyzer",
                            subtitle: isSpeechAnalyzerSupported ? "New Api from iOS 26.0 and above, offline only" : "Requires iOS 26+",
                        )
                        .opacity(isSpeechAnalyzerSupported ? 1.0 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSpeechAnalyzerSupported)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Speech To Text")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EntryCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                    .bold()
                    .foregroundStyle(Color(red: 0.06, green: 0.15, blue: 0.25))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

#Preview {
    EntryView()
}
