//
//  EuiccManager.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//


import Foundation
import CryptoTokenKit



protocol EuiccDelegate: AnyObject {
    func throwError(_ decription:String)
    func downloadCallbackHolder(_ state: LpacDownloadState)
    func downloadFinish()

}
extension EuiccDelegate {
    func downloadCallbackHolder(_ state: LpacDownloadState) {}
}
class EuiccManager {
    weak var delegate: EuiccDelegate?
    static let shared = EuiccManager()
    private let lpacManager: LpacManager
    private let watcher: TKTokenWatcher = TKTokenWatcher()
    private var listNotification: [Notification] {
        get {
            return lpacManager.listNotifications().sorted(by: { $0.seqNumber > $1.seqNumber })
        }
    }
    private let isdrAid = Data([0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x00, 0x01, 0x00])
    var state: LpacDownloadState?
    var downloadResult: LpacError?
    var complete:Bool = false
    init(apduInterface: ApduInterface? = nil , httpInterface: HttpInterface? = nil)  {
        // Create LPAC manager
     
        lpacManager = LpacManager(apduInterface: apduInterface ?? SmartCardApduInterface(), httpInterface: httpInterface ?? HttpInterfaceImpl())
        lpacManager.delegate = self
        
    }
    
    deinit {
        lpacManager.cleanup()
    }
    private func handleState(_ state: TKSmartCardSlot.State) {
        
    }
    func retryConnect() async throws {
        do {
            try await createContext()
        } catch {
            throw error
        }
    }
    
    func createContext() async throws {
        // ISD-R AID for eUICC (example)
        // Initialize
        guard let smartCardName = TKSmartCardSlotManager.default?.slotNames.first else {
            throw SmartCardError.missingCard
        }
        
        do {
            let result = try await lpacManager.initialize(reader:smartCardName, isdrAid: isdrAid)
            
            if result != .success {
                throw SmartCardError.initError("Failed to initialize LPAC library: \(result)")
            }
        } catch {
            throw error
        }
    }
    
    func getEID() throws -> String {
        do {
            return try lpacManager.getEID()
        } catch {
            throw error
        }
    }
    
    func getCardInfo() throws -> Es10cExEuiccInfo2 {
        do {
            return try lpacManager.getCardInfo()
        } catch {
            throw error
        }
    }
    
    func listProfiles() throws -> [ProfileInfo] {
        do { return try lpacManager.getProfilesInfo() } catch { throw error }
    }
    
    func changeStatusProfile(iccid: String, status:Bool) throws -> Bool {
        do {
            let result = status ? try lpacManager.enableProfile(iccid: iccid) : try lpacManager.disableProfile(iccid: iccid)
            return result == .success
        } catch {
            throw error
        }
    }
    
    
    func deleteProfile(iccid: String) async throws -> Bool {
     
        // Notify changed for card reader
        do {
            let result = try lpacManager.deleteProfile(iccid: iccid)
            print("Delete Profile: \(iccid)")
            result == .success ? await self.beginTrackedOperation() : nil

            return result == .success
        } catch {
            throw error
        }
   
        
    }
    
    func handleNotification(seqNumber:UInt64, completion: ( ((Bool) -> Void))? = nil ) {
        let result = lpacManager.handleNotification(seqNumber: seqNumber)
        completion?(result)
    }
    
    
    func setNickname(iccid: String, nickname: String) throws -> Bool {
        // Notify changed for card reader
        do {
            let result = try lpacManager.setNickname(iccid: iccid, nickname: nickname)
            return result == .success
        } catch {
            throw error
        }
     
    }
    
    func downloadProfile(
        activationCode: String
    ) throws {
        // Parse activation code (format: LPA:1$smdp.example.com$matching-id)
        let components = activationCode.replacingOccurrences(of: "LPA:", with: "").split(separator: "$")
        guard components.count >= 3 else {
            throw(SmartCardError.initError("Invalid activation code format"))
        }
        
        let smdp = String(components[1])
        let matchingId = String(components[2])
        
        // Download profile with progress updates
        complete = false
        do {
            let result = try lpacManager.downloadProfile(
                smdp: smdp,
                matchingId: matchingId
            )
            self.downloadResult = result
            if let state, state == .finalizing && result == .success {
                self.delegate?.downloadFinish()
            }
        } catch {
            throw error
        }
    }
    
    func beginTrackedOperation() async  {
        let latestSeq = self.listNotification.first?.seqNumber ?? 0
        print("Latest notification is \(latestSeq) before operation")
        print("Operation has requested notification handling")
        for notification in self.listNotification where notification.seqNumber > latestSeq {
            print("Handling notification \(notification)")
            self.handleNotification(seqNumber: notification.seqNumber)
        }
    }
    
}
extension EuiccManager: LpacManagerDelegate {
    func downloadCallbackHolder(_ state: LpacDownloadState) {
        self.state = state
        if state == .finalizing && self.downloadResult == .success {
            self.delegate?.downloadFinish()
        } else {
            self.delegate?.downloadCallbackHolder(state)
        }
        
    }
    
    func throwError(_ description: String) {
        self.delegate?.throwError(description)
    }

}

class EuiccChannel {
    var notifications: [Notification]
    var slotId: String
    var channelID: Int
    
    init(slotId: String, channelID: Int) {
        self.slotId = slotId
        self.channelID = channelID
        self.notifications = []
    }
}

