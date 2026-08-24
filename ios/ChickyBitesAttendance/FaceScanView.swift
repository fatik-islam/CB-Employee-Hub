import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import CoreML
import Vision
import UIKit

enum FaceScanMode {
    case enrollment(Employee)
    case verification
    case kiosk(Employee)

    var requiredSamples: Int {
        switch self { case .enrollment: 5; case .verification,.kiosk: 3 }
    }

    var title: String {
        switch self { case .enrollment: L10n.text("Enroll Employee Face"); case .verification: L10n.text("Verify Your Face");case .kiosk: L10n.text("Quick Face Check") }
    }
}

struct FaceScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let mode: FaceScanMode
    let onVerified: ((String) -> Void)?
    let onCaptured: (([[Float]], BiometricChallenge) -> Void)?
    @StateObject private var scanner: LiveFaceScanner
    @State private var enrollmentStatus: FaceTemplateStatus?
    @State private var submissionStarted = false
    @State private var challenge: BiometricChallenge?

    init(mode: FaceScanMode, onVerified: ((String) -> Void)? = nil, onCaptured: (([[Float]], BiometricChallenge) -> Void)? = nil) {
        self.mode = mode
        self.onVerified = onVerified
        self.onCaptured = onCaptured
        _scanner = StateObject(wrappedValue: LiveFaceScanner(
            requiredSamples: mode.requiredSamples,
            captureKind: mode.captureKind
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    CameraPreview(session: scanner.session)
                        .frame(maxWidth: .infinity)
                        .frame(height: 390)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    Ellipse()
                        .stroke(scanner.scanComplete ? CBTheme.success : scanner.faceAligned ? CBTheme.gold : .white,
                                style: StrokeStyle(lineWidth: 4, dash: scanner.faceAligned ? [] : [10, 8]))
                        .frame(width: 235, height: 300)

                    if scanner.scanComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(CBTheme.success)
                            .symbolEffect(.bounce, value: scanner.scanComplete)
                    }

                    VStack {
                        Spacer()
                        Text(L10n.text(scanner.instruction))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.black.opacity(0.62), in: Capsule())
                            .padding(.bottom, 18)
                    }
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    scanStep("Position", complete: scanner.faceAligned)
                    scanStep("Live check", complete: scanner.livenessComplete)
                    scanStep("Capture \(scanner.embeddings.count)/\(mode.requiredSamples)", complete: scanner.scanComplete)
                }

                if case .enrollment(let employee) = mode {
                    VStack(spacing: 4) {
                        Text(employee.fullName).font(.headline)
                        Text(employee.employeeCode).font(.caption).foregroundStyle(CBTheme.muted)
                        if enrollmentStatus?.enrolled == true {
                            Label("A face is enrolled. Saving will replace it.", systemImage: "person.crop.circle.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(CBTheme.info)
                                .padding(.top, 4)
                        }
                    }
                }
                if case .kiosk(let employee) = mode {
                    VStack(spacing: 4) {
                        Text(employee.fullName).font(.headline)
                        Text(employee.employeeCode).font(.caption).foregroundStyle(CBTheme.muted)
                    }
                }

                Text("No photo or video is saved. The scan automatically keeps only clear, consistent face measurements.")
                    .font(.caption)
                    .foregroundStyle(CBTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button(action: submit) {
                    Label {
                        Text(scanner.scanComplete ? primaryButtonTitle : L10n.text("Scanning Automatically…"))
                    } icon: {
                        Image(systemName: mode.requiredSamples == 5 ? "person.crop.circle.badge.checkmark" : "checkmark.shield.fill")
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .cbPrimaryButton()
                .disabled(!scanner.scanComplete || session.isWorking || submissionStarted)
                .padding(.horizontal, 16)

                if case .enrollment(let employee) = mode, enrollmentStatus?.enrolled == true {
                    Button("Remove Enrolled Face", role: .destructive) {
                        Task {
                            if await session.revokeFace(employeeId: employee.id, reason: "Removed by manager from employee profile") {
                                enrollmentStatus = FaceTemplateStatus(employeeId: employee.id, enrolled: false, enrolledAt: nil, modelVersion: nil)
                                scanner.reset()
                            }
                        }
                    }
                    .disabled(session.isWorking)
                }

                Spacer(minLength: 8)
            }
            .background(CBTheme.cream100.ignoresSafeArea())
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { scanner.stop() }
            .onChange(of: scanner.scanComplete) { _, complete in
                guard complete else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                submit()
            }
            .task {
                if case .enrollment(let employee) = mode {
                    enrollmentStatus = await session.faceStatus(employeeId: employee.id)
                    let actions=["blink_turn_left","blink_turn_right","turn_left_blink","turn_right_blink"]
                    scanner.configureChallenge(actions.randomElement()!)
                    scanner.start()
                } else if let issued = await session.biometricChallenge() {
                    challenge = issued
                    scanner.configureChallenge(issued.action)
                    scanner.start()
                } else {
                    let actions=["blink_turn_left","blink_turn_right","turn_left_blink","turn_right_blink"]
                    let local=BiometricChallenge(challengeId:UUID().uuidString,action:actions.randomElement()!,expiresAt:ISO8601DateFormatter().string(from:Date().addingTimeInterval(180)))
                    challenge=local
                    scanner.configureChallenge(local.action)
                    scanner.start()
                    session.successMessage="Offline recovery is ready. Your signed scan will sync after internet returns."
                }
            }
            .overlay { if session.isWorking { LoadingOverlay() } }
        }
    }

    private var primaryButtonTitle: String {
        switch mode { case .enrollment: L10n.text("Save Employee Face"); case .verification,.kiosk: L10n.text("Verify and Continue") }
    }

    private func scanStep(_ title: String, complete: Bool) -> some View {
        Label { Text(L10n.text(title)) } icon: { Image(systemName: complete ? "checkmark.circle.fill" : "circle") }
            .font(.caption.weight(.semibold))
            .foregroundStyle(complete ? CBTheme.success : CBTheme.muted)
    }

    private func submit() {
        guard !submissionStarted else { return }
        let summary = FaceEmbeddingMath.robustSummary(scanner.embeddings)
        guard summary.descriptor.count == 512, summary.samples.count == mode.requiredSamples else {
            session.errorMessage = "The face scan could not be prepared. Please scan again."
            scanner.reset()
            return
        }
        guard let liveness=scanner.livenessEvidence,liveness.passivePassed else {
            session.errorMessage="The live face check was incomplete. Please blink and turn naturally, then try again."
            scanner.reset()
            return
        }
        submissionStarted = true
        Task {
            let succeeded: Bool
            switch mode {
            case .enrollment(let employee):
                succeeded = await session.enrollFace(employeeId: employee.id, descriptors: summary.samples,liveness:liveness)
            case .verification:
                guard let challenge else {
                    session.errorMessage = "The face challenge expired. Please start again."
                    submissionStarted = false
                    return
                }
                if let proofId = await session.verifyFace(descriptors: summary.samples, challenge: challenge,liveness:liveness) {
                    onVerified?(proofId)
                    succeeded = true
                } else if let onCaptured, isConnectivityFailure(session.errorMessage) {
                    session.errorMessage=nil
                    onCaptured(summary.samples,challenge)
                    succeeded=true
                } else {
                    succeeded = false
                }
            case .kiosk(let employee):
                guard let challenge else {
                    session.errorMessage = "The face challenge expired. Please start again."
                    submissionStarted = false
                    return
                }
                if let proofId = await session.verifyFace(descriptors:summary.samples,challenge:challenge,liveness:liveness,kioskEmployeeId:employee.id) {
                    onVerified?(proofId)
                    succeeded=true
                } else { succeeded=false }
            }
            if succeeded { dismiss() }
            else {
                submissionStarted = false
                scanner.reset()
            }
        }
    }

    private func isConnectivityFailure(_ message:String?)->Bool {
        guard let message else{return false}
        return message.localizedCaseInsensitiveContains("network")
            || message.localizedCaseInsensitiveContains("internet")
            || message.localizedCaseInsensitiveContains("offline")
            || message.contains("-1009")
    }
}

private extension FaceScanMode {
    var captureKind: FaceCaptureKind {
        switch self { case .enrollment: .enrollment; case .verification,.kiosk: .verification }
    }
}

nonisolated enum FaceCaptureKind: Sendable {
    case enrollment
    case verification

    var sampleInterval: Double {
        switch self { case .enrollment: 0.26; case .verification: 0.18 }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

nonisolated final class LiveFaceScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    @Published nonisolated(unsafe) private(set) var instruction = "Position one face inside the oval"
    @Published nonisolated(unsafe) private(set) var faceAligned = false
    @Published nonisolated(unsafe) private(set) var blinkPassed = false
    @Published nonisolated(unsafe) private(set) var turnPassed = false
    @Published nonisolated(unsafe) private(set) var livenessComplete = false
    @Published nonisolated(unsafe) private(set) var scanComplete = false
    @Published nonisolated(unsafe) private(set) var embeddings: [[Float]] = []
    @Published nonisolated(unsafe) private(set) var livenessEvidence: BiometricLivenessEvidence?

    private let requiredSamples: Int
    private let captureKind: FaceCaptureKind
    private let sessionQueue = DispatchQueue(label: "pk.com.chickybites.face.session")
    private let frameQueue = DispatchQueue(label: "pk.com.chickybites.face.frames")
    private let engine = FaceEmbeddingEngine()
    private let visionHandler = VNSequenceRequestHandler()
    private var configured = false
    private var processing = false
    private var sawOpenEyes = false
    private var sawClosedEyes = false
    private var internalBlinkPassed = false
    private var internalTurnPassed = false
    private var collected: [[Float]] = []
    private var lastSampleTime = -Double.infinity
    private var frameCounter = 0
    private var finished = false
    private var stableFrames = 0
    private var lastFaceBox: CGRect?
    private var lastPublishedInstruction = ""
    private var challengeAction = "blink_turn_left"
    private var scanStartedAt:Double?
    private var qualifiedFrames=0
    private var eyeRatioMinimum=Double.greatestFiniteMagnitude
    private var eyeRatioMaximum=0.0
    private var yawMinimum=Double.greatestFiniteMagnitude
    private var yawMaximum = -Double.greatestFiniteMagnitude
    private var maxFrameJump=0.0
    private var accumulatedMotion=0.0

    init(requiredSamples: Int, captureKind: FaceCaptureKind) {
        self.requiredSamples = requiredSamples
        self.captureKind = captureKind
        super.init()
    }

    func configureChallenge(_ action:String) {
        frameQueue.async { [weak self] in
            self?.challengeAction = action
            let direction=action.contains("left") ? "left":"right"
            self?.publishInstruction(action.hasPrefix("blink_") ? "Blink once, then turn your head \(direction)":"Turn your head \(direction), then blink once")
        }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                if allowed { self?.configureAndStart() }
                else { self?.publishInstruction("Camera access is required for live face verification") }
            }
        default: publishInstruction("Enable camera access in iPhone Settings to continue")
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func reset() {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.sawOpenEyes = false
            self.sawClosedEyes = false
            self.internalBlinkPassed = false
            self.internalTurnPassed = false
            self.collected = []
            self.lastSampleTime = -Double.infinity
            self.finished = false
            self.stableFrames = 0
            self.lastFaceBox = nil
            self.lastPublishedInstruction = ""
            self.scanStartedAt=nil
            self.qualifiedFrames=0
            self.eyeRatioMinimum=Double.greatestFiniteMagnitude
            self.eyeRatioMaximum=0
            self.yawMinimum=Double.greatestFiniteMagnitude
            self.yawMaximum = -Double.greatestFiniteMagnitude
            self.maxFrameJump=0
            self.accumulatedMotion=0
            DispatchQueue.main.async {
                self.faceAligned = false
                self.blinkPassed = false
                self.turnPassed = false
                self.livenessComplete = false
                self.scanComplete = false
                self.embeddings = []
                self.livenessEvidence=nil
                self.instruction = "Position one face inside the oval"
            }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                defer { self.session.commitConfiguration() }

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.session.canAddInput(input) else {
                    self.publishInstruction("The front camera is unavailable")
                    return
                }
                if (try? camera.lockForConfiguration()) != nil {
                    if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                    if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                    if camera.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 24 && $0.maxFrameRate >= 24 }) {
                        camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 24)
                        camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 24)
                    }
                    camera.unlockForConfiguration()
                }
                self.session.addInput(input)

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.frameQueue)
                guard self.session.canAddOutput(output) else {
                    self.publishInstruction("The camera could not start")
                    return
                }
                self.session.addOutput(output)
                if let connection = output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    connection.isVideoMirrored = true
                    if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
                }
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !finished, !processing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameCounter += 1
        let cadence = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical ? 4 : 2
        guard frameCounter.isMultiple(of: cadence) else { return }
        processing = true
        defer { processing = false }

        let request = VNDetectFaceLandmarksRequest()
        guard (try? visionHandler.perform([request], on: pixelBuffer, orientation: .up)) != nil,
              let faces = request.results, faces.count == 1,
              let face = faces.first,
              let landmarks = face.landmarks else {
            publishAligned(false)
            stableFrames = 0
            lastFaceBox = nil
            publishInstruction("Keep one face clearly inside the oval")
            return
        }

        guard faceIsWellPositioned(face) else {
            publishAligned(false)
            stableFrames = 0
            lastFaceBox = face.boundingBox
            publishInstruction(positionInstruction(for: face))
            return
        }
        publishAligned(true)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if scanStartedAt == nil { scanStartedAt=timestamp }
        qualifiedFrames += 1
        updateStability(with: face.boundingBox)

        let eyeRatio = Double(averageEyeRatio(landmarks))
        eyeRatioMinimum=min(eyeRatioMinimum,eyeRatio);eyeRatioMaximum=max(eyeRatioMaximum,eyeRatio)
        let detectedYaw = face.yaw?.doubleValue ?? 0
        yawMinimum=min(yawMinimum,detectedYaw);yawMaximum=max(yawMaximum,detectedYaw)
        let blinkFirst=challengeAction.hasPrefix("blink_")
        if !internalBlinkPassed {
            if eyeRatio > 0.16 { sawOpenEyes = true }
            if sawOpenEyes && eyeRatio < 0.12 { sawClosedEyes = true }
            if sawClosedEyes && eyeRatio > 0.16 {
                if blinkFirst || internalTurnPassed {
                    internalBlinkPassed = true
                    DispatchQueue.main.async { self.blinkPassed = true }
                } else {
                    sawOpenEyes=false;sawClosedEyes=false
                }
            }
        }

        let directedTurnPassed = challengeAction.contains("left") ? detectedYaw < -0.10 : detectedYaw > 0.10
        if directedTurnPassed && (!blinkFirst || internalBlinkPassed) {
            internalTurnPassed = true
            DispatchQueue.main.async { self.turnPassed = true }
        }

        if !internalBlinkPassed || !internalTurnPassed {
            let direction = challengeAction.contains("left") ? "left" : "right"
            let missing = !internalBlinkPassed && !internalTurnPassed
                ? (blinkFirst ? "Blink once, then gently turn \(direction)":"Gently turn \(direction), then blink once")
                : (!internalBlinkPassed ? "Blink once" : "Gently turn \(direction)")
            publishInstruction(missing)
            return
        }

        let yaw = abs(detectedYaw)
        guard yaw < 0.13, eyeRatio > 0.14 else {
            publishInstruction("Look straight at the camera")
            return
        }
        guard stableFrames >= 2 else {
            publishInstruction("Hold still for a moment")
            return
        }
        let evidence=makeLivenessEvidence(timestamp:timestamp)
        guard evidence.passivePassed else {
            DispatchQueue.main.async { self.livenessComplete=false;self.livenessEvidence=nil }
            publishInstruction("Move naturally, then look straight at the camera")
            return
        }
        DispatchQueue.main.async { self.livenessComplete = true;self.livenessEvidence=evidence }

        guard timestamp - lastSampleTime >= captureKind.sampleInterval else { return }
        lastSampleTime = timestamp
        guard let embedding = engine.embedding(pixelBuffer: pixelBuffer, face: face, orientation: .up) else {
            publishInstruction("Move into even lighting and try again")
            return
        }
        if !collected.isEmpty,
           FaceEmbeddingMath.cosine(embedding, FaceEmbeddingMath.average(collected)) < 0.42 {
            publishInstruction("Hold still in even light — recapturing")
            return
        }
        collected.append(embedding)
        let snapshot = collected
        let complete = snapshot.count >= requiredSamples
        DispatchQueue.main.async {
            self.embeddings = snapshot
            self.livenessComplete = true
            self.scanComplete = complete
            self.instruction = complete ? "Face verified" : "Capturing automatically \(snapshot.count)/\(self.requiredSamples)"
            UISelectionFeedbackGenerator().selectionChanged()
        }
        if complete { finished = true }
    }

    private func faceIsWellPositioned(_ face: VNFaceObservation) -> Bool {
        let box = face.boundingBox
        let center = CGPoint(x: box.midX, y: box.midY)
        return face.confidence >= 0.82
            && box.width >= 0.27 && box.width <= 0.70
            && box.height >= 0.27 && box.height <= 0.75
            && center.x >= 0.32 && center.x <= 0.68
            && center.y >= 0.27 && center.y <= 0.73
            && abs(face.roll?.doubleValue ?? 0) < 0.22
    }

    private func positionInstruction(for face: VNFaceObservation) -> String {
        let box = face.boundingBox
        if box.width < 0.27 { return "Move a little closer" }
        if box.width > 0.70 { return "Move a little farther away" }
        if box.midX < 0.32 { return "Move your face slightly right" }
        if box.midX > 0.68 { return "Move your face slightly left" }
        if box.midY < 0.27 { return "Raise the phone slightly" }
        if box.midY > 0.73 { return "Lower the phone slightly" }
        return "Keep your head upright in the oval"
    }

    private func updateStability(with box: CGRect) {
        defer { lastFaceBox = box }
        guard let previous = lastFaceBox else { stableFrames = 0; return }
        let centerMovement = hypot(box.midX - previous.midX, box.midY - previous.midY)
        let sizeMovement = abs(box.width - previous.width) + abs(box.height - previous.height)
        let jump=Double(centerMovement + sizeMovement)
        maxFrameJump=max(maxFrameJump,jump)
        accumulatedMotion += min(jump,0.08)
        stableFrames = centerMovement < 0.028 && sizeMovement < 0.045 ? min(stableFrames + 1, 8) : 0
    }

    private func makeLivenessEvidence(timestamp:Double)->BiometricLivenessEvidence {
        let duration=max(0,timestamp-(scanStartedAt ?? timestamp))
        let blinkAmplitude=max(0,eyeRatioMaximum-eyeRatioMinimum)
        let turnAmplitude=max(0,yawMaximum-yawMinimum)
        let motionScore=min(1,(turnAmplitude/0.16)*0.45 + (blinkAmplitude/0.08)*0.40 + (accumulatedMotion/0.08)*0.15)
        let orderPassed=internalBlinkPassed && internalTurnPassed
        let passivePassed=duration >= 0.65 && duration <= 15 && qualifiedFrames >= 8 && maxFrameJump <= 0.16
            && blinkAmplitude >= 0.035 && turnAmplitude >= 0.10 && motionScore >= 0.58 && orderPassed
        return BiometricLivenessEvidence(
            captureDurationMs:Int((duration*1000).rounded()),qualifiedFrames:qualifiedFrames,
            naturalMotionScore:motionScore,maxFrameJump:maxFrameJump,blinkAmplitude:blinkAmplitude,
            turnAmplitude:turnAmplitude,challengeOrderPassed:orderPassed,passivePassed:passivePassed
        )
    }

    private func averageEyeRatio(_ landmarks: VNFaceLandmarks2D) -> CGFloat {
        let ratios = [landmarks.leftEye, landmarks.rightEye].compactMap { eye -> CGFloat? in
            guard let points = eye?.normalizedPoints, points.count >= 4 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX > minX else { return nil }
            return (maxY - minY) / (maxX - minX)
        }
        return ratios.isEmpty ? 1 : ratios.reduce(0, +) / CGFloat(ratios.count)
    }

    private func publishInstruction(_ value: String) {
        guard value != lastPublishedInstruction else { return }
        lastPublishedInstruction = value
        DispatchQueue.main.async {
            if !self.finished { self.instruction = value }
        }
    }

    private func publishAligned(_ value: Bool) {
        DispatchQueue.main.async {
            if self.faceAligned != value { self.faceAligned = value }
        }
    }
}

nonisolated private final class FaceEmbeddingEngine {
    private static let targetPoints: [(CGFloat, CGFloat)] = [
        (38.2946, 51.6963), (73.5318, 51.5014), (56.0252, 71.7366),
        (41.5493, 92.3655), (70.7299, 92.2041)
    ]
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let model: MLModel?

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        if let url = Bundle.main.url(forResource: "AdaFace_IR18", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: url, configuration: configuration)
        } else {
            model = nil
        }
    }

    func embedding(pixelBuffer: CVPixelBuffer, face: VNFaceObservation, orientation: CGImagePropertyOrientation) -> [Float]? {
        guard let landmarks = face.landmarks else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard let aligned = align(image: image, face: face, landmarks: landmarks) else { return nil }
        guard let model,
              let input = try? MLDictionaryFeatureProvider(dictionary: ["face_image": MLFeatureValue(pixelBuffer: aligned)]),
              let output = try? model.prediction(from: input),
              let values = output.featureValue(for: "embedding")?.multiArrayValue,
              values.count == 512 else { return nil }
        return FaceEmbeddingMath.normalize((0..<values.count).map { values[$0].floatValue })
    }

    private func align(image: CIImage, face: VNFaceObservation, landmarks: VNFaceLandmarks2D) -> CVPixelBuffer? {
        guard let source = fivePoints(face: face, landmarks: landmarks, size: image.extent.size),
              let matrix = affine(source: source, destination: Self.targetPoints) else { return nil }
        let transform = CGAffineTransform(a: matrix[0], b: matrix[3], c: matrix[1], d: matrix[4], tx: matrix[2], ty: matrix[5])
        let transformed = image.transformed(by: transform)
        var output: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 112, 112, kCVPixelFormatType_32BGRA, attributes, &output)
        guard let output else { return nil }
        context.render(transformed, to: output, bounds: CGRect(x: 0, y: 0, width: 112, height: 112), colorSpace: CGColorSpaceCreateDeviceRGB())
        return output
    }

    private func fivePoints(face: VNFaceObservation, landmarks: VNFaceLandmarks2D, size: CGSize) -> [(CGFloat, CGFloat)]? {
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.noseCrest,
              let lips = landmarks.outerLips else { return nil }
        let box = face.boundingBox
        func pixel(_ points: [CGPoint]) -> CGPoint {
            let sum = points.reduce(.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            let count = CGFloat(points.count)
            return CGPoint(
                x: (box.minX + (sum.x / count) * box.width) * size.width,
                y: (box.minY + (sum.y / count) * box.height) * size.height
            )
        }
        let nosePoints = nose.normalizedPoints
        let lipPoints = lips.normalizedPoints
        guard !nosePoints.isEmpty, lipPoints.count >= 2 else { return nil }
        let points = [
            pixel(leftEye.normalizedPoints),
            pixel(rightEye.normalizedPoints),
            pixel([nosePoints.last!]),
            pixel([lipPoints[0]]),
            pixel([lipPoints[lipPoints.count / 2]])
        ]
        return points.map { ($0.x, $0.y) }
    }

    private func affine(source: [(CGFloat, CGFloat)], destination: [(CGFloat, CGFloat)]) -> [CGFloat]? {
        let count = min(source.count, destination.count)
        guard count >= 3 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: 6), count: count * 2)
        var b = [Double](repeating: 0, count: count * 2)
        for index in 0..<count {
            let x = Double(source[index].0), y = Double(source[index].1)
            a[index * 2] = [x, y, 1, 0, 0, 0]
            a[index * 2 + 1] = [0, 0, 0, x, y, 1]
            b[index * 2] = Double(destination[index].0)
            b[index * 2 + 1] = Double(destination[index].1)
        }
        return solve(a: a, b: b)?.map { CGFloat($0) }
    }

    private func solve(a: [[Double]], b: [Double]) -> [Double]? {
        let n = 6, m = a.count
        var normal = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        var right = [Double](repeating: 0, count: n)
        for row in 0..<n {
            for column in 0..<n { for index in 0..<m { normal[row][column] += a[index][row] * a[index][column] } }
            for index in 0..<m { right[row] += a[index][row] * b[index] }
        }
        for column in 0..<n {
            var pivot = column
            for row in column..<n where abs(normal[row][column]) > abs(normal[pivot][column]) { pivot = row }
            guard abs(normal[pivot][column]) > 1e-12 else { return nil }
            normal.swapAt(column, pivot); right.swapAt(column, pivot)
            for row in (column + 1)..<n {
                let factor = normal[row][column] / normal[column][column]
                for index in column..<n { normal[row][index] -= factor * normal[column][index] }
                right[row] -= factor * right[column]
            }
        }
        var result = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var value = right[row]
            for column in (row + 1)..<n { value -= normal[row][column] * result[column] }
            result[row] = value / normal[row][row]
        }
        return result
    }
}

nonisolated enum FaceEmbeddingMath {
    struct Summary: Sendable {
        let descriptor: [Float]
        let samples: [[Float]]
        let consistency: Float
    }

    static func normalize(_ values: [Float]) -> [Float] {
        let magnitude = sqrt(values.reduce(Float.zero) { $0 + $1 * $1 })
        guard magnitude > 0 else { return [] }
        return values.map { $0 / magnitude }
    }

    static func average(_ samples: [[Float]]) -> [Float] {
        guard !samples.isEmpty, samples.allSatisfy({ $0.count == 512 }) else { return [] }
        var result = [Float](repeating: 0, count: 512)
        for sample in samples { for index in result.indices { result[index] += sample[index] } }
        return normalize(result.map { $0 / Float(samples.count) })
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == 512, rhs.count == 512 else { return -1 }
        return zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
    }

    static func robustSummary(_ input: [[Float]]) -> Summary {
        let normalized = input.map(normalize).filter { $0.count == 512 }
        guard !normalized.isEmpty else { return Summary(descriptor: [], samples: [], consistency: 0) }

        let medoidIndex = normalized.indices.max { left, right in
            averageSimilarity(of: normalized[left], in: normalized) < averageSimilarity(of: normalized[right], in: normalized)
        } ?? normalized.startIndex
        let medoid = normalized[medoidIndex]
        let accepted = normalized.filter { cosine($0, medoid) >= 0.42 }
        guard !accepted.isEmpty else { return Summary(descriptor: [], samples: [], consistency: 0) }

        let pairScores = accepted.indices.flatMap { left in
            accepted.indices.compactMap { right in left < right ? cosine(accepted[left], accepted[right]) : nil }
        }
        let consistency = pairScores.isEmpty ? 1 : pairScores.reduce(0, +) / Float(pairScores.count)
        return Summary(descriptor: average(accepted), samples: accepted, consistency: consistency)
    }

    private static func averageSimilarity(of candidate: [Float], in samples: [[Float]]) -> Float {
        guard samples.count > 1 else { return 1 }
        return samples.reduce(Float.zero) { $0 + cosine(candidate, $1) } / Float(samples.count)
    }
}
