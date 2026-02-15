import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SpeechToTextViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                Button(action: {
                    viewModel.toggleRecording()
                }) {
                    VStack {
                        Image(systemName: viewModel.model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(viewModel.model.isRecording ? .red : .blue)
                        
                        Text(viewModel.model.isRecording ? "Stop Recording" : "Start Recording")
                            .font(.headline)
                            .foregroundColor(viewModel.model.isRecording ? .red : .blue)
                    }
                }
                .padding()
                
                if viewModel.model.isRecording {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .scaleEffect(viewModel.model.isRecording ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.model.isRecording)
                        
                        Text("Recording...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !viewModel.model.displayText.isEmpty {
                            Text(viewModel.model.displayText)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(10)
                        } else {
                            Text("Tap the microphone to start recording...")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Speech to Text")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        viewModel.clearTranscript()
                    }
                    .disabled(viewModel.model.displayText.isEmpty)
                }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
