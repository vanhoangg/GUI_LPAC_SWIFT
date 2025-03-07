import UIKit
import AVFoundation

struct ActivationCode {
    let code: String
    var status: Bool
}
class EuiccViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, EuiccDelegate {
    func throwError(_ decription: String) {
        showAlert(title: "Error", message: decription)
    }
    
    
    // MARK: - UI Components
    
    private let tableView = UITableView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let responseTextView = UITextView()
    // MARK: - Properties
    private var profiles: [ProfileInfo] = [
        ProfileInfo(iccid: "1234567890",
                    name: "Test Profile 1",
                    provider: "Provider 1",
                    nickname: "Profile 1",
                    isdpAid: "TEST 1",
                    state: .enabled,
                    profileClass: .test),
        ProfileInfo(iccid: "0987654321",
                    name: "Test Profile 2",
                    provider: "Provider 2",
                    nickname: "Profile 2",
                    isdpAid: "TEST 2",
                    state: .disabled,
                    profileClass: .test)
    ]
    
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupEuiccManager()
        setupUI()
        
    }
    
    
    
    // MARK: - Setup
    private func setupUI() {
        title = "eSIM Manager"
        
        view.backgroundColor = .systemBackground
        
        // Add navigation bar buttons
        let refreshBarButton = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshProfiles)
        )
        let addBarButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(navigateToNewScreen))
        
        navigationItem.rightBarButtonItems = [addBarButton, refreshBarButton]
        
        // Configure EID label
        responseTextView.font = UIFont.systemFont(ofSize: 12)
        responseTextView.textColor = .secondaryLabel
        responseTextView.textAlignment = .center
        // Configure table view
        tableView.register(ProfileCell.self, forCellReuseIdentifier: "ProfileCell")
        tableView.delegate = self
        tableView.dataSource = self
        // Configure activity indicator
        activityIndicator.hidesWhenStopped = true
        
        // Add subviews
        view.addSubview(responseTextView)
        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        responseTextView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // EID label at top
            responseTextView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            responseTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            responseTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            responseTextView.heightAnchor.constraint(equalToConstant: 200),
            tableView.topAnchor.constraint(equalTo: responseTextView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 8),
            // Activity indicator in center
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupEuiccManager() {
        EuiccManager.shared.delegate = self
        // Create EUICC Manager with interfaces
        Task {
            do {
                
                // Attempt to get EID
                let response = try await EuiccManager.shared.createContext()
                if response {
                    let eid = try EuiccManager.shared.getEID()
                    responseTextView.text += "EID: \(String(describing: eid))"
                    let eidInfo = try EuiccManager.shared.getCardInfo()
                    eidInfo.toJsonString().components(separatedBy: ",").forEach( {
                        responseTextView.text += $0 + "\n"
                    })
                }

                
            } catch {
                responseTextView.text += error.localizedDescription
            }
        }
    }
    
    // MARK: - Actions
    @objc private func navigateToNewScreen() {
        let newScreenVC = ImportProfileViewController()
        navigationController?.pushViewController(newScreenVC, animated: true)
    }
    
    
    
    
    
}

// MARK: - Profile Management
extension EuiccViewController {
    
    @objc private func refreshProfiles() {
        activityIndicator.startAnimating()
        tableView.isHidden = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let profiles = try EuiccManager.shared.listProfiles()
                self.profiles = profiles
                for profile in self.profiles {
                    print("Profile \(profile.toJsonString())")
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.showAlert(title: "Error", message: "Failed to retrieve profiles \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.activityIndicator.stopAnimating()
                self.tableView.isHidden = false
            }
            
        }
    }
    private func changeStatusProfile(_ profile: ProfileInfo, status: Bool) {
        guard let iccid = profile.iccid else {
            showAlert(title: "Error", message: "Invalid profile ICCID")
            return
        }
        
        activityIndicator.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let success = try EuiccManager.shared.changeStatusProfile(iccid: iccid, status: status)
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    success ? self.refreshProfiles() : self.showAlert(title: "Error", message: "Failed to \(status ? "Enable": "Disable")  profile")
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.showAlert(title: "Error", message: error.localizedDescription)
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
                Task {
                    do {
                        let success = try await EuiccManager.shared.deleteProfile(iccid: iccid)
                        
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            success ? self.refreshProfiles() : self.showAlert(title: "Error", message: "Failed to delete profile")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.activityIndicator.stopAnimating()
                            self.showAlert(title: "Error", message: error.localizedDescription)
                        }
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
                do {
                    let success = try EuiccManager.shared.setNickname(iccid: iccid, nickname: nickname)
                    
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        success ? self.refreshProfiles() : self.showAlert(title: "Error", message: "Failed to rename profile")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.activityIndicator.stopAnimating()
                        self.showAlert(title: "Error", message: error.localizedDescription)
                    }
                }
            }
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
        actionSheet.addAction(UIAlertAction(title: profile.state == .disabled ? "Enable" :"Disable", style: .destructive) { [weak self] _ in
            
            self?.changeStatusProfile(profile, status: profile.state == .disabled)
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad compatibility
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = tableView
            popoverController.sourceRect = tableView.rectForRow(at: indexPath)
        }
        
        present(actionSheet, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
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
