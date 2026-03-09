import SwiftUI

enum RecordingState {
    case idle
    case recording
    case transcribing
    case processing
}

struct StatusIndicatorView: View {
    let state: RecordingState

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "waveform")
        case .recording:
            Image(systemName: "mic.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red)
        case .transcribing:
            Image(systemName: "ellipsis")
        case .processing:
            Image(systemName: "brain")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.purple)
        }
    }
}
