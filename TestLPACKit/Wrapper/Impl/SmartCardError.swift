//
//  SmartCardError.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/4/25.
//

struct SmartCardError {
    static let invalidResponse = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
    static let invalidCommand = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid command"])

    static let cardNotConnected = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Card not connected"])
    static let failedGetEUICC = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get EUICC Info"])
    static let missingContext = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Context"])
    static let failedGetProfile = NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get Profile Info"])


}
