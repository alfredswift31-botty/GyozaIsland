import AVFoundation
import SwiftUI

final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    // startRunning/stopRunning block and must not overlap, so both run in
    // order on one serial queue instead of racing (or stalling the main thread).
    private let sessionQueue = DispatchQueue(label: "com.gyoza.GyozaIsland.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    // False once the mirror is closed; permission can be granted after that.
    private var isActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func startSession() {
        isActive = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configureSession() }
        }
    }

    func stopSession() {
        isActive = false
        sessionQueue.async { [session = self.session] in
            session.stopRunning()
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    private func configureSession() {
        // The permission prompt can outlive the mirror; don't start a camera
        // nobody can see.
        guard isActive, previewLayer == nil else { return }

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

        sessionQueue.async { [weak self] in
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
