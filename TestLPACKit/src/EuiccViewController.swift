import UIKit
import AVFoundation


class EuiccViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    // MARK: - UI Components
    
    private let tableView = UITableView()
    var captureSession: AVCaptureSession? = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let downloadProgressLabel = UILabel()
    private let downloadProgressView = UIProgressView(progressViewStyle: .bar)
    private let activationCodeTextField = UITextField()
    private let downloadButton = UIButton(type: .system)
    let cameraView = UIView()

    private let responseTextView = UITextView()
    // MARK: - Properties
    
    private var profiles: [ProfileInfo] = []
    private var euiccManager: EuiccManager?
    private var downloadState: LpacDownloadState?
    
    // MARK: - Lifecycle
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            captureSession?.stopRunning()
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpCamera()
        setupEuiccManager()
        setupUI()
    
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (captureSession?.isRunning == false) {
            captureSession?.startRunning()
        }
        refreshProfiles()
        
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

        
        
        title = "eSIM Manager"
        view.backgroundColor = .systemBackground
        
        // Add refresh button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshProfiles)
        )
        
        // Configure EID label
        responseTextView.font = UIFont.systemFont(ofSize: 12)
        responseTextView.textColor = .secondaryLabel
        responseTextView.textAlignment = .center
//        
//        // Configure table view
        tableView.register(ProfileCell.self, forCellReuseIdentifier: "ProfileCell")
        tableView.delegate = self
        tableView.dataSource = self
        
        // Configure activation code input
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
        view.addSubview(responseTextView)
        view.addSubview(cameraView)
        view.addSubview(tableView)
        view.addSubview(activationCodeTextField)
        view.addSubview(downloadButton)
        view.addSubview(downloadProgressLabel)
        view.addSubview(downloadProgressView)
        view.addSubview(activityIndicator)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        responseTextView.translatesAutoresizingMaskIntoConstraints = false
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        activationCodeTextField.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // EID label at top
            responseTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            responseTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            responseTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            
            cameraView.topAnchor.constraint(equalTo: responseTextView.bottomAnchor, constant: 8),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 8),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor,multiplier: 1),

            // Table view below EID label
            tableView.topAnchor.constraint(equalTo: cameraView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3),
            
            // Input field below table view
            activationCodeTextField.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 16),
            activationCodeTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            activationCodeTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Download button below input
            downloadButton.topAnchor.constraint(equalTo: activationCodeTextField.bottomAnchor, constant: 16),
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
    
    private func setupEuiccManager() {
        // Create APDU Interface for NFC communications
        let apduInterface = SmartCardApduInterface()
        
        
        // Create HTTP Interface for network communications
        let httpInterface = NetworkHttpInterface()
        
        // Create EUICC Manager with interfaces
        do {
            euiccManager = try EuiccManager(apduInterface: apduInterface, httpInterface: httpInterface)
            // Attempt to get EID
            let eid = euiccManager?.getEID()
            responseTextView.text += "EID: \(String(describing: eid))"
            if let eidInfo = try? euiccManager?.getCardInfo() {
                print(eidInfo.toJsonString())
            }
           
        } catch {
            responseTextView.text += error.localizedDescription
        }
    }
    
    // MARK: - Actions
    
    @objc private func refreshProfiles() {
        activityIndicator.startAnimating()
        tableView.isHidden = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                if let profiles = try self.euiccManager?.listProfiles() {
                    DispatchQueue.main.async {
                        self.profiles = profiles
                        for profile in profiles {
                            print("Profile \(profile.toJsonString())")
                            
                        }
                        self.tableView.reloadData()
                        self.activityIndicator.stopAnimating()
                        self.tableView.isHidden = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.tableView.isHidden = false
                    self.showAlert(title: "Error", message: "Failed to retrieve profiles \(error.localizedDescription)")
                }
            }
            
        }
    }
    
    @objc private func downloadProfile() {
        guard let activationCode = activationCodeTextField.text, !activationCode.isEmpty else {
            showAlert(title: "Error", message: "Please enter an activation code")
            return
        }
        
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
            
            self.euiccManager?.downloadProfile(
                activationCode: activationCode,
                progressHandler: { [weak self] state in
                    DispatchQueue.main.async {
                        self?.updateDownloadProgress(state: state)
                    }
                },
                completionHandler: { [weak self] success, error in
                    DispatchQueue.main.async {
                        if success {
                            self?.showAlert(title: "Success", message: "Profile downloaded successfully") {
                                self?.refreshProfiles()
                                self?.activationCodeTextField.text = ""
                                self?.downloadProgressLabel.isHidden = true
                                self?.downloadProgressView.isHidden = true
                            }
                        } else {
                            self?.showAlert(title: "Error", message: "Failed to download profile: \(error ?? "Unknown error")")
                            self?.downloadProgressLabel.isHidden = true
                            self?.downloadProgressView.isHidden = true
                        }
                    }
                }
            )
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
    
    // MARK: - Profile Management
    
    private func enableProfile(_ profile: ProfileInfo) {
        guard let iccid = profile.iccid else {
            showAlert(title: "Error", message: "Invalid profile ICCID")
            return
        }
        
        activityIndicator.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let euiccManager = self.euiccManager else { return }
            
            let success = euiccManager.enableProfile(iccid: iccid)
            
            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                
                if success {
                    self.refreshProfiles()
                } else {
                    self.showAlert(title: "Error", message: "Failed to enable profile")
                }
            }
        }
    }
    
    private func deleteProfile(_ profile: ProfileInfo) {
        guard let iccid = profile.iccid else {
            showAlert(title: "Error", message: "Invalid profile ICCID")
            return
        }
        
        // Confirm deletion
        let alert = UIAlertController(
            title: "Delete Profile",
            message: "Are you sure you want to delete this profile? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            self.activityIndicator.startAnimating()
            
            DispatchQueue.global(qos: .userInitiated).async {
                guard let euiccManager = self.euiccManager else { return }
                
                let success = euiccManager.deleteProfile(iccid: iccid)
                
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    
                    if success {
                        self.refreshProfiles()
                    } else {
                        self.showAlert(title: "Error", message: "Failed to delete profile")
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
    
    private func renameProfile(_ profile: ProfileInfo) {
        guard let iccid = profile.iccid else {
            showAlert(title: "Error", message: "Invalid profile ICCID")
            return
        }
        
        let alert = UIAlertController(
            title: "Rename Profile",
            message: "Enter a new nickname for this profile",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Nickname"
            textField.text = profile.nickname
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let self = self, let nickname = alert.textFields?.first?.text, !nickname.isEmpty else { return }
            
            self.activityIndicator.startAnimating()
            
            DispatchQueue.global(qos: .userInitiated).async {
                guard let euiccManager = self.euiccManager else { return }
                
                let success = euiccManager.setNickname(iccid: iccid, nickname: nickname)
                
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    
                    if success {
                        self.refreshProfiles()
                    } else {
                        self.showAlert(title: "Error", message: "Failed to rename profile")
                    }
                }
            }
        })
        
        present(alert, animated: true)
    }
    
    // MARK: - Helpers
    
    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - TableView Delegate & DataSource

extension EuiccViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return profiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath) as? ProfileCell else {
            return UITableViewCell()
        }
        
        let profile = profiles[indexPath.row]
        cell.configure(with: profile)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let profile = profiles[indexPath.row]
        
        if profile.state == .disabled {
            enableProfile(profile)
        } else {
            // Show options for enabled profile
            let actionSheet = UIAlertController(
                title: "Profile Options",
                message: "Select an action for this profile",
                preferredStyle: .actionSheet
            )
            
            actionSheet.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
                self?.renameProfile(profile)
            })
            
            actionSheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
                self?.deleteProfile(profile)
            })
            
            actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            // For iPad compatibility
            if let popoverController = actionSheet.popoverPresentationController {
                popoverController.sourceView = tableView
                popoverController.sourceRect = tableView.rectForRow(at: indexPath)
            }
            
            present(actionSheet, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

// MARK: - Setup Camera
extension EuiccViewController {
    private func setUpCamera() {
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video), let captureSession else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
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
        
        dismiss(animated: true)
    }
    
    func found(code: String) {
        print(code)
        activationCodeTextField.text = code
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}

// MARK: - ProfileCell

class ProfileCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let providerLabel = UILabel()
    private let iccidLabel = UILabel()
    private let statusIndicator = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        nameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        providerLabel.font = UIFont.systemFont(ofSize: 14)
        iccidLabel.font = UIFont.systemFont(ofSize: 12)
        iccidLabel.textColor = .secondaryLabel
        
        statusIndicator.layer.cornerRadius = 6
        statusIndicator.clipsToBounds = true
        
        contentView.addSubview(nameLabel)
        contentView.addSubview(providerLabel)
        contentView.addSubview(iccidLabel)
        contentView.addSubview(statusIndicator)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        iccidLabel.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: statusIndicator.leadingAnchor, constant: -16),
            
            providerLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            providerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            providerLabel.trailingAnchor.constraint(equalTo: statusIndicator.leadingAnchor, constant: -16),
            
            iccidLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 4),
            iccidLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iccidLabel.trailingAnchor.constraint(equalTo: statusIndicator.leadingAnchor, constant: -16),
            iccidLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),
            
            statusIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusIndicator.widthAnchor.constraint(equalToConstant: 12),
            statusIndicator.heightAnchor.constraint(equalToConstant: 12)
        ])
    }
    
    func configure(with profile: ProfileInfo) {
        nameLabel.text = profile.nickname ?? profile.name ?? "Unknown"
        providerLabel.text = profile.provider ?? "Unknown Provider"
        iccidLabel.text = profile.iccid ?? "Unknown ICCID"
        
        // Set status indicator color
        statusIndicator.backgroundColor = profile.state == .enabled ? .systemGreen : .systemGray
    }
}
