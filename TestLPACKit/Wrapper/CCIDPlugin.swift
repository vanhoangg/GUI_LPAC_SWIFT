//
//  CCIDPlugin.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//


import Foundation
import CryptoTokenKit

extension String {
    var hexadecimal: Data? {
        var data = Data(capacity: count / 2)
        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, range: NSRange(startIndex..., in: self)) { match, _, _ in
            if let match = match {
                let byteString = (self as NSString).substring(with: match.range)
                if let num = UInt8(byteString, radix: 16) {
                    data.append(num)
                }
            }
        }
        return data.isEmpty ? nil : data
    }
}

extension Data {
    var hexadecimal: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

class CCIDPlugin {
    private var cards: [String: TKSmartCard] = [:]

    func listReaders() -> [String] {
        return TKSmartCardSlotManager.default?.slotNames ?? []
    }

    func connect(reader: String) throws {
        guard let slot = TKSmartCardSlotManager.default?.slotNamed(reader) else {
            throw CCIDError.invalidReader
        }

        guard let card = slot.makeSmartCard() else {
            throw CCIDError.noCard
        }

        cards[reader] = card
    }

    func transceive(reader: String, apdu: String) async throws -> String {
        guard let capduData = apdu.hexadecimal else {
            throw CCIDError.invalidAPDU
        }

        guard let card = cards[reader] else {
            throw CCIDError.invalidReader
        }

        return try await withCheckedThrowingContinuation { continuation in
            card.beginSession { success, _ in
                guard success else {
                    continuation.resume(throwing: CCIDError.beginSessionError)
                    return
                }

                card.transmit(capduData) { rapdu, _ in
                    card.endSession()
                    if let rapdu = rapdu {
                        continuation.resume(returning: rapdu.hexadecimal)
                    } else {
                        continuation.resume(throwing: CCIDError.transmitError)
                    }
                }
            }
        }
    }

    func disconnect(reader: String) {
        cards.removeValue(forKey: reader)
    }
}

enum CCIDError: Error {
    case invalidReader
    case noCard
    case beginSessionError
    case transmitError
    case invalidAPDU

    var localizedDescription: String {
        switch self {
        case .invalidReader:
            return "Invalid reader"
        case .noCard:
            return "No card"
        case .beginSessionError:
            return "Begin session error"
        case .transmitError:
            return "Transmit error"
        case .invalidAPDU:
            return "Invalid APDU"
        }
    }
}
