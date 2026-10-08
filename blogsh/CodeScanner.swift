import SwiftUI
import Vision
import VisionKit
import AVFoundation

/// The camera, reading the code `./blog.sh pair` drew on a screen: the
/// system's own scanner, asked for a QR code and nothing else. What it
/// reads is handed over as text -- whether that text is a code of the
/// blog's is for whoever asked to say.
struct CodeScanner: UIViewControllerRepresentable {
    let read: (String) -> Void

    /// There is a camera here that can read codes: not in a simulator,
    /// and not everywhere an iPad's app runs.
    @MainActor static var isOffered: Bool { DataScannerViewController.isSupported }

    /// May the app use the camera? Asks, the first time.
    static func allowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(read: read) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.read = read
        // Begun once it stands in a window; asked again, a scanner that is
        // already looking does nothing.
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var read: (String) -> Void
        private var done = false

        init(read: @escaping (String) -> Void) { self.read = read }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in added {
                if case .barcode(let code) = item, let text = code.payloadStringValue, !text.isEmpty {
                    // The first code is the one: the scanner would otherwise
                    // hand the same one over at every frame.
                    done = true
                    scanner.stopScanning()
                    read(text)
                    return
                }
            }
        }
    }
}

/// The scanner as a screen of its own: the camera's picture, a line
/// saying what to point it at, and a way out.
struct CodeScannerScreen: View {
    let read: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CodeScanner { text in
                read(text)
                dismiss()
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Point the camera at the code on the server's screen.")
                    .font(.ui(14, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
