//
//  SmartCardObserver.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/10/25.
//
import Foundation
import CryptoTokenKit


public class SmartCardObserver: NSObject {
    var card: TKSmartCard?
    var slot: TKSmartCardSlot?
    var channel: [Int] = []
    var onStateChanged: ((TKSmartCardSlot.State) -> Void)?
    
    init(onStateChanged: ((TKSmartCardSlot.State) -> Void)? = nil) {
        self.onStateChanged = onStateChanged
        super.init()
        guard let slot = TKSmartCardSlotManager.default?.slotNames.first.flatMap({
            TKSmartCardSlotManager.default?.slotNamed($0)
        }) else {
            print("⚠️ No smart card slot available.")
            return
        }
        
        guard let card = slot.makeSmartCard() else {
            print("⚠️ No smart card available.")
            return
        }
        self.slot = slot
        self.card = card
        slot.addObserver(self, forKeyPath: "state", options: [.new], context: nil)
        // Notify current state initially
        onStateChanged?(slot.state)
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                      change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "state", let slot = object as? TKSmartCardSlot else { return }
        onStateChanged?(slot.state)
    }
    
    deinit {
        slot?.removeObserver(self, forKeyPath: "state")
    }
}
