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
}
class EuiccManager {
    weak var delegate: EuiccDelegate?
    
    static let shared = EuiccManager()
    
    private let lpacManager: LpacManager
    private var listNotification: [Notification] = []
    private let isdrAid = Data([0xA0, 0x00, 0x00, 0x05, 0x59, 0x10, 0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0x89, 0x00, 0x00, 0x01, 0x00])

    init(apduInterface: ApduInterface? = nil , httpInterface: HttpInterface? = nil)  {
        // Create LPAC manager
        lpacManager = LpacManager(apduInterface: apduInterface ?? SmartCardApduInterface.shared, httpInterface: httpInterface ?? HttpInterfaceImpl.shared)
        lpacManager.delegate = self
    }
    
    deinit {
        lpacManager.cleanup()
    }
    
    
    func createContext() async throws -> Bool {
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
            return result == .success
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
    
    func getListNotification() async -> [Notification] {
        self.listNotification = await lpacManager.listNotifications()
        return self.listNotification
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
        activationCode: String,
        progressHandler: @escaping (LpacDownloadState) -> Void,
        completionHandler: @escaping () -> Void
    ) throws {
        // Parse activation code (format: LPA:1$smdp.example.com$matching-id)
        let components = activationCode.replacingOccurrences(of: "LPA:", with: "").split(separator: "$")
        guard components.count >= 3 else {
            throw(SmartCardError.initError("Invalid activation code format"))
        }
        
        let smdp = String(components[1])
        let matchingId = String(components[2])
        
        var complete = false
        // Download profile with progress updates

        do {
            let result = try lpacManager.downloadProfile(
                smdp: smdp,
                matchingId: matchingId,
                progressHandler: { state in
                    progressHandler(state)
                    complete = state == .finalizing
                }
            )
            if result != .success || !complete {
                throw SmartCardError.initError("Failed to start download: \(result)")
            }
            completionHandler()

        } catch {
            throw error
        }
    }
    
    func beginTrackedOperation() async  {
        let notifications = await self.getListNotification()
        let latestSeq = notifications.first?.seqNumber ?? 0
        print("Latest notification is \(latestSeq) before operation")
        print("Operation has requested notification handling")
        for notification in notifications where notification.seqNumber > latestSeq {
            print("Handling notification \(notification)")
            self.handleNotification(seqNumber: notification.seqNumber)
        }
    }
    
}
extension EuiccManager: LpacManagerDelegate {
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

