import AVFoundation
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct DeviceMigrationView: View {
    @ObservedObject var coordinator: DeviceMigrationCoordinator
    let initialMode: DeviceMigrationMode

    @Environment(\.dismiss) private var dismiss
    @State private var pastedLink = ""
    @State private var passphrase = ""
    @State private var rememberPassphrase = true
    @State private var scannerError: String?
    @State private var isQuitting = false

    var body: some View {
        NavigationStack {
            content
                .padding(20)
                .frame(width: 560, height: 540)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if showsCancelButton {
                            Button("Cancel", action: cancelAndDismiss)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if coordinator.phase == .importComplete {
                            Button("Done", action: dismiss.callAsFunction)
                        }
                    }
                }
        }
        .interactiveDismissDisabled(coordinator.dismissalDisabled && !isQuitting)
        .task { coordinator.present(initialMode) }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .scanOrPaste:
            scanOrPaste
        case .confirmExport:
            confirmExport
        case .preparingImport:
            working(title: "Preparing secure download", detail: "Creating a temporary SimpleX profile…")
        case let .downloading(bytes, total):
            transferProgress(title: "Downloading from phone", bytes: bytes, total: total)
        case .readyToReplace:
            readyToReplace
        case .replacingDatabase:
            working(title: "Importing chat archive", detail: "Your previous database is being preserved as a backup.")
        case let .enterPassphrase(error):
            enterPassphrase(error: error)
        case .openingDatabase:
            working(title: "Opening imported chat", detail: "Checking the phone database passphrase…")
        case .importComplete:
            importComplete
        case .preparingExport:
            working(title: "Preparing encrypted archive", detail: "Chat is stopped while the database is copied.")
        case let .uploading(bytes, total):
            transferProgress(title: "Uploading encrypted archive", bytes: bytes, total: total)
        case let .exportReady(link):
            exportReady(link: link)
        case .exportComplete:
            exportComplete
        case .resumingChat:
            working(title: "Resuming chat", detail: "Reconnecting this Mac…")
        case let .failed(message):
            failed(message)
        }
    }

    private var scanOrPaste: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Scan the archive QR code shown on your phone")
                    .font(.headline)
                Text("On your phone, open Settings → Database → Migrate to another device.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let scannerError {
                ContentUnavailableView(
                    "Camera unavailable",
                    systemImage: "camera.fill",
                    description: Text(scannerError)
                )
                .frame(height: 240)
            } else {
                QRCodeScannerView(
                    onCode: { code in
                        pastedLink = code
                        coordinator.startImport(link: code)
                    },
                    onError: { scannerError = $0 }
                )
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: 10))
            }

            VStack(spacing: 12) {
                TextField("Or paste the SimpleX archive link", text: $pastedLink)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Paste") {
                        pastedLink = NSPasteboard.general.string(forType: .string) ?? ""
                    }
                    Spacer()
                    Button("Download Archive") {
                        coordinator.startImport(link: pastedLink)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var confirmExport: some View {
        VStack(spacing: 24) {
            Image(systemName: "qrcode")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Export to your phone")
                    .font(.title2.weight(.semibold))
                Text("Native Chat will stop chat, create an encrypted archive, and upload it temporarily to SimpleX file servers. The QR code grants access to that archive.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            GroupBox {
                Label(
                    "After importing on your phone, do not run chat on both devices. Doing so can break connection encryption.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .padding(8)
            }
            Button("Create Transfer QR Code", action: coordinator.startExport)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private var readyToReplace: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.arrow.down")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Archive downloaded")
                    .font(.title2.weight(.semibold))
                Text("Importing replaces the active database on this Mac. SimpleX preserves the current chat and agent databases as .bak backups.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Replace Database and Import", role: .destructive, action: coordinator.replaceDatabase)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private func enterPassphrase(error: String?) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Enter your phone database passphrase")
                    .font(.title2.weight(.semibold))
                Text("This is the database passphrase from SimpleX on your phone, not your phone unlock code.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                SecureField("Database passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                if coordinator.keychainStorageAvailable {
                    Toggle("Remember passphrase in Mac Keychain", isOn: $rememberPassphrase)
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Button("Open Imported Chat") {
                coordinator.openImportedDatabase(
                    passphrase: passphrase,
                    remember: rememberPassphrase
                )
            }
            .keyboardShortcut(.defaultAction)
            .disabled(passphrase.isEmpty)
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private var importComplete: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Chat imported")
                    .font(.title2.weight(.semibold))
                Text("Finish the migration on your phone to remove the temporary server copy. Your conversations are now open on this Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private func exportReady(link: String) -> some View {
        VStack(spacing: 16) {
            Text("Scan this code on your phone")
                .font(.headline)
            TransferQRCode(value: link)
                .frame(width: 280, height: 280)
            Text("On your phone, choose Migrate from another device and scan this QR code.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                }
                Spacer()
                Button("Phone Import Finished", action: coordinator.finalizeExport)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private var exportComplete: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("Transfer finalized")
                    .font(.title2.weight(.semibold))
                Text("Chat remains stopped on this Mac so the imported copy on your phone can be the only active copy.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Quit Native Chat", action: quitApplication)
                Button("Resume on This Mac", role: .destructive, action: coordinator.resumeChatOnMac)
            }
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private func working(title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(title).font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private func transferProgress(title: String, bytes: Int64, total: Int64?) -> some View {
        VStack(spacing: 16) {
            if let total, total > 0 {
                ProgressView(value: Double(bytes), total: Double(total))
                    .frame(maxWidth: 360)
                Text("\(Int(min(Double(bytes) / Double(total), 1) * 100))%")
                    .font(.title.monospacedDigit())
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 440, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Transfer failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: coordinator.resetFailure)
        }
    }

    private var title: String {
        coordinator.mode == .importFromPhone ? "Import from Phone" : "Export to Phone"
    }

    private var showsCancelButton: Bool {
        switch coordinator.phase {
        case .enterPassphrase, .openingDatabase, .exportComplete, .resumingChat, .importComplete:
            false
        default:
            true
        }
    }

    private func cancelAndDismiss() {
        Task {
            await coordinator.cancel()
            if case .failed = coordinator.phase { return }
            dismiss()
        }
    }

    private func quitApplication() {
        isQuitting = true
        dismiss()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct TransferQRCode: View {
    let value: String

    var body: some View {
        if let image = qrImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .padding(12)
                .background(.white)
                .clipShape(.rect(cornerRadius: 10))
        } else {
            ContentUnavailableView("QR code unavailable", systemImage: "qrcode")
        }
    }

    private var qrImage: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private struct QRCodeScannerView: NSViewRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError)
    }

    func makeNSView(context: Context) -> QRScannerPreviewView {
        let view = QRScannerPreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: QRScannerPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: QRScannerPreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private let onError: (String) -> Void
        private let sessionQueue = DispatchQueue(label: "io.github.ajzrva.nativechat.qr-scanner")
        private var session: AVCaptureSession?
        private var deliveredCode = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }

        func attach(to view: QRScannerPreviewView) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configure(view)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self, weak view] allowed in
                    DispatchQueue.main.async {
                        guard let self, let view else { return }
                        if allowed {
                            self.configure(view)
                        } else {
                            self.onError("Allow camera access in System Settings, or paste the archive link instead.")
                        }
                    }
                }
            case .denied, .restricted:
                onError("Allow camera access in System Settings, or paste the archive link instead.")
            @unknown default:
                onError("Camera access is unavailable. Paste the archive link instead.")
            }
        }

        func stop() {
            guard let session else { return }
            self.session = nil
            sessionQueue.async {
                if session.isRunning { session.stopRunning() }
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !deliveredCode,
                  let code = metadataObjects
                    .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                    .first(where: { $0.type == .qr })?
                    .stringValue else { return }
            deliveredCode = true
            onCode(code)
            stop()
        }

        private func configure(_ view: QRScannerPreviewView) {
            do {
                guard session == nil else { return }
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    onError("No camera is available. Paste the archive link instead.")
                    return
                }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                let session = AVCaptureSession()
                session.beginConfiguration()
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    onError("The camera could not scan QR codes. Paste the archive link instead.")
                    return
                }
                session.addInput(input)
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                self.session = session
                view.previewLayer.session = session
                sessionQueue.async { session.startRunning() }
            } catch {
                onError("The camera could not start: \(error.localizedDescription)")
            }
        }
    }
}

private final class QRScannerPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
