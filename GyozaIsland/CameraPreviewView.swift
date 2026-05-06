import AVFoundation
import SwiftUI

final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func startSession() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configureSession() }
        }
    }

    func stopSession() {
        session.stopRunning()
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        // Prefer front camera; fall back to any available camera.
        let position: AVCaptureDevice.Position = .front
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                  ?? AVCaptureDevice.default(for: .video)

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

struct CameraPreviewView: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.startSession()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.stopSession()
    }
}
