//
//  SimpleCamera.swift
//  SimpleCameraKit
//
//  Created by TKang on 2017. 10. 12..
//  Copyright © 2017년 TKang. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import Photos
import CoreMotion

protocol SimpleCameraDelegate: class {
    /**
        Called when the device orientation is changed.
     
     - parameter camera: `SimpleCamera` class you are using.
     
     - parameter deviceOrientation: New device orientation.
    */
    func simpleCameraDidChangeDeviceOrientation(_ camera: SimpleCamera, deviceOrientation: UIDeviceOrientation)
    /**
     Called when the capture screen output is ready. Invoked after `func captureCurrentScreen()`
     
     - parameter camera: `SimpleCamera` class you are using.
     
     - parameter capturedScreen: Captured Screen image in `CIImage` form.
     */
    func simpleCameraCaptureScreenOutput(_ camera: SimpleCamera, capturedScreen: CIImage)
    /**
     Called when the still photo is ready. Invoked after `func capturePhoto()`
     
     - parameter camera: `SimpleCamera` class you are using.
     
     - parameter photo: Captured still photo in Jpeg `Data` format.
     */
    func simpleCameraDidCapturePhoto(_ camera: SimpleCamera, photo: Data?)
    /**
     Called repeatedly after timer is set. Show remaining Time
     
     - parameter camera: `SimpleCamera` class you are using.
     
     - parameter remainingTime: Remaining time to fire capture timer.
     */
    func simpleCameraCountDownTimer(_ camera: SimpleCamera, _ remainingTime: TimeInterval)
}

// These delegate methods are optional. default behavior are none.
extension SimpleCameraDelegate {
    public func simpleCameraDidChangeDeviceOrientation(_ camera: SimpleCamera, deviceOrientation: UIDeviceOrientation){}
    public func simpleCameraCaptureScreenOutput(_ camera: SimpleCamera, capturedScreen: CIImage){}
    public func simpleCameraCountDownTimer(_ camera: SimpleCamera, _ remainingTime: TimeInterval){}
}

public class SimpleCamera : NSObject {
    // Camera Core
    var videoDevice : AVCaptureDevice!
    var captureSession : AVCaptureSession!
    var captureSessionQueue : DispatchQueue!
    var videoDataOutput : AVCaptureVideoDataOutput!
    var photoOutput : AVCapturePhotoOutput!
    var videoPreviewView: GLKView!
    var ciContext: CIContext!
    var eaglContext: EAGLContext!
    var videoPreviewViewBounds: CGRect = CGRect.zero
    var position: AVCaptureDevice.Position = .back 
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var torchMode: AVCaptureDevice.TorchMode = .off
    var timer: Timer!
    var timerForCountDown: Timer!
    // Image Buffers
    var photoSampleBuffer : CMSampleBuffer?
    var previewPhotoSampleBuffer : CMSampleBuffer?
    var usingNextFrameAsCapturedScreen: Bool = false
    // Device Info
    let motionManager : CMMotionManager = CMMotionManager()
    var deviceOrientation : UIDeviceOrientation!
    // Delegate
    weak var delegate : SimpleCameraDelegate?
    
    override init() {
        super.init()
        if let captureSession = self.configureCaptureSession() {
            self.captureSession = captureSession
        } else {
            print("error! no capture session")
        }
        
        configureContextsAndPreview()
        startMotionManager()
    }
    
    /**
        Activate the Camera device
    */
    func start() {
        captureSession.startRunning()
    }
    
    /**
        Deactivate the Camera device
    */
    func stop() {
        captureSession.stopRunning()
    }
    
    private func startMotionManager() {
        motionManager.deviceMotionUpdateInterval = 0.3
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (motion, error) in
            guard let motion = motion else {
                print("couldn't update device motion with error : \(error?.localizedDescription ?? "unknown Error")")
                return
            }
            let originalDeviceOrientation = self.deviceOrientation
            if abs(motion.gravity.z) < 0.8 {
                if motion.gravity.x >= 0.75 {
                    self.deviceOrientation = .landscapeRight
                } else if motion.gravity.x <= -0.75 {
                    self.deviceOrientation = .landscapeLeft
                } else if motion.gravity.y >= 0.75 {
                    self.deviceOrientation = .portraitUpsideDown
                } else if motion.gravity.y <= -0.75 {
                    self.deviceOrientation = .portrait
                }
            } else {
                if motion.gravity.x >= 0.5 {
                    self.deviceOrientation = .landscapeRight
                } else if motion.gravity.x <= -0.5 {
                    self.deviceOrientation = .landscapeLeft
                } else if motion.gravity.y >= 0.4 {
                    self.deviceOrientation = .portraitUpsideDown
                } else if motion.gravity.y <= -0.4 {
                    self.deviceOrientation = .portrait
                }
            }
            if originalDeviceOrientation != self.deviceOrientation {
                self.delegate?.simpleCameraDidChangeDeviceOrientation(self, deviceOrientation: self.deviceOrientation)
            }
        }
    }
    /**
        Set preview for the video input
     
     - parameter view: `UIView` to show preview
     */
    func setPreview(to view: UIView) {
        videoPreviewView.frame = view.bounds
        
        view.addSubview(videoPreviewView)
        view.sendSubview(toBack: videoPreviewView)
        print(view.subviews)
        
        videoPreviewView.bindDrawable()
        videoPreviewViewBounds.size.width = CGFloat(videoPreviewView.drawableWidth)
        videoPreviewViewBounds.size.height = CGFloat(videoPreviewView.drawableHeight)
    }
    
    private func configureCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        
        guard let defaultDevice = defaultDevice() else {
            print("Couldn't find any available device")
            return nil
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: defaultDevice) else {
            print("Unable to obtain video input for default camera.")
            return nil
        }
        
        videoDataOutput = AVCaptureVideoDataOutput()
        let videoDataOutputSetting = [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        videoDataOutput.videoSettings = videoDataOutputSetting
        
        captureSessionQueue = DispatchQueue(label: "capture_session_queue")
        
        videoDataOutput.setSampleBufferDelegate(self, queue: captureSessionQueue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // Create and configure the photo output.
        photoOutput = AVCapturePhotoOutput()
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        
        // Make sure inputs and output can be added to session.
        guard captureSession.canAddInput(videoInput) else { return nil }
        guard captureSession.canAddOutput(photoOutput) else { return nil }
        guard captureSession.canAddOutput(videoDataOutput) else { return nil }
        
        // Configure the session.
        captureSession.beginConfiguration()
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        captureSession.addInput(videoInput)
        captureSession.addOutput(photoOutput)
        captureSession.addOutput(videoDataOutput)
        captureSession.commitConfiguration()
        
        return captureSession
    }
    
    private func defaultDevice() -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return device // use default back facing camera otherwise
        } else {
            return nil
        }
    }
    
    private func configureContextsAndPreview() {
        eaglContext = EAGLContext(api: .openGLES2)
        videoPreviewViewBounds = CGRect.zero
        videoPreviewView = GLKView(frame: videoPreviewViewBounds, context: eaglContext)
        videoPreviewView.enableSetNeedsDisplay = false
        videoPreviewView.transform = CGAffineTransform(rotationAngle: CGFloat.pi/2.0)
        
        ciContext = CIContext(eaglContext: eaglContext, options: [kCIContextWorkingColorSpace:NSNull()])
    }
    
    func setTimer(_ time: TimeInterval) {
        let fireDate = Date().addingTimeInterval(time)
        timer = Timer(fire: fireDate, interval: 0, repeats: false, block: { (timer) in
            self.capturePhoto()
            self.timerForCountDown.invalidate()
            self.timerForCountDown = nil
        })
        timerForCountDown = Timer(fire: Date(), interval: 1, repeats: true, block: { (timer) in
            self.delegate?.simpleCameraCountDownTimer(self, ceil(fireDate.timeIntervalSince(Date())))
        })
        RunLoop.main.add(timer, forMode: .commonModes)
        RunLoop.main.add(timerForCountDown, forMode: .commonModes)
    }
    
//    var timerForMute : Timer!
    
    /**
        Capture Still Photo.
        You can get the result image(Jpeg Data) in following delegate method.
     
        `func simpleCameraDidCapturePhoto(_ camera: SimpleCamera, photo: Data?)`
     */
    @objc func capturePhoto() {
        DispatchQueue.global(qos: .default).async {
            let photoSettings = AVCapturePhotoSettings()
            photoSettings.isAutoStillImageStabilizationEnabled = true
            photoSettings.isHighResolutionPhotoEnabled = true
            //Flash mode
            let supportedFlashModes = self.photoOutput.__supportedFlashModes
            if supportedFlashModes.contains(1) && self.flashMode == .on {
                photoSettings.flashMode = .on
            } else if supportedFlashModes.contains(2) && self.flashMode == .auto {
                photoSettings.flashMode = .auto
            } else {
                photoSettings.flashMode = .off
            }
            
//            // silent shutter for some countries
//            self.timerForMute = Timer(timeInterval: 0.01, target: self, selector: #selector(self.muteShutterSound), userInfo: nil, repeats: true)
//            RunLoop.main.add(self.timerForMute, forMode: RunLoopMode.commonModes)
            
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
    
//    @objc func muteShutterSound() {
//        AudioServicesDisposeSystemSoundID(1108)
//    }
    
    /**
        Capture Video Output.
        You can get the result image(CIImage) in following delegate method.
     
        `func simapleCameraCaptureScreenOutput(_ camera: SimpleCamera, capturedScreen: CIImage)`
    */
    func captureCurrentScreen() {
        usingNextFrameAsCapturedScreen = true
    }
    
    /**
        Rotate Camera.
        If using the back camera, change to the front one and vice versa.
     */
    func rotateCamera() {
        captureSession.beginConfiguration()
        let currentVideoInput = getCurrentVideoInput()
        captureSession.removeInput(currentVideoInput)
        switch position {
        case .back:
            guard let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("There is no available front camera")
                return
            }
            guard let frontCamera = try? AVCaptureDeviceInput(device: frontCameraDevice) else {
                print("Unable to obtain video input for front camera")
                return
            }
            guard captureSession.canAddInput(frontCamera) else { return }
            captureSession.addInput(frontCamera)
            position = .front
        case .front:
            guard let backCameraDevice = self.defaultDevice() else {
                print("There is no available back camera")
                return
            }
            guard let backCamera = try? AVCaptureDeviceInput(device: backCameraDevice) else {
                print("Unable to obtain video input for back camera")
                return
            }
            guard captureSession.canAddInput(backCamera) else { return }
            captureSession.addInput(backCamera)
            position = .back
        default:
            break
        }
        captureSession.commitConfiguration()
    }
    
    /**
        Set the flash mode
     
     - parameter mode: `AVCaptureDevice.FlashMode` .auto, .on, .off are available
    */
    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
    }
    
    /**
        Set the torch mode if available.
     
     - parameter mode: `AVCaptureDevice.TorchMode` `.auto, .on, .off` are available
     - parameter torchLevel: Brightness of torch. default is `AVCaptureDevice.maxAvailableTorchLevel`.
     The difference too small to notice difference. Even very small value like 0.1 is still bright.
     Set This value to 0.0 cannot make the torch off. Maybe In some devices, it might work.
    */
    func setTorchMode(_ mode: AVCaptureDevice.TorchMode, _ torchLevel: Float = AVCaptureDevice.maxAvailableTorchLevel) {
        let captureDevice = getCurrentVideoInput().device
        if captureDevice.isTorchAvailable {
            do {
                try captureDevice.lockForConfiguration()
                switch mode{
                case .on:
                    try captureDevice.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                case .off:
                    captureDevice.torchMode = .off
                case .auto:
                    captureDevice.torchMode = .auto
                }
                captureDevice.unlockForConfiguration()
            } catch {
                print("error occurred during setting torch mode: \(error.localizedDescription)")
            }
        }
    }
    
    func setFocusMode(_ mode: AVCaptureDevice.FocusMode){
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isFocusModeSupported(mode) {
                captureDevice.focusMode = mode
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting focus mode: \(error.localizedDescription)")
        }
    }
    
    func setFocus(by point: CGPoint) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isFocusPointOfInterestSupported {
                captureDevice.focusPointOfInterest = point
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting focus by interesting point: \(error.localizedDescription)")
        }
    }
    
    func setFocusLock(to lensPosition: Float, completionHandler: ((CMTime) -> Void)?) {
        // Fit lensPosition into available range
        var lensPosition = max(0, lensPosition)
        lensPosition = min(1, lensPosition)
        
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isLockingFocusWithCustomLensPositionSupported {
                captureDevice.setFocusModeLocked(lensPosition: lensPosition, completionHandler: completionHandler)
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during locking focus: \(error.localizedDescription)")
        }
    }
    
    func setExposureMode(_ mode: AVCaptureDevice.ExposureMode) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isExposureModeSupported(mode) {
                captureDevice.exposureMode = mode
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting exposure mode: \(error.localizedDescription)")
        }
    }
    
    func setExposure(by point: CGPoint) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isExposurePointOfInterestSupported {
                captureDevice.exposurePointOfInterest = point
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting exposure by interesting point: \(error.localizedDescription)")
        }
    }
    
    func setExposureTargetBias(to bias: Float, completionHandler: ((CMTime) -> Void)?) {
        let captureDevice = getCurrentVideoInput().device
        do {
            // fit exposure target bias into available range
            var bias = max(captureDevice.minExposureTargetBias, bias)
            bias = min(captureDevice.maxExposureTargetBias, bias)
            
            try captureDevice.lockForConfiguration()
            captureDevice.setExposureTargetBias(bias, completionHandler: completionHandler)
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting exposure target bias: \(error.localizedDescription)")
        }
    }
    
    func setExposure(duration: CMTime, iso: Float, completionHandler: ((CMTime) -> Void)?) {
        let captureDevice = getCurrentVideoInput().device
        do {
            // fit duration and iso into available range
            var duration = max(captureDevice.activeVideoMinFrameDuration, duration)
            duration = min(captureDevice.activeVideoMaxFrameDuration, duration)
            var iso = max(captureDevice.activeFormat.minISO, iso)
            iso = min(captureDevice.activeFormat.maxISO, iso)
            
            try captureDevice.lockForConfiguration()
            captureDevice.setExposureModeCustom(duration: duration, iso: iso, completionHandler: completionHandler)
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during set custom exposure: \(error.localizedDescription)")
        }
    }
    
    func setWhiteBalanceMode(_ mode: AVCaptureDevice.WhiteBalanceMode) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isWhiteBalanceModeSupported(mode) {
                captureDevice.whiteBalanceMode = mode
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting white balance mode: \(error.localizedDescription)")
        }
    }
    
    func setWhiteBalance(temperature: Float, tint: Float, completionHandler: ((CMTime) -> Void)?) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: tint)
                var whiteBalanceGains = captureDevice.deviceWhiteBalanceGains(for: temperatureAndTint)
                whiteBalanceGains = cropGainValuesToFitIntoAvailableRange(captureDevice: captureDevice, gains: whiteBalanceGains)
                captureDevice.setWhiteBalanceModeLocked(with: whiteBalanceGains, completionHandler: completionHandler)
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting white balance with temperature value and tint value: \(error.localizedDescription)")
        }
    }
    
    func setWhiteBalance(chromaticityPoint: CGPoint, completionHandler: ((CMTime) -> Void)?) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                let chromaticity = AVCaptureDevice.WhiteBalanceChromaticityValues(x: Float(chromaticityPoint.x), y: Float(chromaticityPoint.y))
                var whiteBalanceGains = captureDevice.deviceWhiteBalanceGains(for: chromaticity)
                whiteBalanceGains = cropGainValuesToFitIntoAvailableRange(captureDevice: captureDevice, gains: whiteBalanceGains)
                captureDevice.setWhiteBalanceModeLocked(with: whiteBalanceGains, completionHandler: completionHandler)
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting white balance with chromaticity value: \(error.localizedDescription)")
        }
    }
    
    func setWhiteBalance(gains: AVCaptureDevice.WhiteBalanceGains, completionHandler: ((CMTime) -> Void)?) {
        let captureDevice = getCurrentVideoInput().device
        do {
            try captureDevice.lockForConfiguration()
            if captureDevice.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                let gains = cropGainValuesToFitIntoAvailableRange(captureDevice: captureDevice, gains: gains)
                captureDevice.setWhiteBalanceModeLocked(with: gains, completionHandler: completionHandler)
            }
            captureDevice.unlockForConfiguration()
        } catch {
            print("error occurred during setting white balance with gains: \(error.localizedDescription)")
        }
    }
    
    private func cropGainValuesToFitIntoAvailableRange(captureDevice: AVCaptureDevice , gains: AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
        var gains = gains
        gains.redGain = max(1, gains.redGain)
        gains.greenGain = max(1, gains.greenGain)
        gains.blueGain = max(1, gains.blueGain)
        
        gains.redGain = min(captureDevice.maxWhiteBalanceGain, gains.redGain)
        gains.greenGain = min(captureDevice.maxWhiteBalanceGain, gains.greenGain)
        gains.blueGain = min(captureDevice.maxWhiteBalanceGain, gains.blueGain)
        
        return gains
    }
    
    private func getCurrentVideoInput() -> AVCaptureDeviceInput {
        var currentVideoInput : AVCaptureDeviceInput!
        for input in captureSession.inputs {
            for port in input.ports {
                if port.mediaType == .video {
                    currentVideoInput = input as! AVCaptureDeviceInput
                    break
                }
            }
        }
        return currentVideoInput
    }
    
    /**
        You need to override this method in your subClass for processing preview images before they appear.
        Default behavior is none.
     
     - parameter sourceImage: image output from the camera device.
     
     - returns: processed image to show.
 
    */
    public func processPreviewImage(sourceImage: CIImage) -> CIImage {
        // You need to override this method to process image before it is displayed.
        // Default behavior is nothing.
        return sourceImage
    }
    
    private func flipFrontCameraImage(_ image: CIImage) -> CIImage {
        let flipHorizonatllyTransform = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: image.extent.height))
        return image.transformed(by: flipHorizonatllyTransform)
    }
}

extension SimpleCamera : AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
//        // Invalidate timer for mute shutter
//        self.timerForMute.invalidate()
        
        guard error == nil, let photoSampleBuffer = photoSampleBuffer else {
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }
        
        self.photoSampleBuffer = photoSampleBuffer
        self.previewPhotoSampleBuffer = previewPhotoSampleBuffer
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let photoSampleBuffer = self.photoSampleBuffer {
            guard let jpegData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer) else {
                print("Unable to create JPEG data")
                delegate?.simpleCameraDidCapturePhoto(self, photo: nil)
                return
            }
            delegate?.simpleCameraDidCapturePhoto(self, photo: jpegData)
        }
    }
}

extension SimpleCamera : AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let sourceImage = CIImage(cvImageBuffer: imageBuffer, options: nil)
        
        sendPreviewToVideoPreview(sourceImage: sourceImage)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let attachment = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_DroppedFrameReason, nil)
        print("Video data output frame was dropped because of \(attachment ?? ("unknown reason" as CFTypeRef))")
    }
    
    private func sendPreviewToVideoPreview(sourceImage: CIImage) {
        let sourceExtent = sourceImage.extent
    
        let sourceAspect = sourceExtent.width/sourceExtent.height
        let previewAspect = videoPreviewViewBounds.width/videoPreviewViewBounds.height
    
        // we want to maintain the aspect radio of the screen size, so we clip the video image
        var drawRect = sourceExtent
        if sourceAspect > previewAspect {
            // use full height of the video image, and center crop the width
            drawRect.origin.x += (drawRect.size.width - drawRect.size.height * previewAspect) / 2.0
            drawRect.size.width = drawRect.size.height * previewAspect
        } else {
            // use full width of the video image, and center crop the height
            drawRect.origin.y += (drawRect.size.height - drawRect.size.width / previewAspect) / 2.0;
            drawRect.size.height = drawRect.size.width / previewAspect;
        }
    
        var processedImage = processPreviewImage(sourceImage: sourceImage)
        if position == .front {
            processedImage = flipFrontCameraImage(processedImage)
        }
        
        if usingNextFrameAsCapturedScreen {
            delegate?.simpleCameraCaptureScreenOutput(self, capturedScreen: processedImage)
            usingNextFrameAsCapturedScreen = false
        }
    
        videoPreviewView.bindDrawable()
        
        if eaglContext != EAGLContext.current() {
            EAGLContext.setCurrent(eaglContext)
        }
        
        // clear eagl view to grey
        glClearColor(0.5, 0.5, 0.5, 1.0);
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        
        // set the blend mode to "source over" so that CI will use that
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        
        ciContext.draw(processedImage, in: videoPreviewViewBounds, from: drawRect)
        
        videoPreviewView.display()
    }
}
