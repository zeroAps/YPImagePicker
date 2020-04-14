//
//  YPVideoVC.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit

public class YPVideoCaptureVC: UIViewController, YPPermissionCheckable {
    
    public var didCaptureVideo: ((URL) -> Void)?
    
    private let videoHelper = YPVideoCaptureHelper()
    private let v = YPCameraView(overlayView: nil)
    private var viewState = ViewState()
    
    let alert = UIAlertController(title: nil, message: "Compressing! Please wait!", preferredStyle: .alert)
    var progress: Float?
    var progressView: UIProgressView?
    
    // MARK: - Init
    
    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    public required init() {
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.videoTitle
        videoHelper.didCaptureVideo = { [weak self] videoURL in
            self?.didCaptureVideo?(videoURL)
            self?.resetVisualState()
            self?.dismiss(animated: false, completion: nil)
        }
        videoHelper.videoRecordingProgress = { [weak self] progress, timeElapsed in
            self?.updateState {
                $0.progress = progress
                $0.timeElapsed = timeElapsed
            }
        }
    }
    
    // MARK: - View LifeCycle
    
    override public func loadView() { view = v }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        v.timeElapsedLabel.isHidden = false // Show the time elapsed label since we're in the video screen.
        setupButtons()
        linkButtons()
        
        // Focus
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        v.previewViewContainer.addGestureRecognizer(tapRecognizer)
        
        // Zoom
        let pinchRecongizer = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(_:)))
        v.previewViewContainer.addGestureRecognizer(pinchRecongizer)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.uploadDidProgress(_:)), name: NSNotification.Name(rawValue: "ProgressBarPercentage"), object: nil)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        v.shotButton.isEnabled = false
        doAfterPermissionCheck { [weak self] in
            guard let strongSelf = self else {
                return
            }
            self?.videoHelper.start(previewView: strongSelf.v.previewViewContainer,
                                    withVideoRecordingLimit: YPConfig.video.recordingTimeLimit,
                                    completion: {
                                        DispatchQueue.main.async {
                                            self?.v.shotButton.isEnabled = true
                                            self?.refreshState()
                                        }
            })
        }
    }
    
    func refreshState() {
        // Init view state with video helper's state
        updateState {
            $0.isRecording = self.videoHelper.isRecording
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
        }
    }
    
    // MARK: - Setup
    
    private func setupButtons() {
        v.flashButton.setImage(YPConfig.icons.flashOffIcon, for: .normal)
        v.flipButton.setImage(YPConfig.icons.loopIcon, for: .normal)
        v.shotButton.setImage(YPConfig.icons.captureVideoImage, for: .normal)
    }
    
    private func linkButtons() {
        v.flashButton.addTarget(self, action: #selector(flashButtonTapped), for: .touchUpInside)
        v.shotButton.addTarget(self, action: #selector(shotButtonTapped), for: .touchUpInside)
        v.flipButton.addTarget(self, action: #selector(flipButtonTapped), for: .touchUpInside)
    }
    
    // MARK: - Flip Camera
    
    @objc
    func flipButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.flip()
        }
    }
    
    private func flip() {
        videoHelper.flipCamera {
            self.updateState {
                $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
            }
        }
    }
    
    // MARK: - Toggle Flash
    
    @objc
    func flashButtonTapped() {
        videoHelper.toggleTorch()
        updateState {
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
        }
    }
    
    // MARK: - Toggle Recording
    
    @objc
    func shotButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.toggleRecording()
        }
    }
    
    private func toggleRecording() {
        videoHelper.isRecording ? stopRecording() : startRecording()
    }
    
    private func startRecording() {
        videoHelper.startRecording()
        updateState {
            $0.isRecording = true
        }
    }
    
    private func stopRecording() {
        videoHelper.stopRecording()
        updateState {
            $0.isRecording = false
        }
        
        let height:NSLayoutConstraint = NSLayoutConstraint(item: alert.view!, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant:120)
        alert.view.addConstraint(height);
        
        present(alert, animated: true, completion: {
            //  Add your progressbar after alert is shown (and measured)
            let margin:CGFloat = 8.0
            let rect = CGRect(x: margin, y: 72.0, width: self.alert.view.frame.width - margin * 2.0 , height: 5.0)
            self.progressView = UIProgressView(frame: rect)
            self.progressView?.tintColor = self.view.tintColor
            self.alert.view.addSubview(self.progressView!)
        })
    }

    public func stopCamera() {
        videoHelper.stopCamera()
    }
    
    // MARK: - Focus
    
    @objc
    func focusTapped(_ recognizer: UITapGestureRecognizer) {
        doAfterPermissionCheck { [weak self] in
            self?.focus(recognizer: recognizer)
        }
    }
    
    private func focus(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: v.previewViewContainer)
        let viewsize = v.previewViewContainer.bounds.size
        let newPoint = CGPoint(x: point.x/viewsize.width, y: point.y/viewsize.height)
        videoHelper.focus(onPoint: newPoint)
        v.focusView.center = point
        YPHelper.configureFocusView(v.focusView)
        v.addSubview(v.focusView)
        YPHelper.animateFocusView(v.focusView)
    }
    
    // MARK: - Zoom
    
    @objc
    func pinch(_ recognizer: UIPinchGestureRecognizer) {
        doAfterPermissionCheck { [weak self] in
            self?.zoom(recognizer: recognizer)
        }
    }
    
    func zoom(recognizer: UIPinchGestureRecognizer) {
        videoHelper.zoom(began: recognizer.state == .began, scale: recognizer.scale)
    }
    
    // MARK: - UI State
    
    enum FlashMode {
        case noFlash
        case off
        case on
        case auto
    }
    
    struct ViewState {
        var isRecording = false
        var flashMode = FlashMode.noFlash
        var progress: Float = 0
        var timeElapsed: TimeInterval = 0
    }
    
    private func updateState(block:(inout ViewState) -> Void) {
        block(&viewState)
        updateUIWith(state: viewState)
    }
    
    private func updateUIWith(state: ViewState) {
        func flashImage(for torchMode: FlashMode) -> UIImage {
            switch torchMode {
            case .noFlash: return UIImage()
            case .on: return YPConfig.icons.flashOnIcon
            case .off: return YPConfig.icons.flashOffIcon
            case .auto: return YPConfig.icons.flashAutoIcon
            }
        }
        v.flashButton.setImage(flashImage(for: state.flashMode), for: .normal)
        v.flashButton.isEnabled = !state.isRecording
        v.flashButton.isHidden = state.flashMode == .noFlash
        v.shotButton.setImage(state.isRecording ? YPConfig.icons.captureVideoOnImage : YPConfig.icons.captureVideoImage,
                              for: .normal)
        v.flipButton.isEnabled = !state.isRecording
        v.progressBar.progress = state.progress
        v.timeElapsedLabel.text = YPHelper.formattedStrigFrom(state.timeElapsed)
        
        // Animate progress bar changes.
        UIView.animate(withDuration: 1, animations: v.progressBar.layoutIfNeeded)
    }
    
    private func resetVisualState() {
        updateState {
            $0.isRecording = self.videoHelper.isRecording
            $0.flashMode = self.flashModeFrom(videoHelper: self.videoHelper)
            $0.progress = 0
            $0.timeElapsed = 0
        }
    }
    
    private func flashModeFrom(videoHelper: YPVideoCaptureHelper) -> FlashMode {
        if videoHelper.hasTorch() {
            switch videoHelper.currentTorchMode() {
            case .off: return .off
            case .on: return .on
            case .auto: return .auto
            @unknown default:
                fatalError()
            }
        } else {
            return .noFlash
        }
    }
    
    @objc private func uploadDidProgress(_ notification: Notification) {
        if let progress = notification.object as? Float {
            self.progressView?.progress = progress
            
            if let progress = Double(String(format: "%.2f", progress)), progress > 0.97 {
                alert.dismiss(animated: false, completion: nil)
            }
        }
    }
}
