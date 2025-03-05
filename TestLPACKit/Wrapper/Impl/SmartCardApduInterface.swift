//
//  SmartCardApduInterface.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//

import Foundation
import CryptoTokenKit

class SmartCardApduInterface: ApduInterface {


    
    private var card: TKSmartCard?
    private var slotManager: TKSmartCardSlotManager? = TKSmartCardSlotManager.default
    private var slot: TKSmartCardSlot?
    
    let initalCommand = "80AA00000AA9088100820101830107"
    let channelCommand = "0070000001"

  
    func selectedDevice(reader:String) {
        
        guard let slot = slotManager?.slotNamed(reader) else {
            print("Invalid reader")
            return
        }
        
        guard let card = slot.makeSmartCard() else {
            print("No card found in reader")
            return
        }
        self.card = card
        self.slot = slot
    }
    
    func connect(completion: @escaping (Bool) -> Void) {
        let reader = TKSmartCardSlotManager.default?.slotNames.first
        guard let reader else {
            completion(false)
            return
        }
        selectedDevice(reader: reader)
  
        print("Connecting to smart card reader: \(reader)...")

        
        self.card?.beginSession { [weak self] success, error in
            guard let self else { return }
            if let error = error {
                print("Failed to connect to smart card: \(error.localizedDescription)")
                completion(false)
                return
            }
            completion(success)
        }
    }
    
    func disconnect() {
        print("Disconnecting from smart card...")
        card?.endSession()
        card = nil
    }
    
    func logicalChannelOpen(aid: Data, completion: ((Result<Int, Error>) -> Void)? = nil) {
        print("logicalChannelOpen: - Opening logical channel with AID: \(aid.hexadecimal)")
        guard let initalCommand = initalCommand.hexadecimal else {
            print("Command: \(self.initalCommand)")
            completion?(.failure(SmartCardError.invalidCommand))
            return
        }
        guard let channelCommand = channelCommand.hexadecimal else {
            print("Command: \(self.channelCommand)")
            completion?(.failure(SmartCardError.invalidCommand))
            return
        }
        func transmitCommand(command:Data,success:@escaping ((Data) -> Void)) {
            transmit(data: command) { [weak self] result in
                guard let self else {
                    return
                }
                switch result {
                    case .success(let response):
                        success(response)
                    case .failure(let error):
                        print("Command: \(self.channelCommand)")
                        completion?(.failure(error))
                }
            }
        }
        transmitCommand(command: initalCommand, success: { [weak self] _ in
            guard let self else {
                return
            }
            transmitCommand(command: channelCommand, success: { channelResp in
                let channel = channelResp.prefix(2)
                let currentChannel = channel.prefix(1)
                let selectCommand = self.buildSelectCommand(channel: currentChannel, aid: aid)
                transmitCommand(command: selectCommand) { aidResp in
                    completion?(.success(aidResp.hexString != "6a82" ? 1 : -1))
                }
            })
            
        })
    }
    
    func logicalChannelClose(channel: Int) {
        print("Closing logical channel: \(channel)")
        // Implementation would depend on the specific smart card protocol
    }
    
    func transmit(data: Data, completion: ((Result<Data, Error>) -> Void)? = nil) {
        print("Transmitting APDU: \(data.hexadecimal)")
        sendApdu(command: data) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    guard response.count >= 2 else {
                        completion?(.failure(SmartCardError.invalidResponse))
                        return
                    }
                    completion?(.success(response))
//                    if sw1 == 0x90 && sw2 == 0x00 {
//                        
//                    } else {
//                        print("Error: Response Failed")
//                    }
                case .failure(let failure):
                    completion?(.failure(failure))
            }
        }
    }
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
    
    private func sendApdu(command: Data, completion: @escaping ((Result<Data, Error>) -> Void)) {
        guard let card = self.card else {
            completion(.failure(SmartCardError.cardNotConnected))
            return
        }
        card.transmit(command) { data , error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(data ?? Data()))
            }
            
        }
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
}


