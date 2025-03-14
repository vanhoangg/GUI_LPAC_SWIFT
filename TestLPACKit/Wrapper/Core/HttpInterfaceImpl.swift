//
//  NetworkHttpInterface.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//
import AsyncHTTPClient
import NIO
import NIOSSL
/// Swift interface for HTTP operations
public protocol HttpInterface {
    /// HTTP response structure
    typealias HttpResponse = (data: Data, statusCode: Int, success: Bool)

    /// Transmit data via HTTP
    /// - Parameters:
    ///   - url: URL to connect to
    ///   - headers: HTTP headers
    ///   - data: Data to transmit (or nil for GET)
    /// - Returns: HTTP response
    func transmit(url: String, headers: [String: String], data: Data?, completion: @escaping (HttpInterface.HttpResponse) -> Void )
}

class HttpInterfaceImpl: NSObject, HttpInterface {
    func transmit(url: String, headers: [String: String], data: Data?, completion: @escaping (HttpInterface.HttpResponse) -> Void ) {
        print("HTTP Request to: \(url)")

        if let data = data {
            print("HTTP Body: \(String(buffer: ByteBuffer(data: data)))")
        }

        var responseData = Data()
        var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
        tlsConfiguration.certificateVerification = .none
            var request = HTTPClientRequest(url: url)
            request.tlsConfiguration = tlsConfiguration
            if let data = data {
                request.method = .POST
                request.body = .bytes(ByteBuffer(data: data))
            } else {
                request.method = .GET
            }
            request.headers.add(name: "User-Agent", value: "gsma-rsp-lpad")
            request.headers.add(name: "Content-Type", value: "application/json")
            request.headers.add(name: "X-Admin-Protocol", value: "gsma/rsp/v2.2.0")
            request.headers.add(name: "Accept", value: "application/json")

        Task {
            let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))

            let body = response.body
            let collectedBytes = try await body.collect(upTo: 1024 * 1024 * 30)
            print("Response Data: \(String(buffer: collectedBytes))")
            if let data = collectedBytes.getData(at: 0, length: collectedBytes.readableBytes) {
                responseData = data
            }
            if (200...299).contains(response.status.code) {
                completion((data: responseData, statusCode: Int(response.status.code), success: true))
            } else {
                completion((data: responseData, statusCode: Int(response.status.code), success: false))

            }
        }

    }
}
extension HttpInterfaceImpl: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Trust the certificate even if not valid
        guard let trust = challenge.protectionSpace.serverTrust else {
            print("Not trust: \(challenge.protectionSpace)")
            return
        }
        let urlCredential = URLCredential(trust: trust)
        completionHandler(.useCredential, urlCredential)
    }
}

// MARK: - Helper Extensions

extension Data {
    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
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

struct HttpResponse {
    let statusCode: Int
    let body: Data
}
