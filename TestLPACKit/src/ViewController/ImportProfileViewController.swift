//
//  ImportProfileViewController.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/7/25.
//

import UIKit
import AVFoundation


protocol ImportProfileDelegate :AnyObject {
    func reloadProfile()
}
class ImportProfileViewController: UIViewController {
    // MARK: - Properties

    private var downloadState: LpacDownloadState?
    private var mockActivationCode: [ActivationCode] = [
        //        ActivationCode(code:"LPA:1$rsp.truphone.com$QR-G-5C-1LS-1W1Z9P7",status:false),
        ActivationCode(code: "LPA:1$rsp.truphone.com$QR-G-5C-KR-1PCDWP9", status: false)
        //        ActivationCode(code: "LPA:1$rsp.truphone.com$QRF-SPEEDTEST",status:false),
        
        //        ActivationCode(code: "LPA:1$rsp.truphone.com$QRF-BETTERROAMING-PMRDGIR2EARDEIT5",status:false),
        //        ActivationCode(code: "LPA:1$rsp-eu.redteamobile.com$5901981126831169",status:false),
        //        ActivationCode(code: "LPA:1$smdpp.test.rsp.sysmocom.de$f54172bdf98a95d65cbeb88a38a1c11d800a85c3",status:false),
        
        //        ActivationCode(code: "LPA:1$testsmdpplus.infineon.com$f54172bdf98a95d65cbeb88a38a1c11d800a85c3",status:false),
        //        ActivationCode(code: "LPA:1$testsmdpplus.infineon.com$c0bc70ba36929d43b467ff57570530e57ab8fcd8",status:false),
    ]
    private var captureSession: AVCaptureSession? = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private lazy var activityIndicator = { return UIActivityIndicatorView(style: .large) } ()
    private lazy var downloadProgressLabel = { return UILabel() } ()
    private lazy var downloadProgressView = { return UIProgressView(progressViewStyle: .bar) } ()
    private lazy var smdpAddressTextField = { return UITextField() } ()
    private lazy var activationCodeTextField = { return UITextField() } ()
    private lazy var downloadButton = { return UIButton(type: .system) } ()
    private lazy var cameraView = { return UIView() } ()
    private lazy var inputStackView = {
        let inputStackView = UIStackView(arrangedSubviews: [smdpAddressTextField,activationCodeTextField])
        inputStackView.axis = .vertical
        inputStackView.spacing = 24
        inputStackView.distribution = .equalSpacing
        return inputStackView
    } ()

    
    // MARK: - Open properties
    weak var delegate:ImportProfileDelegate?
    

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession?.stopRunning()
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (captureSession?.isRunning == false) {
            captureSession?.startRunning()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpCamera()
        setupUI()
        
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        guard let captureSession else { return }
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        view.addSubview(cameraView)
        
        title = "eSIM Manager"
        view.backgroundColor = .systemBackground
        
        
        
        
        
        // Configure activation code input
        smdpAddressTextField.placeholder = "Enter SM-DP+ address"
        smdpAddressTextField.borderStyle = .roundedRect
        smdpAddressTextField.autocorrectionType = .no
        smdpAddressTextField.autocapitalizationType = .none
        
        activationCodeTextField.placeholder = "Enter activation code"
        activationCodeTextField.borderStyle = .roundedRect
        activationCodeTextField.autocorrectionType = .no
        activationCodeTextField.autocapitalizationType = .none
        
        // Configure download button
        downloadButton.setTitle("Download Profile", for: .normal)
        downloadButton.addTarget(self, action: #selector(downloadProfile), for: .touchUpInside)
        
        // Configure download progress UI
        downloadProgressLabel.textAlignment = .center
        downloadProgressLabel.font = UIFont.systemFont(ofSize: 14)
        downloadProgressLabel.isHidden = true
        downloadProgressView.progress = 0
        downloadProgressView.isHidden = true
        
        // Configure activity indicator
        activityIndicator.hidesWhenStopped = true
        
        // Add subviews
        view.addSubview(inputStackView)
        view.addSubview(downloadButton)
        view.addSubview(downloadProgressLabel)
        view.addSubview(downloadProgressView)
        view.addSubview(activityIndicator)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        inputStackView.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // EID label at top
            cameraView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor,multiplier: 1),
            
            // Table view below EID label
            
            // Input field below table view
            inputStackView.topAnchor.constraint(greaterThanOrEqualTo: cameraView.bottomAnchor, constant: 16),
            inputStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Download button below input
            downloadButton.topAnchor.constraint(equalTo: inputStackView.bottomAnchor, constant: 16),
            downloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Progress label below button
            downloadProgressLabel.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 16),
            downloadProgressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            downloadProgressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Progress bar below label
            downloadProgressView.topAnchor.constraint(equalTo: downloadProgressLabel.bottomAnchor, constant: 8),
            downloadProgressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            downloadProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            downloadProgressView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            
            // Activity indicator in center
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            previewLayer.frame = cameraView.layer.bounds
        }
    }
    
   
    
    
    
}


// MARK: - Profile Manager
extension ImportProfileViewController {
    
    @objc private func downloadProfile() {
        
        guard let index = mockActivationCode.firstIndex(where: { $0.status == false }), !mockActivationCode[index].code.isEmpty else {
            showAlert(title: "Error", message: "Please enter an activation code")
            return
        }
        let activationCode = mockActivationCode[index].code
        
        // Parse activation code (format: LPA:1$smdp.example.com$matching-id)
        let components = activationCode.replacingOccurrences(of: "LPA:", with: "").split(separator: "$")
        if components.count < 3 {
            showAlert(title: "Error", message: "Invalid activation code format")
            return
        }
        
        let smdp = String(components[1])
        let matchingId = String(components[2])
        
        // Show progress UI
        downloadProgressLabel.isHidden = false
        downloadProgressView.isHidden = false
        updateDownloadProgress(state: .preparing)
        
        // Start download
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try EuiccManager.shared.downloadProfile(
                    activationCode: activationCode,
                    progressHandler: { [weak self] state in
                        DispatchQueue.main.async {
                            self?.updateDownloadProgress(state: state)
                        }
                    },
                    completionHandler: { [weak self] in
                        self?.delegate?.reloadProfile()
                        self?.mockActivationCode[index].status = true

                        DispatchQueue.main.async {
                            self?.downloadProgressLabel.isHidden = true
                            self?.downloadProgressView.isHidden = true
                            self?.activationCodeTextField.text = ""
                            self?.smdpAddressTextField.text = ""
                            self?.showAlert(title: "Success", message: "Profile downloaded successfully")
                        }
                    }
                )
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }
    
    private func updateDownloadProgress(state: LpacDownloadState) {
        downloadState = state
        
        let stateText: String
        var progress: Float = 0.0
        
        switch state {
            case .preparing:
                stateText = "Preparing download..."
                progress = 0.2
            case .connecting:
                stateText = "Connecting to SM-DP+..."
                progress = 0.4
            case .authenticating:
                stateText = "Authenticating..."
                progress = 0.6
            case .downloading:
                stateText = "Downloading profile..."
                progress = 0.8
            case .finalizing:
                stateText = "Finalizing installation..."
                progress = 1.0
            default:
                stateText = "Processing..."
                progress = 0.5
        }
        
        downloadProgressLabel.text = stateText
        UIView.animate(withDuration: 0.3) {
            self.downloadProgressView.setProgress(progress, animated: true)
        }
    }
    
}
// MARK: - Camera Handle
extension ImportProfileViewController: AVCaptureMetadataOutputObjectsDelegate {
    private func setUpCamera() {
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video), let captureSession else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        
    }
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession?.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            found(code: stringValue)
        }
    }
    
    func found(code: String) {
        print(code)
        activationCodeTextField.text = code
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
