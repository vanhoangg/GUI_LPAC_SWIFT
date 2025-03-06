//
//  ConsolePrint.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/5/25.
//


#if DEBUG

import OSLog
// Override print with a print that puts line number.... https://stackoverflow.com/a/55835930
public func print(_ items: String...,
                  filename: String = #file,
                  function: String = #function,
                  line: Int = #line,
                  separator: String = " ",
                  terminator: String = "🔹──────────────────────────────🔹") {
    let logger = Logger(subsystem: Date().debugDescription, category: URL(fileURLWithPath: filename).lastPathComponent)
    let output = "\(items.compactMap { $0 }.joined(separator: separator))"
    logger.info("\(terminator)\n\(output)\n\(terminator)")
//    Swift.print(pretty+output, terminator: terminator)

}
#endif
