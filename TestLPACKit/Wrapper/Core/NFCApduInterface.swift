//
//  NFCApduInterface.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//
import CryptoKit

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

