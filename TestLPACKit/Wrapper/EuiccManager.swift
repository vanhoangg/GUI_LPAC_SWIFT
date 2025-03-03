//
//  EuiccManager.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//


import Foundation

class EuiccManager {
    private let lpacManager: LpacManager
    
    init(apduInterface: ApduInterface, httpInterface: HttpInterface) {
        // Create LPAC manager
        lpacManager = LpacManager(apduInterface: apduInterface, httpInterface: httpInterface)
        
        // ISD-R AID for eUICC (example)
        let isdrAid = Data([0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x00, 0x01, 0x00])
        
        // Initialize
        let result = lpacManager.initialize(isdrAid: isdrAid)
        if result != .success {
            print("Failed to initialize LPAC library: \(result)")
        }
    }
    
    deinit {
        lpacManager.cleanup()
    }
    
    func getEID() -> String? {
        return lpacManager.getEID()
    }
    func getCardInfo() -> Es10cExEuiccInfo2? {
        return lpacManager.getCardInfo()
    }
    
    func listProfiles() -> [ProfileInfo]? {
        return lpacManager.getProfilesInfo()
    }
    
    func enableProfile(iccid: String) -> Bool {
        let result = lpacManager.enableProfile(iccid: iccid)
        return result == .success
    }
    
    func deleteProfile(iccid: String) -> Bool {
        let result = lpacManager.deleteProfile(iccid: iccid)
        return result == .success
    }
    
    func setNickname(iccid: String, nickname: String) -> Bool {
        let result = lpacManager.setNickname(iccid: iccid, nickname: nickname)
        return result == .success
    }
    
    func downloadProfile(
        activationCode: String,
        progressHandler: @escaping (LpacDownloadState) -> Void,
        completionHandler: @escaping (Bool, String?) -> Void
    ) {
        // Parse activation code (format: LPA:1$smdp.example.com$matching-id)
        let components = activationCode.replacingOccurrences(of: "LPA:", with: "").split(separator: "$")
        guard components.count >= 3 else {
            completionHandler(false, "Invalid activation code format")
            return
        }
        
        let smdp = String(components[1])
        let matchingId = String(components[2])
        
        var complete = false
        
        // Download profile with progress updates
        let result = lpacManager.downloadProfile(
            smdp: smdp,
            matchingId: matchingId,
            progressHandler: { state in
                progressHandler(state)
                
                // When finalization is complete, mark as successful
                if state == .finalizing && !complete {
                    complete = true
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        completionHandler(true, nil)
                    }
                }
            }
        )
        
        // If initialization fails, report error immediately
        if result != .success && !complete {
            completionHandler(false, "Failed to start download: \(result)")
        }
    }
}

