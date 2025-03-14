//
//  ProfileInfo.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/5/25.
//

public struct Notification {
    public enum Operation: Int {
        case unknown = 0
        case install = 1
        case delete = 2
        case enable = 3
        case disable = 4
    }

    public let seqNumber: UInt64
    public let notificationAddress: String
    public let iccid: String
    public let operation: Operation
}

/// Profile information structure
public struct ProfileInfo {
    public let iccid: String?
    public let name: String?
    public let provider: String?
    public let nickname: String?
    public let isdpAid: String?
    public let state: LpacProfileState?
    public let profileClass: LpacProfileClass?

    func toJsonString() -> String {
        var dict = [String: Any]()
        if let iccid = iccid {
            dict["iccid"] = iccid
        }
        if let name = name {
            dict["name"] = name
        }
        if let provider = provider {
            dict["provider"] = provider
        }
        if let nickname = nickname {
            dict["nickname"] = nickname
        }
        if let isdpAid = isdpAid {
            dict["isdpAid"] = isdpAid
        }
        if let state = state {
            dict["state"] = state.rawValue
        }
        if let profileClass = profileClass {
            dict["profileClass"] = profileClass.rawValue
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
