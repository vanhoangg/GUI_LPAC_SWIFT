import Foundation

/// Main class for interacting with the LPAC library
///
///
protocol LpacManagerDelegate :AnyObject {
    func throwError(_ description:String)
    func downloadCallbackHolder(_ state:LpacDownloadState)
}
public class LpacManager {
    // Context pointer
    private var context: lpac_context_t?
    // Callbacks for APDU operations
    private var apduCallbacks = lpac_apdu_interface_t()
    private var httpCallbacks = lpac_http_interface_t()
    
    weak var delegate:LpacManagerDelegate?

    // Store Swift implementation objects
    let apduInterface: ApduInterface
    let httpInterface: HttpInterface
    // Download progress callback wrapper
    private let downloadCallback: @convention(c) (lpac_download_state_t, UnsafeMutableRawPointer?) -> Void = { state, userData in
        guard let userData = userData else { return }
        let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
        let swiftState = LpacDownloadState(rawValue: Int(state.rawValue)) ?? .preparing
        manager.delegate?.downloadCallbackHolder(swiftState)
    }
    
    /// Creates a new LPAC manager with the specified interfaces
    /// - Parameters:
    ///   - apduInterface: Interface for APDU operations
    ///   - httpInterface: Interface for HTTP operations
    public init(apduInterface: ApduInterface, httpInterface: HttpInterface) {
        self.apduInterface = apduInterface
        self.httpInterface = httpInterface

        // Set up APDU callbacks
        apduCallbacks.connect = { userData in
            guard let userData = userData else { return -1 }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            let semaphore = DispatchSemaphore(value: 0)
            var result: Int32 = -1
            
            manager.apduInterface.connect { success in
                result = success ? 0 : -1
                semaphore.signal()
            }

            semaphore.wait()
            return result
        }

        apduCallbacks.disconnect = { userData in
            guard let userData = userData else { return }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            manager.apduInterface.disconnect()
        }
        
        apduCallbacks.logical_channel_open = { aid, aidLen, userData in
            guard let userData = userData, let aid = aid else { return -1 }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            let aidData = Data(bytes: aid, count: Int(aidLen))
            let semaphore = DispatchSemaphore(value: 0)
            var result: Int32 = -1
            manager.apduInterface.logicalChannelOpen(aid: aidData) {  results in
                switch results {
                    case .success(let intData):
                        result = Int32(intData)
                    case .failure(let error):
                        manager.delegate?.throwError(error.localizedDescription)
                        // TODO: DVH - handle error
                }
                semaphore.signal()
            }

            semaphore.wait()
            return result
        }

        apduCallbacks.logical_channel_close = { channel, userData in
            guard let userData = userData else { return }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            manager.apduInterface.logicalChannelClose(channel: Int(channel))
        }

        apduCallbacks.transmit = { [weak self] rx, rxLen, tx, txLen, userData in
            var result: Int32 = -1
            guard let userData = userData, let tx = tx, let rx = rx, let rxLen = rxLen else {
                // TODO(Hoang): - Handle Error
                return result
            }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            let semaphore = DispatchSemaphore(value: 0)

            let txData = Data(bytes: tx, count: Int(txLen))
           manager.apduInterface.transmit(data: txData) { results in
               if case let .success(response) = results, !response.isEmpty {
                   let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: response.count)
                   response.copyBytes(to: buffer, count: response.count)
                   rx.pointee = buffer
                   rxLen.pointee = UInt32(response.count)
                   result = 0
               } else {
                   result = -1
               }
               semaphore.signal()
            }
            semaphore.wait()
            return result
        }

        // Set up HTTP callbacks
        httpCallbacks.transmit = { url, rcode, rx, rxLen, tx, txLen, headers, userData in
            guard let userData = userData, let urlStr = url else { return -1 }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()

            // Convert C arrays to Swift types
            let urlString = String(cString: urlStr)
            var headerDict = [String: String]()

            if let headers = headers {
                var i = 0
                while headers[i] != nil {
                    let key = String(cString: headers[i]!)
                    i += 1
                    if headers[i] == nil { break }
                    let value = String(cString: headers[i]!)
                    headerDict[key] = value
                    i += 1
                }
            }

            var txData: Data?
            if let tx = tx, txLen > 0 {
                txData = Data(bytes: tx, count: Int(txLen))
            }

            // Call Swift implementation
            var responseTrasnmit:Int32 = -1
            let semaphore = DispatchSemaphore(value: 0)

            manager.httpInterface.transmit(url: urlString, headers: headerDict, data: txData) { result in
                if (result.success) {
                    print("response \(result.statusCode)")
                    if let rcode = rcode {
                        rcode.pointee = UInt32(result.statusCode)
                    }
                    
                    print("result.data \(result.data)")
                    
                    
                    // Set result data
                    if let rx = rx, let rxLen = rxLen, !result.data.isEmpty {
                        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: result.data.count)
                        result.data.copyBytes(to: buffer, count: result.data.count)
                        print("buffer \(buffer)")
                        rx.pointee = buffer
                        rxLen.pointee = UInt32(result.data.count)
                        responseTrasnmit = 0
                    }
                } else {
                    let stringResponse = result.data.hexString
                    manager.delegate?.throwError(stringResponse)
                }
                semaphore.signal()
            }
            semaphore.wait()
            return responseTrasnmit
        }
    }

    deinit {
        cleanup()
    }

    /// Initialize the LPAC library with the ISD-R AID
    /// - Parameter isdrAid: The ISD-R AID to use
    /// - Returns: LpacError code
    public func initialize(reader:String,isdrAid: Data) async throws -> LpacError {
        // Clean up any existing context
        do {
            try await self.selectPort(reader: reader)
        } catch {
            throw error
        }
        cleanup()

        // Create a self reference that will be passed to callbacks
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Create the context
        context = lpac_create_context(
            isdrAid.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) },
            UInt32(isdrAid.count),
            &apduCallbacks,
            &httpCallbacks,
            selfPtr
        )

        guard context != nil else {
            throw SmartCardError.missingContext
        }

        // Initialize the library
        let result = lpac_init(context)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    /// Clean up resources
    public func cleanup() {
        if let ctx = context {
            lpac_fini(ctx)
            lpac_destroy_context(ctx)
            context = nil
        }
    }
    
    public func selectPort(reader:String) async throws {
        do {
            try apduInterface.selectedDevice(reader: reader)
        } catch {
            throw SmartCardError.invalidReader
        }
    }
    
    /// Get the EID (eUICC Identifier)
    /// - Returns: EID string or nil if an error occurred
    public func getEID() throws -> String {
        guard let ctx = context else {
            throw SmartCardError.missingContext
        }

        var eidPtr: UnsafeMutablePointer<Int8>?
        let result = lpac_get_eid(ctx, &eidPtr)

        guard result == LPAC_SUCCESS, let ptr = eidPtr else {
            print("GET EUID: Result: \(result.rawValue)")
            print("GET EUID: eidPtr: \(String(describing: eidPtr))")
            throw SmartCardError.failedGetEUICC
        }

        let eid = String(cString: ptr)
        lpac_free_string(ptr)
        return eid
    }
    public func getCardInfo() throws -> Es10cExEuiccInfo2 {
        guard let ctx = context else {
            throw SmartCardError.missingContext
        }

        var euiccPtr: UnsafeMutablePointer<lpac_euicc_info2>?
        let result = lpac_get_euicc_info(ctx, &euiccPtr)

        guard result == LPAC_SUCCESS, let euicc = euiccPtr else {
            throw SmartCardError.failedGetEUICC
        }

        // Convert C structures to Swift objects
        var euiccInfo = Es10cExEuiccInfo2()
        euiccInfo.profileVersion = euicc.pointee.profileVersion != nil ? String(cString: euicc.pointee.profileVersion): nil
        euiccInfo.svn = euicc.pointee.svn != nil ? String(cString: euicc.pointee.svn): nil
        euiccInfo.euiccFirmwareVer = euicc.pointee.euiccFirmwareVer != nil ? String(cString: euicc.pointee.euiccFirmwareVer): nil
        euiccInfo.ts102241Version = euicc.pointee.ts102241Version != nil ? String(cString: euicc.pointee.ts102241Version): nil
        euiccInfo.globalplatformVersion = euicc.pointee.globalplatformVersion != nil ? String(cString: euicc.pointee.globalplatformVersion): nil
        euiccInfo.euiccCategory = euicc.pointee.euiccCategory != nil ? String(cString: euicc.pointee.euiccCategory): nil
        euiccInfo.ppVersion = euicc.pointee.ppVersion != nil ? String(cString: euicc.pointee.ppVersion): nil
        euiccInfo.sasAcreditationNumber = euicc.pointee.sasAcreditationNumber != nil ? String(cString: euicc.pointee.sasAcreditationNumber): nil
        euiccInfo.certificationDataObject?.discoveryBaseURL = euicc.pointee.certificationDataObject.discoveryBaseURL != nil ? String(cString: euicc.pointee.certificationDataObject.discoveryBaseURL): nil
        euiccInfo.certificationDataObject?.platformLabel = euicc.pointee.certificationDataObject.platformLabel != nil ? String(cString: euicc.pointee.certificationDataObject.platformLabel): nil

        euiccInfo.uiccCapability = euicc.pointee.uiccCapability != nil ? LPACKitUtils.convertCArrayToStringArray(cArray: euicc.pointee.uiccCapability) : nil
        euiccInfo.rspCapability = euicc.pointee.rspCapability != nil ? LPACKitUtils.convertCArrayToStringArray(cArray: euicc.pointee.rspCapability): nil
        euiccInfo.forbiddenProfilePolicyRules = euicc.pointee.forbiddenProfilePolicyRules != nil ? LPACKitUtils.convertCArrayToStringArray(cArray: euicc.pointee.forbiddenProfilePolicyRules) : nil

        euiccInfo.euiccCiPKIdListForVerification = euicc.pointee.euiccCiPKIdListForVerification != nil ? LPACKitUtils.convertCArrayToStringArray(cArray: euicc.pointee.euiccCiPKIdListForVerification): nil
        euiccInfo.euiccCiPKIdListForSigning = euicc.pointee.euiccCiPKIdListForSigning != nil ? LPACKitUtils.convertCArrayToStringArray(cArray: euicc.pointee.euiccCiPKIdListForSigning): nil

        var cardResource = ExtCardResource()
        cardResource.freeNonVolatileMemory = euicc.pointee.freeNonVolatileMemory
        cardResource.installedApplication = euicc.pointee.installedApplication
        cardResource.freeVolatileMemory = euicc.pointee.freeVolatileMemory
        euiccInfo.extCardResource = cardResource

        lpac_free_euicc_info(euiccPtr)
        return euiccInfo
    }


    
    
    /// Cancel all ongoing download sessions
    public func cancelSessions() {
        guard let ctx = context else { return }
        lpac_cancel_sessions(ctx)
    }
}
// MARK: - Notification Handle
extension LpacManager {
    // List notifications
    public func listNotifications() -> [Notification] {
        var notificationsPtr: UnsafeMutablePointer<lpac_notification_list_t>?
        let result = lpac_list_notifications(context, &notificationsPtr)
        
        guard result == LPAC_SUCCESS, let notifications = notificationsPtr?.pointee else {
            return []
        }
        
        var notificationList = [Notification]()
        for i in 0..<Int(notifications.count) {
            let notification = notifications.notifications[i]
            let swiftNotification = Notification(
                seqNumber: notification.seq_number,
                notificationAddress: String(cString: notification.notification_address),
                iccid: String(cString: notification.iccid),
                operation: Notification.Operation(rawValue: Int(notification.operation)) ?? .unknown
            )
            notificationList.append(swiftNotification)
        }
        
        lpac_free_notification_list(notificationsPtr)
        return notificationList
    }
    
    // Handle notification
    public func handleNotification(seqNumber: UInt64) -> Bool {
        let result = lpac_handle_notification(context, seqNumber)
        return result == LPAC_SUCCESS
    }
    
    // Delete notification
    public func deleteNotification(seqNumber: UInt64) -> Bool {
        let result = lpac_delete_notification(context, seqNumber)
        return result == LPAC_SUCCESS
    }
}
// MARK: - Profile Handle
extension LpacManager {
    
    /// Get profile information
    /// - Returns: Array of profiles or nil if an error occurred
    public func getProfilesInfo() throws -> [ProfileInfo] {
        guard let ctx = context else {
            throw SmartCardError.missingContext
        }
        
        var profilesPtr: UnsafeMutablePointer<lpac_profile_list_t>?
        let result = lpac_get_profiles_info(ctx, &profilesPtr)
        
        guard result == LPAC_SUCCESS, let profiles = profilesPtr else {
            print("GET PROFILE: result \(result)")
            print("GET PROFILE: profilesPtr \(String(describing: profilesPtr))")
            throw SmartCardError.failedGetProfile
        }
        
        // Convert C structures to Swift objects
        var profileArray = [ProfileInfo]()
        for i in 0..<Int(profiles.pointee.count) {
            let profile = profiles.pointee.profiles[i]
            let profileInfo = ProfileInfo(
                iccid: profile.iccid != nil ? String(cString: profile.iccid) : nil,
                name: profile.name != nil ? String(cString: profile.name) : nil,
                provider: profile.provider != nil ? String(cString: profile.provider) : nil,
                nickname: profile.nickname != nil ? String(cString: profile.nickname) : nil,
                isdpAid: profile.isdp_aid != nil ? String(cString: profile.isdp_aid) : nil,
                state: LpacProfileState(rawValue: Int(profile.state)) ?? .disabled,
                profileClass: LpacProfileClass(rawValue: Int(profile.profile_class)) ?? .unknown
            )
            profileArray.append(profileInfo)
        }
        
        lpac_free_profile_list(profiles)
        return profileArray
    }
    
    /// Enable a profile
    /// - Parameters:
    ///   - iccid: ICCID of the profile to enable
    ///   - refresh: Whether to refresh the card after enabling
    /// - Returns: LpacError code
    public func enableProfile(iccid: String, refresh: Bool = true) throws -> LpacError {
        guard let ctx = context else { throw SmartCardError.missingContext }
        
        let result = lpac_enable_profile(ctx, iccid, refresh)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }
    
    /// Disable a profile
    /// - Parameters:
    ///   - iccid: ICCID of the profile to disable
    ///   - refresh: Whether to refresh the card after disabling
    /// - Returns: LpacError code
    public func disableProfile(iccid: String, refresh: Bool = true) throws -> LpacError {
        guard let ctx = context else { throw SmartCardError.missingContext }

        let result = lpac_disable_profile(ctx, iccid, refresh)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }
    
    /// Delete a profile
    /// - Parameter iccid: ICCID of the profile to delete
    /// - Returns: LpacError code
    public func deleteProfile(iccid: String) throws -> LpacError {
        guard let ctx = context else { throw SmartCardError.missingContext }

        let result = lpac_delete_profile(ctx, iccid)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }
    
    /// Set nickname for a profile
    /// - Parameters:
    ///   - iccid: ICCID of the profile
    ///   - nickname: New nickname
    /// - Returns: LpacError code
    public func setNickname(iccid: String, nickname: String) throws -> LpacError {
        guard let ctx = context else { throw SmartCardError.missingContext }

        let result = lpac_set_nickname(ctx, iccid, nickname)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }
    
    /// Download a profile
    /// - Parameters:
    ///   - smdp: SM-DP+ address
    ///   - matchingId: Matching ID (activation code)
    ///   - imei: Device IMEI (optional)
    ///   - confirmationCode: Confirmation code (optional)
    ///   - progressHandler: Callback for download progress
    /// - Returns: LpacError code
    public func downloadProfile(
        smdp: String,
        matchingId: String?,
        imei: String? = nil,
        confirmationCode: String? = nil
    ) throws -> LpacError  {
        guard let ctx = context else { throw SmartCardError.missingContext }


        
        // Get a self reference for the callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Call the C function
        let result = lpac_download_profile(
            ctx,
            smdp,
            matchingId,
            imei,
            confirmationCode,
            downloadCallback,
            selfPtr
        )
        return LpacError(rawValue: Int(result.rawValue)) ?? .general

    }
}





// Define the Notification struct
