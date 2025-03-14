import UIKit
import AVFoundation

struct ActivationCode {
    let code: String
    var status: Bool
}
class EuiccViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    // MARK: - UI Components

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let responseTextView = UITextView()
    // MARK: - Properties
    private var profiles: [ProfileInfo] = []
    private var eiuccInfo: Es10cExEuiccInfo2 = Es10cExEuiccInfo2()
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
        responseTextView.font = UIFont.systemFont(ofSize: 14)
        responseTextView.textColor = .secondaryLabel
        responseTextView.textAlignment = .left
        // Configure table view
        tableView.register(ProfileCell.self, forCellReuseIdentifier: "ProfileCell")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
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
            responseTextView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
            tableView.topAnchor.constraint(equalTo: responseTextView.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
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
                try await EuiccManager.shared.createContext()
                let eid = try EuiccManager.shared.getEID()
                responseTextView.text += "EID: \(String(describing: eid))\n"

                let eidInfo = try EuiccManager.shared.getCardInfo()
                eiuccInfo = eidInfo
                eidInfo.toJsonString().components(separatedBy: ",").forEach( {
                    responseTextView.text += $0 + "\n"
                })
                refreshProfiles()

            } catch {
                responseTextView.text += error.localizedDescription
            }
        }
    }

    // MARK: - Actions
    @objc private func navigateToNewScreen() {
        let newScreenVC = ImportProfileViewController()
        newScreenVC.delegate = self
        navigationController?.pushViewController(newScreenVC, animated: true)
    }

}

// MARK: - Delegate
extension EuiccViewController: ImportProfileDelegate, EuiccDelegate {
    func downloadFinish() {

    }

    func downloadCallbackHolder(_ state: LpacDownloadState) {

    }

    func reloadProfile() {
        refreshProfiles()
    }
    func throwError(_ decription: String) {
        showAlert(title: "Error", message: decription)
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
                    self.profiles = []
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
        return 1
    }
    func numberOfSections(in tableView: UITableView) -> Int {
        return profiles.count

    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ProfileCell", for: indexPath) as? ProfileCell else {
            return UITableViewCell()
        }

        let profile = profiles[indexPath.section]
        cell.configure(with: profile)
        // add border and color
        cell.layer.borderColor = UIColor.cyan.cgColor
        cell.layer.borderWidth = 1
        cell.layer.cornerRadius = 24
        cell.clipsToBounds = true
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let profile = profiles[indexPath.section]
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
        return UITableView.automaticDimension
    }
    // Set the spacing between sections
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 10
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = UIColor.white
        return headerView
    }
}

// MARK: - ProfileCell
class ProfileCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let providerLabel = UILabel()
    private let iccidLabel = UILabel()
    private let nickNameLabel = UILabel()
    private let aidLabel = UILabel()
    private let classLabel = UILabel()

    private lazy var stackViewLabel: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [nameLabel, providerLabel, iccidLabel, nickNameLabel, aidLabel, classLabel])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.distribution = .fill
        return stackView
    }()
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
        nameLabel.textColor = .systemBlue
        providerLabel.font = UIFont.systemFont(ofSize: 14)
        iccidLabel.font = UIFont.systemFont(ofSize: 14)
        nickNameLabel.font = UIFont.systemFont(ofSize: 14)
        aidLabel.font = UIFont.systemFont(ofSize: 14)
        aidLabel.textColor = .systemPurple
        classLabel.font = UIFont.systemFont(ofSize: 14)
        classLabel.textColor = .systemTeal

        statusIndicator.layer.cornerRadius = 6
        statusIndicator.clipsToBounds = true

        contentView.addSubview(stackViewLabel)
        contentView.addSubview(statusIndicator)

        stackViewLabel.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackViewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackViewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackViewLabel.trailingAnchor.constraint(equalTo: statusIndicator.leadingAnchor, constant: -16),
            stackViewLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            statusIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusIndicator.widthAnchor.constraint(equalToConstant: 24),
            statusIndicator.heightAnchor.constraint(equalToConstant: 24)
        ])

    }

    func configure(with profile: ProfileInfo) {
        nameLabel.text = "Name: " + (profile.name ?? "Unknown")
        providerLabel.text = "Provider: " + (profile.provider ?? "Unknown Provider")
        iccidLabel.text = "ICCID: " + (profile.iccid ?? "Unknown ICCID")
        nickNameLabel.text = "Nickname: " + (profile.nickname ?? "")
        aidLabel.text = "AID: " + (profile.isdpAid ?? "")
        var classText: String?
        switch profile.profileClass?.rawValue ?? 0 {
            case 1:
                classText = "Test Class"
            case 2:
                classText = "Provisioning Class"
            case 3:
                classText = "Operational Class"
            default:
                classText = "Unknown Class"
        }
        classLabel.text = "Class: " + (classText ?? "")

        // Set status indicator color
        statusIndicator.backgroundColor = profile.state == .enabled ? .systemGreen : .systemGray
    }
}
