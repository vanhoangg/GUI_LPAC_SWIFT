//
//  NetworkHttpInterface.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/3/25.
//

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
    func transmit(url: String, headers: [String: String], data: Data?) -> HttpResponse
}

class NetworkHttpInterface: NSObject, HttpInterface {
    func transmit(url: String, headers: [String: String], data: Data?) -> HttpInterface.HttpResponse {
        print("HTTP Request to: \(url)")
        
        // Create URL request
        guard let url = URL(string: url) else {
            return (Data(), 400, false)
        }
 
        var request = URLRequest(url: url)
        
        if let data = data {
            
            request.httpMethod = "POST"
            request.httpBody = data
        } else {
            request.httpMethod = "GET"
        }
        request.setValue("gsma-rsp-lpad", forHTTPHeaderField: "User-Agent")
        request.setValue("header", forHTTPHeaderField: "Content-Type")
        request.setValue("gsma/rsp/v2.2.0", forHTTPHeaderField: "X-Admin-Protocol")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Add headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Use semaphore for synchronous request
        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var statusCode = 0
        var success = false
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request) { data, response, error in
            if let data = data, let response = response as? HTTPURLResponse {
                responseData = data
                statusCode = response.statusCode
                success = (200...299).contains(response.statusCode)
            }
            semaphore.signal()
        }
        task.resume()
        
        // Wait for the request to complete
        _ = semaphore.wait(timeout: .now() + 30)
        
        return (responseData, statusCode, success)
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
