import SwiftUI
import AVFoundation
import MetalKit
import MediaPlayer

struct CameraView: UIViewControllerRepresentable {
    var imageHandler: (UIImage) -> Void
    var selectedFilter: FilterType
    var enableLiveFilter: Bool
    
    @AppStorage("disableSelfieMirroring") private var disableSelfieMirroring: Bool = false
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.imageHandler = imageHandler
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        uiViewController.selectedFilter = selectedFilter
        uiViewController.enableLiveFilter = enableLiveFilter
        uiViewController.disableSelfieMirroring = self.disableSelfieMirroring
    }
}

extension Notification.Name {
    static let takePhoto = Notification.Name("takePhoto")
    static let setFlashMode = Notification.Name("setFlashMode")
    static let switchCamera = Notification.Name("switchCamera")
    static let setZoom = Notification.Name("setZoom")
    static let cycleTimer = Notification.Name("cycleTimer")
}


class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, MTKViewDelegate {
    
    var imageHandler: ((UIImage) -> Void)?
    
    private var captureSession: AVCaptureSession!
    private var photoOutput: AVCapturePhotoOutput!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var currentDeviceInput: AVCaptureDeviceInput?
    
    private var metalView: MTKView!
    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var currentCIImage: CIImage? {
        didSet {
            DispatchQueue.main.async {
                self.metalView.setNeedsDisplay()
            }
        }
    }
    
    private var shutterView: UIView!
    private var countdownLabel: UILabel!
    
    private var focusIndicatorView: UIView!
    private var exposureSlider: ExposureSliderView!
    private var initialExposureBias: Float = 0.0
    private var currentExposureValue: Double = 0.5
    
    private var initialZoomFactor: CGFloat = 1.0
    private let displayMaxZoom: CGFloat = 50.0
    private var initialDisplayZoom: CGFloat = 1.0
    
    private enum FlashMode: CaseIterable {
        case off, on, auto
        var avFlashMode: AVCaptureDevice.FlashMode {
            switch self {
                case .off: .off
                case .on: .on
                case .auto: .auto
            }
        }
    }
    private var flashMode: FlashMode = .off
    
    @AppStorage("lastTimerIndex") private var timerIndex: Int = 0
    private let timerOptions: [Int] = [0, 3, 5]
    private var currentTimer: Int { timerOptions[timerIndex] }
    
    @AppStorage("lastAspectIndex") private var aspectIndex: Int = 0
    private enum AspectRatio: CaseIterable {
        case r3x4, r9x16
        var ratio: CGFloat {
            switch self {
                case .r3x4: 3.0/4.0
                case .r9x16: 9.0/16.0
            }
        }
        static func forIndex(_ index: Int) -> AspectRatio {
            guard index >= 0 && index < Self.allCases.count else { return .r3x4 }
            return Self.allCases[index]
        }
    }
    
    var selectedFilter: FilterType = .normal { didSet { updateCurrentFilter() } }
    var enableLiveFilter: Bool = false { didSet { updateCurrentFilter() } }
    private var currentFilter: CIFilter?
    
    private var observers: [NSObjectProtocol] = []
    
    var disableSelfieMirroring: Bool = false
    
    @AppStorage("lastCameraPosition") private var lastCameraPosition: String = "back"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupMetalView()
        setupShutterView()
        setupSession()
        setupCountdownLabel()
        addNotificationObservers()
        setupFocusIndicator()
        setupExposureSlider()
        setupGestureRecognizers()
        hideSystemVolumeHUD()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
        setupVolumeShutter()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        VolumeShutterManager.shared.stopObserving()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView.frame = view.bounds
        
        if let slider = exposureSlider {
            let sliderWidth: CGFloat = 40
            let sliderHeight: CGFloat = 180
            let sliderX: CGFloat = 20
            let sliderY = (view.bounds.height - sliderHeight) / 2
            slider.frame = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
        }
    }
    
    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        captureSession?.stopRunning()
        VolumeShutterManager.shared.stopObserving()
    }
    
    private func setupShutterView() {
        shutterView = UIView(frame: view.bounds)
        shutterView.backgroundColor = .black
        shutterView.alpha = 0
        shutterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(shutterView)
    }
    
    private func hideSystemVolumeHUD() {
        let volumeView = MPVolumeView()
        volumeView.frame = CGRect(x: -1000, y: -1000, width: 1, height: 1)
        volumeView.clipsToBounds = true
        view.addSubview(volumeView)
    }
    
    private func setupVolumeShutter() {
        VolumeShutterManager.shared.shutterAction = { [weak self] in
            self?.startCaptureSequence()
        }
        VolumeShutterManager.shared.startObserving()
    }
    
    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal is not supported") }
        
        metalView = MTKView(frame: view.bounds, device: device)
        metalView.delegate = self
        metalView.enableSetNeedsDisplay = true
        metalView.framebufferOnly = false
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(metalView)
        
        ciContext = CIContext(mtlDevice: device)
        commandQueue = device.makeCommandQueue()!
    }
    
    private func setupSession() {
        captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        let initialPosition: AVCaptureDevice.Position = (lastCameraPosition == "front") ? .front : .back
        
        guard let camera = CameraViewController.findDevice(position: initialPosition) else {
            print("No camera available for last used position. Trying alternate.")
            let alternatePosition: AVCaptureDevice.Position = (initialPosition == .back) ? .front : .back
            guard let fallbackCamera = CameraViewController.findDevice(position: alternatePosition) else {
                print("No cameras found on device.")
                captureSession.commitConfiguration()
                return
            }
            lastCameraPosition = fallbackCamera.position == .back ? "back" : "front"
            setupDeviceInput(for: fallbackCamera)
            captureSession.commitConfiguration()
            return
        }
        
        setupDeviceInput(for: camera)
        
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        photoOutput = AVCapturePhotoOutput()
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }
        
        photoOutput.isHighResolutionCaptureEnabled = false
        if #available(iOS 16.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .speed
        }
        
        updateVideoOutputConnection()
        
        captureSession.commitConfiguration()
    }
    
    private func setupDeviceInput(for device: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentDeviceInput = input
                DispatchQueue.main.async {
                    CameraManager.shared.updateCameraState(for: device)
                }
            }
        } catch {
            print("Error creating camera input for device \(device): \(error)")
        }
    }
    
    private func updateVideoOutputConnection() {
        guard let connection = self.videoOutput.connection(with: .video) else { return }
        
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        if connection.isVideoMirroringSupported {
            let isFrontCamera = (self.currentDeviceInput?.device.position == .front)
            connection.isVideoMirrored = isFrontCamera
        }
    }
    
    private func setupCountdownLabel() {
        countdownLabel = UILabel()
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.textAlignment = .center
        countdownLabel.font = .systemFont(ofSize: 100, weight: .light)
        countdownLabel.textColor = .white
        countdownLabel.isHidden = true
        view.addSubview(countdownLabel)
        
        NSLayoutConstraint.activate([
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func startSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                let initialZoom = CameraManager.shared.currentZoomFactor
                self.setZoom(factor: initialZoom, isInitialSet: true)
            }
        }
    }
    
    private func addNotificationObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .takePhoto, object: nil, queue: .main) { [weak self] _ in self?.startCaptureSequence() })
        
        observers.append(center.addObserver(forName: .setFlashMode, object: nil, queue: .main) { [weak self] notification in
            if let index = notification.userInfo?["flashIndex"] as? Int {
                self?.setFlashMode(index: index)
            }
        })
        
        observers.append(center.addObserver(forName: .switchCamera, object: nil, queue: .main) { [weak self] _ in self?.switchCamera() })
        observers.append(center.addObserver(forName: .cycleTimer, object: nil, queue: .main) { [weak self] _ in self?.cycleTimer() })
        
        observers.append(center.addObserver(forName: .setZoom, object: nil, queue: .main) { [weak self] note in
            if let zoom = note.userInfo?["zoom"] as? Double {
                self?.setZoom(factor: CGFloat(zoom))
            }
        })
    }
    
    private func setFlashMode(index: Int) {
        guard index >= 0 && index < FlashMode.allCases.count else { return }
        self.flashMode = FlashMode.allCases[index]
    }
    
    private func cycleTimer() {
        timerIndex = (timerIndex + 1) % timerOptions.count
    }
    
    private func setZoom(factor: CGFloat, isInitialSet: Bool = false) {
        guard let device = currentDeviceInput?.device else { return }
        do {
            try device.lockForConfiguration()
            let newZoomFactor = max(device.minAvailableVideoZoomFactor, min(factor, device.activeFormat.videoMaxZoomFactor))
            
            if isInitialSet {
                device.videoZoomFactor = newZoomFactor
            } else {
                device.ramp(toVideoZoomFactor: newZoomFactor, withRate: 5.0)
            }
            
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                CameraManager.shared.currentZoomFactor = factor
            }
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }
    
    private func switchCamera() {
        guard let currentInput = currentDeviceInput else { return }
        
        let oldPosition = currentInput.device.position
        
        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)
        
        let newPosition: AVCaptureDevice.Position = (oldPosition == .back) ? .front : .back
        
        if oldPosition == .back && newPosition == .front {
            let backCameraDefaultZoom = CameraManager.shared.defaultZoomFactor
            UserDefaults.standard.set(backCameraDefaultZoom, forKey: "lastZoomFactor_back")
        }
        
        lastCameraPosition = (newPosition == .back) ? "back" : "front"
        
        if let newDevice = CameraViewController.findDevice(position: newPosition),
           let newInput = try? AVCaptureDeviceInput(device: newDevice),
           captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            currentDeviceInput = newInput
            CameraManager.shared.updateCameraState(for: newDevice)
        } else {
            captureSession.addInput(currentInput)
        }
        
        updateVideoOutputConnection()
        
        captureSession.commitConfiguration()
        
        let newZoom = CameraManager.shared.currentZoomFactor
        self.setZoom(factor: newZoom, isInitialSet: true)
    }
    
    private func startCaptureSequence() {
        if currentTimer > 0 {
            startCountdown(seconds: currentTimer)
        } else {
            captureNow()
        }
    }
    
    private func startCountdown(seconds: Int) {
        countdownLabel.isHidden = false
        var remaining = seconds
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if remaining > 0 {
                self.countdownLabel.text = "\(remaining)"
                remaining -= 1
            } else {
                self.countdownLabel.isHidden = true
                self.captureNow()
                timer.invalidate()
            }
        }
    }
    
    private func captureNow() {
        triggerShutterAnimation()
        
        PhotoManager.shared.lastCapturedExposure = self.currentExposureValue
        
        let settings = AVCapturePhotoSettings()
        if #available(iOS 15.0, *) {
            settings.photoQualityPrioritization = .speed
        }
        settings.isHighResolutionPhotoEnabled = false
        
        if let photoOutputConnection = self.photoOutput.connection(with: .video) {
            photoOutputConnection.videoOrientation = .portrait
            if photoOutputConnection.isVideoMirroringSupported {
                let isFrontCamera = (self.currentDeviceInput?.device.position == .front)
                photoOutputConnection.isVideoMirrored = isFrontCamera && !self.disableSelfieMirroring
            }
        }
        
        if let device = currentDeviceInput?.device, device.isFlashAvailable, photoOutput.supportedFlashModes.contains(flashMode.avFlashMode) {
            settings.flashMode = flashMode.avFlashMode
        } else {
            settings.flashMode = .off
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func triggerShutterAnimation() {
        DispatchQueue.main.async {
            self.shutterView.alpha = 1.0
            UIView.animate(withDuration: 0.5, delay: 0.15, options: .curveEaseOut, animations: {
                self.shutterView.alpha = 0.0
            }, completion: nil)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self,
                  let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data)?.fixedOrientation() else {
                print("Could not get image from photo data.")
                return
            }
            let currentAspectRatio = AspectRatio.forIndex(self.aspectIndex).ratio
            var viewBounds: CGRect = .zero
            var innerRect: CGRect = .zero
            DispatchQueue.main.sync {
                viewBounds = self.metalView.bounds
                innerRect = self.innerCropRect(for: currentAspectRatio, in: viewBounds)
            }
            let croppedImage = self.cropImageToAspect(image, aspect: currentAspectRatio, viewBounds: viewBounds, innerCropRect: innerRect) ?? image
            DispatchQueue.main.async {
                self.imageHandler?(croppedImage)
            }
        }
    }
    
    private func updateCurrentFilter() {
        if enableLiveFilter && selectedFilter != .normal {
            currentFilter = FilterUtils.createColorCubeFilter(for: selectedFilter)
        } else {
            currentFilter = nil
        }
    }
    
    /// Crop using pre-captured view rects (call from background; capture viewBounds/innerCropRect on main first).
    private func cropImageToAspect(_ image: UIImage, aspect: CGFloat, viewBounds: CGRect, innerCropRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let previewSize = viewBounds.size
        let imageAspect = imageSize.width / imageSize.height
        let previewAspect = previewSize.width / previewSize.height
        
        var drawRect = CGRect.zero
        
        if imageAspect > previewAspect {
            let scale = previewSize.height / imageSize.height
            let scaledWidth = imageSize.width * scale
            let xOffset = (scaledWidth - previewSize.width) / 2.0
            let originX = (innerCropRect.minX + xOffset) / scaledWidth * imageSize.width
            let originY = innerCropRect.minY / previewSize.height * imageSize.height
            let width = innerCropRect.width / scaledWidth * imageSize.width
            let height = innerCropRect.height / previewSize.height * imageSize.height
            drawRect = CGRect(x: originX, y: originY, width: width, height: height)
        } else {
            let scale = previewSize.width / imageSize.width
            let scaledHeight = imageSize.height * scale
            let yOffset = (scaledHeight - previewSize.height) / 2.0
            let originX = innerCropRect.minX / previewSize.width * imageSize.width
            let originY = (innerCropRect.minY + yOffset) / scaledHeight * imageSize.height
            let width = innerCropRect.width / previewSize.width * imageSize.width
            let height = innerCropRect.height / scaledHeight * imageSize.height
            drawRect = CGRect(x: originX, y: originY, width: width, height: height)
        }
        
        guard let croppedCG = cgImage.cropping(to: drawRect.integral) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func innerCropRect(for ratio: CGFloat, in bounds: CGRect) -> CGRect {
        let boundsRatio = bounds.width / bounds.height
        var width: CGFloat, height: CGFloat
        if ratio > boundsRatio {
            width = bounds.width
            height = width / ratio
        } else {
            height = bounds.height
            width = height * ratio
        }
        let x = (bounds.width - width) / 2.0
        let y = (bounds.height - height) / 2.0
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        if let filter = currentFilter {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let outputImage = filter.outputImage {
                ciImage = outputImage
            }
        }
        
        currentCIImage = ciImage
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let image = currentCIImage,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let bounds = CGRect(origin: .zero, size: view.drawableSize)
        
        let scaleX = bounds.width / image.extent.width
        let scaleY = bounds.height / image.extent.height
        let scale = max(scaleX, scaleY)
        
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        let originX = (scaledImage.extent.width - bounds.width) / 2
        let originY = (scaledImage.extent.height - bounds.height) / 2
        let centeredImage = scaledImage.transformed(by: CGAffineTransform(translationX: -originX, y: -originY))
        
        ciContext.render(centeredImage,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: bounds,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private static func findDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera
        ]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first
    }
    
    private func setupFocusIndicator() {
        focusIndicatorView = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        focusIndicatorView.layer.borderColor = UIColor.yellow.cgColor
        focusIndicatorView.layer.borderWidth = 2
        focusIndicatorView.layer.cornerRadius = 8
        focusIndicatorView.backgroundColor = .clear
        focusIndicatorView.alpha = 0
        view.addSubview(focusIndicatorView)
    }
    
    private func setupExposureSlider() {
        exposureSlider = ExposureSliderView(frame: .zero)
        exposureSlider.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin, .flexibleBottomMargin]
        exposureSlider.alpha = 0
        view.addSubview(exposureSlider)
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        metalView.addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanForExposure(_:)))
        metalView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
        metalView.addGestureRecognizer(pinchGesture)
    }
    
    @objc private func handleTapToFocus(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: metalView)
        showFocusIndicator(at: location)
        
        let devicePoint = CGPoint(x: location.y / metalView.bounds.height,
                                  y: 1.0 - location.x / metalView.bounds.width)
        
        focus(at: devicePoint)
    }
    
    private func showFocusIndicator(at point: CGPoint) {
        focusIndicatorView.center = point
        focusIndicatorView.alpha = 1
        focusIndicatorView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        
        UIView.animate(withDuration: 0.5, delay: 0.5, options: .curveEaseOut, animations: {
            self.focusIndicatorView.alpha = 0
            self.focusIndicatorView.transform = .identity
        }, completion: nil)
    }
    
    private func focus(at point: CGPoint) {
        guard let device = currentDeviceInput?.device else { return }
        
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            
            self.currentExposureValue = 0.5
            self.exposureSlider.setProgress(0.5)
            
        } catch {
            print("Failed to lock device for focus configuration: \(error)")
        }
    }
    
    @objc private func handlePanForExposure(_ recognizer: UIPanGestureRecognizer) {
        guard let device = currentDeviceInput?.device else { return }
        
        switch recognizer.state {
            case .began:
                do {
                    try device.lockForConfiguration()
                    initialExposureBias = device.exposureTargetBias
                    UIView.animate(withDuration: 0.3) { self.exposureSlider.alpha = 1.0 }
                } catch {
                    print("Failed to lock device for exposure configuration: \(error)")
                    return
                }
                
            case .changed:
                let translation = recognizer.translation(in: view)
                
                let fullRange = device.maxExposureTargetBias - device.minExposureTargetBias
                let change = -CGFloat(fullRange) * (translation.y / (view.bounds.height / 2.0))
                
                let newBias = initialExposureBias + Float(change)
                let clampedBias = max(device.minExposureTargetBias, min(newBias, device.maxExposureTargetBias))
                
                device.setExposureTargetBias(clampedBias, completionHandler: nil)
                
                if fullRange > 0 {
                    let normalizedBias = (clampedBias - device.minExposureTargetBias) / fullRange
                    self.currentExposureValue = Double(normalizedBias)
                    exposureSlider.setProgress(CGFloat(normalizedBias))
                }
                
            case .ended, .cancelled:
                device.unlockForConfiguration()
                UIView.animate(withDuration: 0.3, delay: 1.0, options: .curveEaseOut, animations: {
                    self.exposureSlider.alpha = 0.0
                }, completion: nil)
                
            default:
                break
        }
    }
    
    @objc private func handlePinchToZoom(_ recognizer: UIPinchGestureRecognizer) {
        
        guard let device = currentDeviceInput?.device else { return }
        
        switch recognizer.state {
            case .began:
                initialZoomFactor = device.videoZoomFactor
                
            case .changed:
                let newZoomFactor = initialZoomFactor * recognizer.scale
                let clampedZoomFactor = max(device.minAvailableVideoZoomFactor, min(newZoomFactor, self.displayMaxZoom))
                
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = clampedZoomFactor
                    device.unlockForConfiguration()
                    
                    DispatchQueue.main.async {
                        CameraManager.shared.currentZoomFactor = clampedZoomFactor
                    }
                } catch {
                    print("Failed to lock device for pinch zoom: \(error)")
                }
                
            case .ended, .cancelled:
                DispatchQueue.main.async {
                    CameraManager.shared.currentZoomFactor = device.videoZoomFactor
                }
            default:
                break
        }
    }
    
    
}

private class ExposureSliderView: UIView {
    
    private let trackView = UIView()
    private let progressView = UIView()
    private let sunIcon = UIImageView()
    private let progressLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.25)
        layer.cornerRadius = bounds.width / 2
        clipsToBounds = true
        
        trackView.backgroundColor = .clear
        trackView.clipsToBounds = true
        addSubview(trackView)
        
        progressView.backgroundColor = UIColor.white.withAlphaComponent(0.4)
        trackView.addSubview(progressView)
        
        progressLabel.font = .systemFont(ofSize: 10, weight: .bold)
        progressLabel.textColor = .white
        progressLabel.textAlignment = .center
        trackView.addSubview(progressLabel)
        
        let config = UIImage.SymbolConfiguration(pointSize: 18)
        sunIcon.image = UIImage(systemName: "sun.max.fill", withConfiguration: config)
        sunIcon.tintColor = .white
        sunIcon.contentMode = .center
        addSubview(sunIcon)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        
        let iconHeight: CGFloat = 40
        sunIcon.frame = CGRect(x: 0, y: bounds.height - iconHeight, width: bounds.width, height: iconHeight)
        
        let trackPadding: CGFloat = 6
        trackView.frame = CGRect(x: trackPadding,
                                 y: trackPadding,
                                 width: bounds.width - (trackPadding * 2),
                                 height: bounds.height - iconHeight - (trackPadding * 2))
        trackView.layer.cornerRadius = trackView.bounds.width / 2
        
        progressView.layer.cornerRadius = trackView.bounds.width / 2
    }
    
    func setProgress(_ progress: CGFloat) {
        let clampedProgress = max(0.0, min(1.0, progress))
        let progressHeight = trackView.bounds.height * clampedProgress
        
        progressView.frame = CGRect(x: 0,
                                    y: trackView.bounds.height - progressHeight,
                                    width: trackView.bounds.width,
                                    height: progressHeight)
        
        let percentage = Int(clampedProgress * 100)
        progressLabel.text = "\(percentage)"
        
        progressLabel.frame = trackView.bounds
        progressLabel.center = CGPoint(x: trackView.bounds.midX, y: progressView.frame.midY)
        
        progressLabel.isHidden = progressHeight < 20
    }
}
