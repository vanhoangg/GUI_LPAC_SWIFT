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

    @objc private func slotStateChanged(notification: Notification) {
        guard let slot = notification.object as? TKSmartCardSlot else { return }
        if slot.state == .validCard {
            print("Smart card inserted")
            // Handle smart card insertion
        } else {
            print("Smart card removed")
            // Handle smart card removal
        }
    }
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

        
        self.card?.beginSession {[weak self] success, error in
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
    
    func logicalChannelOpen(aid: Data, completion: @escaping ((Int) -> Void)) {
        print("Opening logical channel with AID: \(aid.hexadecimal)")
        guard let initalCommand = initalCommand.hexadecimal else {
            return
        }
        transmit(data: initalCommand) { [weak self] data in
            guard let self, let channelCommand = channelCommand.hexadecimal else {
                completion(-1)
                return
            }
            transmit(data: channelCommand) { channelResp in
                let channel = channelResp.prefix(2)
                let currentChannel = channel.prefix(1)
                let selectCommand = self.buildSelectCommand(channel: currentChannel, aid: aid)
                self.transmit(data: selectCommand) { aidResp in
                    completion(aidResp.hexString != "6a82" ? 1 : -1)
                }
            }

        }
    }
    
    func logicalChannelClose(channel: Int) {
        print("Closing logical channel: \(channel)")
        // Implementation would depend on the specific smart card protocol
    }
    
    func transmit(data: Data, completion: ((Data) -> Void)? = nil) {
        print("Transmitting APDU: \(data.hexadecimal)")
        
        do {
            try sendApdu(command: data) { data, error in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                guard let data = data, data.count >= 2 else {
                    print("Error: Invalid response")
                    return
                }
                let sw1:UInt8 = data[data.count - 2]
                let sw2:UInt8 = data[data.count - 1]
                var response = data.dropLast(2)
                response.append(sw1)
                response.append(sw2)
                print("data hex: \(data.hexString)")
                print("sw1: \(sw1)")
                print("sw2: \(sw2)")
                completion?(response)
                if sw1 == 0x90 && sw2 == 0x00 {
                  
                } else {
                    print("Error: Response Failed")
                }
                
           
            }
        } catch {
            print("Error transmitting APDU: \(error.localizedDescription)")
        }
    }
    
    private func sendApdu(command: Data, completion: @escaping (Data?, Error?) -> Void) throws {
        guard let card = self.card else {
            throw NSError(domain: "SmartCardError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Card not connected"])
        }
        card.transmit(command, reply: completion)
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


