//
//  Es10cExEuiccInfo2.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/5/25.
//


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
