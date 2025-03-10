//
//  SmartCardApduInterface.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//

import Foundation
import CryptoTokenKit


/// Swift interface for APDU operations

public protocol ApduInterface: AnyObject {
    var port: UICCPort { get }
    /// Connect to the card
    /// - Returns: True if successful
    func connect(completion: @escaping (Bool) -> Void)
    
    /// Disconnect from the card
    func disconnect()
    
    /// Open a logical channel with the given AID
    /// - Parameter aid: AID to select
    /// - Returns: Channel number or negative value on error
    func logicalChannelOpen(aid: Data, completion: ((Result<Int, Error>) -> Void)?)
    
    /// Close a logical channel
    /// - Parameter channel: Channel to close
    func logicalChannelClose(channel: Int)
    
    /// Transmit data to the card
    /// - Parameter data: Data to transmit
    /// - Returns: Response data
    func transmit(data: Data, completion: ((Result<Data, Error>) -> Void)?)
    
    func selectedDevice(reader:String) throws
}


public struct UICCPort {
    var card: TKSmartCard?
    var slot: String?
    var channel: [Int]
    init(card: TKSmartCard? = nil, slot: String? = nil, cardIndex: Int? = nil, channel: [Int] = []) {
        self.card = card
        self.slot = slot
        self.channel = channel
    }
}
class SmartCardApduInterface: ApduInterface {
    var port: UICCPort = UICCPort()
    
    let initalCommand = "80AA00000AA9088100820101830107"
    let channelCommand = "0070000001"

    
    
    func selectedDevice(reader:String) throws {
        guard let slotManager = TKSmartCardSlotManager.default,let slot = slotManager.slotNamed( reader) else {
            throw SmartCardError.invalidReader
        }
        guard let card = slot.makeSmartCard() else {
            throw SmartCardError.missingCard
        }
        
        self.port.card = card
        self.port.slot = slot.name
    }


}
// MARK: - Private Func
extension SmartCardApduInterface {
    
    func sendAPDU(data: Data) async throws -> Data {
        print("Transmitting APDU: \(data.hexString)")
        guard let card = self.port.card else {
            throw SmartCardError.cardNotConnected
        }
        do {
            let response = try await card.transmit(data)
            guard response.count >= 2 else {
                throw SmartCardError.invalidResponse
            }

            return response
        } catch {
            throw error
        }
    }
    
}
// MARK: - Interface
extension SmartCardApduInterface {
    
    func connect(completion: @escaping (Bool) -> Void) {
        guard let reader = self.port.slot else {
            print(SmartCardError.invalidReader.localizedDescription)
            completion(false)
            return
        }
        Task {
            do {
                print("Connecting to smart card reader: \(reader)...")
                let response = try await self.port.card?.beginSession()
                completion(response ?? false)
            } catch {
                print("Failed to connect to smart card: \(error.localizedDescription)")
                completion(false)
            }
        }
    }
    
    func disconnect() {
        print("Disconnecting from smart card...")
        port.card?.endSession()
        port.card = nil
    }
    
    func logicalChannelOpen(aid: Data, completion: ((Result<Int, Error>) -> Void)? = nil) {
        print("logicalChannelOpen: - Opening logical channel with AID: \(aid.hexString)")
        let request = manageChannelCmd(open: true, channel: 0)
        Task {
            do {
                let response = try await sendAPDU(data: request)
                guard response.startIndex < response.count else {
                    let error = SmartCardError.initError("OPEN LOGICAL CHANNEL FAILED \(response.hexString)")
                    completion?(.failure(error))
                    return
                }
                
                let byte:UInt8 = response[response.startIndex]
                self.port.channel.append(Int(byte))
                let selectAid = selectByDfCmd(aid: [UInt8](aid), channel: byte)
                let selectAidResponse = try await sendAPDU(data: selectAid)
                completion?(.success(selectAidResponse.hexString != "6a82" ? 1 : -1))
            } catch {
                completion?(.failure(error))
            }
        }
        //        guard let initalCommand = initalCommand.hexadecimal else {
        //            print("Command: \(self.initalCommand)")
        //            completion?(.failure(SmartCardError.invalidCommand))
        //            return
        //        }
        //        guard let channelCommand = channelCommand.hexadecimal else {
        //            print("Command: \(self.channelCommand)")
        //            completion?(.failure(SmartCardError.invalidCommand))
        //            return
        //        }
        //        func transmitCommand(command:Data,success:@escaping ((Data) -> Void)) {
        //            transmit(data: command) { [weak self] result in
        //                guard let self else {
        //                    return
        //                }
        //                switch result {
        //                    case .success(let response):
        //                        success(response)
        //                    case .failure(let error):
        //                        print("Command: \(self.channelCommand)")
        //                        completion?(.failure(error))
        //                }
        //            }
        //        }
        //        transmitCommand(command: initalCommand, success: { [weak self] _ in
        //            guard let self else {
        //                return
        //            }
        //            transmitCommand(command: channelCommand, success: { channelResp in
        //                let channel = channelResp.prefix(2)
        //                let currentChannel = channel.prefix(1)
        //
        //                let selectCommand = self.buildSelectCommand(channel: currentChannel, aid: aid)
        //                transmitCommand(command: selectCommand) { aidResp in
        //                    self.port.channel = currentChannel.hexString
        //                    completion?(.success(aidResp.hexString != "6a82" ? 1 : -1))
        //                }
        //            })
        //
        //        })
    }
    
    func logicalChannelClose(channel: Int) {
        print("Closing logical channel: \(channel)")
        // Implementation would depend on the specific smart card protocol
    }
    
    func transmit(data: Data, completion: ((Result<Data, Error>) -> Void)? = nil) {
        print("Transmitting APDU: \(data.hexString)")
        Task {
            do {
                let result = try await self.sendAPDU(data: data)
                completion?(.success(result))

            } catch {
                completion?(.failure(error))
            }
        }
    }
    
}
// MARK: - Helper
extension SmartCardApduInterface {
    private func convertResponseStatus(data:Data) -> Data{
        let sw1:UInt8 = data[data.count - 2]
        let sw2:UInt8 = data[data.count - 1]
        var response = data.dropLast(2)
        response.append(sw1)
        response.append(sw2)
        print("data hex: \(data.hexString)")
        print("sw1: \(sw1)")
        print("sw2: \(sw2)")
        return response
    }
    private func buildSelectCommand(channel:Data,aid: Data) -> Data {
        var command = Data()
        command.append(channel) // CLA
        command.append(0xA4) // INS (SELECT)
        command.append(0x04) // P1 (Select by name)
        command.append(0x00) // P2 (First or only occurrence)
        command.append(UInt8(aid.count)) // Lc (Length of AID)
        command.append(aid) // AID data
        
        return command
    }
    private func buildCmd(cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8, data: [UInt8]?, le: UInt8?) -> Data {
        var cmd = [cla, ins, p1, p2]
        if let data = data {
            cmd.append(UInt8(data.count))
            cmd.append(contentsOf: data)
        }
        if let le = le {
            cmd.append(le)
        }
        return Data(cmd)
    }
    
    private func manageChannelCmd(open: Bool, channel: UInt8) -> Data {
        if open {
            return buildCmd(cla: 0x00, ins: 0x70, p1: 0x00, p2: 0x00, data: nil, le: 0x01)
        } else {
            return buildCmd(cla: channel, ins: 0x70, p1: 0x80, p2: channel, data: nil, le: nil)
        }
    }
    
    private func selectByDfCmd(aid: [UInt8], channel: UInt8) -> Data {
        return buildCmd(cla: channel, ins: 0xA4, p1: 0x04, p2: 0x00, data: aid, le: nil)
    }
}

