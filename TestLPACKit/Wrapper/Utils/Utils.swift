//
//  Utils.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/5/25.
//




struct LPACKitUtils {
    static func convertCArrayToStringArray(cArray: UnsafeMutablePointer<UnsafePointer<Int8>?>) -> [String] {
        var intArray = [String]()
        var index = 0
        
        while let cString = cArray[index] {
            intArray.append(String(cString: cString))
            index += 1
        }
        
        return intArray
    }
    static func convertCArrayToStringArray(cArray: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> [String] {
        var stringArray = [String]()
        var index = 0
        while let cString = cArray[index] {
            stringArray.append(String(cString: cString))
            index += 1
        }
        
        return stringArray
    }
}
