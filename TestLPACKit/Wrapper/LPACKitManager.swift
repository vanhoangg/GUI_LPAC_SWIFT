import Foundation

/// Main class for interacting with the LPAC library
public class LpacManager {
    // Context pointer
    private var context: lpac_context_t?

    // Callbacks for APDU operations
    private var apduCallbacks = lpac_apdu_interface_t()
    private var httpCallbacks = lpac_http_interface_t()

    // Store Swift implementation objects
    private let apduInterface: ApduInterface
    private let httpInterface: HttpInterface

    // Retain callback references
    private var downloadCallbackHolder: ((LpacDownloadState) -> Void)?

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
            manager.apduInterface.logicalChannelOpen(aid: aidData) { intData in
                result = Int32(intData)
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

        apduCallbacks.transmit = { rx, rxLen, tx, txLen, userData in
            guard let userData = userData, let tx = tx else { return -1 }
            let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
            let semaphore = DispatchSemaphore(value: 0)
            var result: Int32 = -1

            let txData = Data(bytes: tx, count: Int(txLen))
           manager.apduInterface.transmit(data: txData) { response in
               // Set response data
               if let rx = rx, let rxLen = rxLen, !response.isEmpty {
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
            let result = manager.httpInterface.transmit(url: urlString, headers: headerDict, data: txData)

            // Set response code
            if let rcode = rcode {
                rcode.pointee = UInt32(result.statusCode)
            }

            // Set response data
            if let rx = rx, let rxLen = rxLen, !result.data.isEmpty {
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: result.data.count)
                result.data.copyBytes(to: buffer, count: result.data.count)
                rx.pointee = buffer
                rxLen.pointee = UInt32(result.data.count)
                return 0
            }

            return result.success ? 0 : -1
        }
    }

    deinit {
        cleanup()
    }

    /// Initialize the LPAC library with the ISD-R AID
    /// - Parameter isdrAid: The ISD-R AID to use
    /// - Returns: LpacError code
    public func initialize(isdrAid: Data) -> LpacError {
        // Clean up any existing context
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
            return .memory
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

    /// Get the EID (eUICC Identifier)
    /// - Returns: EID string or nil if an error occurred
    public func getEID() -> String? {
        guard let ctx = context else { return nil }

        var eidPtr: UnsafeMutablePointer<Int8>?
        let result = lpac_get_eid(ctx, &eidPtr)

        guard result == LPAC_SUCCESS, let ptr = eidPtr else {
            return nil
        }

        let eid = String(cString: ptr)
        lpac_free_string(ptr)
        return eid
    }
    public func getCardInfo() -> Es10cExEuiccInfo2? {
        guard let ctx = context else { return nil }

        var euiccPtr: UnsafeMutablePointer<lpac_euicc_info2>?
        let result = lpac_get_euicc_info(ctx, &euiccPtr)

        guard result == LPAC_SUCCESS, let euicc = euiccPtr else {
            return nil
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

        euiccInfo.uiccCapability = euicc.pointee.uiccCapability != nil ? convertCArrayToStringArray(cArray: euicc.pointee.uiccCapability) : nil
        euiccInfo.rspCapability = euicc.pointee.rspCapability != nil ? convertCArrayToStringArray(cArray: euicc.pointee.rspCapability): nil
        euiccInfo.forbiddenProfilePolicyRules = euicc.pointee.forbiddenProfilePolicyRules != nil ? convertCArrayToStringArray(cArray: euicc.pointee.forbiddenProfilePolicyRules) : nil

        euiccInfo.euiccCiPKIdListForVerification = euicc.pointee.euiccCiPKIdListForVerification != nil ? convertCArrayToStringArray(cArray: euicc.pointee.euiccCiPKIdListForVerification): nil
        euiccInfo.euiccCiPKIdListForSigning = euicc.pointee.euiccCiPKIdListForSigning != nil ? convertCArrayToStringArray(cArray: euicc.pointee.euiccCiPKIdListForSigning): nil

        var cardResource = ExtCardResource()
        cardResource.freeNonVolatileMemory = euicc.pointee.freeNonVolatileMemory
        cardResource.installedApplication = euicc.pointee.installedApplication
        cardResource.freeVolatileMemory = euicc.pointee.freeVolatileMemory
        euiccInfo.extCardResource = cardResource

        lpac_free_euicc_info(euiccPtr)
        return euiccInfo
    }

    /// Get profile information
    /// - Returns: Array of profiles or nil if an error occurred
    public func getProfilesInfo() -> [ProfileInfo]? {
        guard let ctx = context else { return nil }

        var profilesPtr: UnsafeMutablePointer<lpac_profile_list_t>?
        let result = lpac_get_profiles_info(ctx, &profilesPtr)

        guard result == LPAC_SUCCESS, let profiles = profilesPtr else {
            return nil
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
    public func enableProfile(iccid: String, refresh: Bool = true) -> LpacError {
        guard let ctx = context else { return .general }

        let result = lpac_enable_profile(ctx, iccid, refresh)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    /// Disable a profile
    /// - Parameters:
    ///   - iccid: ICCID of the profile to disable
    ///   - refresh: Whether to refresh the card after disabling
    /// - Returns: LpacError code
    public func disableProfile(iccid: String, refresh: Bool = true) -> LpacError {
        guard let ctx = context else { return .general }

        let result = lpac_disable_profile(ctx, iccid, refresh)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    /// Delete a profile
    /// - Parameter iccid: ICCID of the profile to delete
    /// - Returns: LpacError code
    public func deleteProfile(iccid: String) -> LpacError {
        guard let ctx = context else { return .general }

        let result = lpac_delete_profile(ctx, iccid)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    /// Set nickname for a profile
    /// - Parameters:
    ///   - iccid: ICCID of the profile
    ///   - nickname: New nickname
    /// - Returns: LpacError code
    public func setNickname(iccid: String, nickname: String) -> LpacError {
        guard let ctx = context else { return .general }

        let result = lpac_set_nickname(ctx, iccid, nickname)
        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    // Download progress callback wrapper
    private let downloadCallback: @convention(c) (lpac_download_state_t, UnsafeMutableRawPointer?) -> Void = { state, userData in
        guard let userData = userData else { return }
        let manager = Unmanaged<LpacManager>.fromOpaque(userData).takeUnretainedValue()
        let swiftState = LpacDownloadState(rawValue: Int(state.rawValue)) ?? .preparing
        manager.downloadCallbackHolder?(swiftState)
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
        confirmationCode: String? = nil,
        progressHandler: ((LpacDownloadState) -> Void)? = nil
    ) -> LpacError {
        guard let ctx = context else { return .general }

        // Save the Swift callback
        self.downloadCallbackHolder = progressHandler

        // Get a self reference for the callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Call the C function
        let result = lpac_download_profile(
            ctx,
            smdp,
            matchingId,
            imei,
            confirmationCode,
            progressHandler != nil ? downloadCallback : nil,
            selfPtr
        )

        return LpacError(rawValue: Int(result.rawValue)) ?? .general
    }

    /// Cancel all ongoing download sessions
    public func cancelSessions() {
        guard let ctx = context else { return }
        lpac_cancel_sessions(ctx)
    }
}

/// Swift interface for APDU operations
public protocol ApduInterface {
    /// Connect to the card
    /// - Returns: True if successful
    func connect(completion: @escaping (Bool) -> Void)

    /// Disconnect from the card
    func disconnect()

    /// Open a logical channel with the given AID
    /// - Parameter aid: AID to select
    /// - Returns: Channel number or negative value on error
    func logicalChannelOpen(aid: Data, completion: @escaping ((Int) -> Void))

    /// Close a logical channel
    /// - Parameter channel: Channel to close
    func logicalChannelClose(channel: Int)

    /// Transmit data to the card
    /// - Parameter data: Data to transmit
    /// - Returns: Response data
    func transmit(data: Data, completion: ((Data) -> Void)?)
}

/// Swift interface for HTTP operations
public protocol HttpInterface {
    /// HTTP response structure
    typealias HttpResponse = (data: Data, statusCode: Int, success: Bool)

    /// Transmit data via HTTP
    /// - Parameters:
    ///   - url: URL to connect to
    ///   - headers: HTTP headers
    ///   - data: Data to transmit (or nil for GET)
    /// - Returns: HTTP response
    func transmit(url: String, headers: [String: String], data: Data?) -> HttpResponse
}

/// Profile information structure
public struct ProfileInfo {
    public let iccid: String?
    public let name: String?
    public let provider: String?
    public let nickname: String?
    public let isdpAid: String?
    public let state: LpacProfileState
    public let profileClass: LpacProfileClass
}

public struct ExtCardResource {
    var installedApplication: UInt32?
    var freeNonVolatileMemory: UInt32?
    var freeVolatileMemory: UInt32?
    func toJsonString() -> String {
        var dict = [String: Any]()
        if let installedApplication = installedApplication {
            dict["installedApplication"] = installedApplication
        }
        if let freeNonVolatileMemory = freeNonVolatileMemory {
            dict["freeNonVolatileMemory"] = freeNonVolatileMemory
        }
        if let freeVolatileMemory = freeVolatileMemory {
            dict["freeVolatileMemory"] = freeVolatileMemory
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

public struct CertificationDataObject {
    var platformLabel: String?
    var discoveryBaseURL: String?
    func toJsonString() -> String {
        var dict = [String: Any]()
        if let platformLabel = platformLabel {
            dict["platformLabel"] = platformLabel
        }
        if let discoveryBaseURL = discoveryBaseURL {
            dict["discoveryBaseURL"] = discoveryBaseURL
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

public struct Es10cExEuiccInfo2 {
    var profileVersion: String?
    var svn: String?
    var euiccFirmwareVer: String?
    var extCardResource: ExtCardResource?
    var uiccCapability: [String]?
    var ts102241Version: String?
    var globalplatformVersion: String?
    var rspCapability: [String]?
    var euiccCiPKIdListForVerification: [String]?
    var euiccCiPKIdListForSigning: [String]?
    var euiccCategory: String?
    var forbiddenProfilePolicyRules: [String]?
    var ppVersion: String?
    var sasAcreditationNumber: String?
    var certificationDataObject: CertificationDataObject?

    func toJsonString() -> String {
        var dict = [String: Any]()
        if let profileVersion = profileVersion {
            dict["profileVersion"] = profileVersion
        }
        if let svn = svn {
            dict["svn"] = svn
        }
        if let euiccFirmwareVer = euiccFirmwareVer {
            dict["euiccFirmwareVer"] = euiccFirmwareVer
        }
        if let extCardResource = extCardResource {
            dict["extCardResource"] = extCardResource.toJsonString()
        }
        if let uiccCapability = uiccCapability {
            dict["uiccCapability"] = uiccCapability
        }
        if let ts102241Version = ts102241Version {
            dict["ts102241Version"] = ts102241Version
        }
        if let globalplatformVersion = globalplatformVersion {
            dict["globalplatformVersion"] = globalplatformVersion
        }
        if let rspCapability = rspCapability {
            dict["rspCapability"] = rspCapability
        }
        if let euiccCiPKIdListForVerification = euiccCiPKIdListForVerification {
            dict["euiccCiPKIdListForVerification"] = euiccCiPKIdListForVerification
        }
        if let euiccCiPKIdListForSigning = euiccCiPKIdListForSigning {
            dict["euiccCiPKIdListForSigning"] = euiccCiPKIdListForSigning
        }
        if let euiccCategory = euiccCategory {
            dict["euiccCategory"] = euiccCategory
        }
        if let forbiddenProfilePolicyRules = forbiddenProfilePolicyRules {
            dict["forbiddenProfilePolicyRules"] = forbiddenProfilePolicyRules
        }
        if let ppVersion = ppVersion {
            dict["ppVersion"] = ppVersion
        }
        if let sasAcreditationNumber = sasAcreditationNumber {
            dict["sasAcreditationNumber"] = sasAcreditationNumber
        }
        if let certificationDataObject = certificationDataObject {
            dict["certificationDataObject"] = certificationDataObject.toJsonString()
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
public func convertCArrayToStringArray(cArray: UnsafeMutablePointer<UnsafePointer<Int8>?>) -> [String] {
    var intArray = [String]()
    var index = 0

    while let cString = cArray[index] {
        intArray.append(String(cString: cString))
        index += 1
    }

    return intArray
}
private func convertCArrayToStringArray(cArray: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> [String] {
    var stringArray = [String]()
    var index = 0
    while let cString = cArray[index] {
            stringArray.append(String(cString: cString))
        index += 1
    }

    return stringArray
}
