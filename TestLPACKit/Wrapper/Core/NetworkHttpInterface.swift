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
    func transmit(url: String, headers: [String: String], data: Data?,completion: @escaping (Result<HttpInterface.HttpResponse,any Error>) -> Void )
}

class NetworkHttpInterface: NSObject, HttpInterface {
    func transmit(url: String, headers: [String: String], data: Data?, completion: @escaping (Result<HttpInterface.HttpResponse,any Error>) -> Void ) {
        print("HTTP Request to: \(url)")
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
            if let data = collectedBytes.getData(at: 0, length: collectedBytes.readableBytes) {
                responseData = data
                print("Response Data: \(responseData.hexString)")
            }
            completion(.success((data: responseData, statusCode: Int(response.status.code), success: (200...299).contains(response.status.code))))
        }

    }
}
extension NetworkHttpInterface: URLSessionDelegate {
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        //Trust the certificate even if not valid
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


struct HttpResponse {
    let statusCode: Int
    let body: Data
}
