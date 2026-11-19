//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import CryptoKit
import Foundation
import Security

/// A DER element: its tag and either its parts (constructed) or its content.
struct DERNode: Equatable {
    var tag: [UInt8]
    var children: [DERNode]?
    var content: [UInt8] = []

    var isConstructed: Bool { tag.first.map { $0 & 0x20 != 0 } ?? false }

    static func parse(_ data: Data) -> DERNode? {
        let bytes = [UInt8](data)
        var index = 0
        guard let node = parse(bytes, &index, depth: 0), index == bytes.count else { return nil }
        return node
    }

    private static func parse(_ b: [UInt8], _ i: inout Int, depth: Int) -> DERNode? {
        guard depth < 64, i < b.count else { return nil }
        let start = i
        i += 1
        if b[start] & 0x1F == 0x1F {
            while i < b.count, b[i] & 0x80 != 0 { i += 1 }
            i += 1
        }
        guard i < b.count else { return nil }
        let tag = Array(b[start..<i])
        let first = b[i]
        i += 1
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count >= 1, count <= 4, i + count <= b.count else { return nil }
            for _ in 0..<count { length = length << 8 | Int(b[i]); i += 1 }
        }
        guard i + length <= b.count else { return nil }
        let end = i + length
        if tag[0] & 0x20 != 0 {
            var children: [DERNode] = []
            while i < end {
                guard let child = parse(b, &i, depth: depth + 1) else { return nil }
                children.append(child)
            }
            guard i == end else { return nil }
            return DERNode(tag: tag, children: children)
        }
        defer { i = end }
        return DERNode(tag: tag, children: nil, content: Array(b[i..<end]))
    }

    var encoded: [UInt8] {
        let body = children.map { $0.flatMap(\.encoded) } ?? content
        return tag + Self.length(body.count) + body
    }

    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func sequence(_ children: [DERNode]) -> DERNode { DERNode(tag: [0x30], children: children) }
    static func set(_ children: [DERNode]) -> DERNode { DERNode(tag: [0x31], children: children) }
    static func integer(_ value: [UInt8]) -> DERNode {
        // Positive: a leading zero when the top bit is set.
        var v = Array(value.drop { $0 == 0 })
        if v.isEmpty { v = [0] }
        if v[0] & 0x80 != 0 { v.insert(0, at: 0) }
        return DERNode(tag: [0x02], content: v)
    }
    static func oid(_ encoded: [UInt8]) -> DERNode { DERNode(tag: [0x06], content: encoded) }
    static let null = DERNode(tag: [0x05], content: [])
    static func octets(_ bytes: [UInt8]) -> DERNode { DERNode(tag: [0x04], content: bytes) }
    static let trueValue = DERNode(tag: [0x01], content: [0xFF])
}

/// A timestamp authority (RFC 3161): vouches that a signature existed at a time, so it can be
/// checked against the signer's certificate as it was then.
public struct TimestampAuthority: Sendable {
    public let url: URL
    /// Sends a request (DER) and returns the reply; over HTTP by default.
    public let send: @Sendable (Data) throws -> Data

    public init(url: URL, send: (@Sendable (Data) throws -> Data)? = nil) {
        self.url = url
        self.send = send ?? { request in try Self.post(request, to: url) }
    }

    public enum Failure: LocalizedError {
        case unreachable(String), refused(Int), unreadable
        public var errorDescription: String? {
            switch self {
            case .unreachable(let why): return "The timestamp server couldn't be reached: \(why)"
            case .refused(let status): return "The timestamp server refused the request (status \(status))."
            case .unreadable: return "The timestamp server's reply couldn't be read."
            }
        }
    }

    /// POSTs a request and waits for the reply, up to 20 seconds.
    static func post(_ request: Data, to url: URL) throws -> Data {
        var http = URLRequest(url: url, timeoutInterval: 20)
        http.httpMethod = "POST"
        http.httpBody = request
        http.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        http.setValue("application/timestamp-reply", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(Failure.unreachable("no reply"))
        URLSession.shared.dataTask(with: http) { data, response, error in
            if let error {
                result = .failure(Failure.unreachable(error.localizedDescription))
            } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                result = .failure(Failure.unreachable("HTTP \(status)"))
            } else {
                result = .success(data ?? Data())
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    // sha256: 2.16.840.1.101.3.4.2.1; id-aa-timeStampToken: 1.2.840.113549.1.9.16.2.14
    static let sha256OID: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
    static let timeStampTokenOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x02, 0x0E]

    /// A TimeStampReq for `hash` (SHA-256), asking for the authority's certificate too.
    static func request(hash: [UInt8], nonce: [UInt8]) -> Data {
        let imprint = DERNode.sequence([.sequence([.oid(sha256OID), .null]), .octets(hash)])
        return Data(DERNode.sequence([.integer([1]), imprint, .integer(nonce), .trueValue]).encoded)
    }

    /// The token in a TimeStampResp, if the authority granted it.
    static func token(fromReply reply: Data) throws -> DERNode {
        guard let response = DERNode.parse(reply), let parts = response.children, let statusInfo = parts.first,
              let status = statusInfo.children?.first, status.tag == [0x02] else { throw Failure.unreadable }
        let code = status.content.reduce(0) { $0 << 8 | Int($1) }
        guard code == 0 || code == 1 else { throw Failure.refused(code) }
        guard parts.count >= 2 else { throw Failure.unreadable }
        return parts[1]
    }

    /// `signature` (a CMS SignedData, DER) with a timestamp of its signer's signature added.
    public func timestamped(_ signature: Data) throws -> Data {
        guard var contentInfo = DERNode.parse(signature), contentInfo.children?.count == 2,
              var explicit = contentInfo.children?[1], var signedData = explicit.children?.first,
              var signerInfos = signedData.children?.last, signerInfos.tag == [0x31],
              var signerInfo = signerInfos.children?.first,
              let signatureIndex = signerInfo.children?.firstIndex(where: { $0.tag == [0x04] }) else { throw Failure.unreadable }
        let value = signerInfo.children![signatureIndex].content
        let hash = Array(SHA256.hash(data: value))
        var nonce = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce)
        let token = try Self.token(fromReply: send(Self.request(hash: hash, nonce: nonce)))
        let attribute = DERNode.sequence([.oid(Self.timeStampTokenOID), .set([token])])
        // Unsigned attributes, [1] IMPLICIT, after the signature: added to, or made.
        if let index = signerInfo.children!.firstIndex(where: { $0.tag == [0xA1] }) {
            signerInfo.children![index].children!.append(attribute)
        } else {
            signerInfo.children!.append(DERNode(tag: [0xA1], children: [attribute]))
        }
        signerInfos.children![0] = signerInfo
        signedData.children![signedData.children!.count - 1] = signerInfos
        explicit.children![0] = signedData
        contentInfo.children![1] = explicit
        return Data(contentInfo.encoded)
    }
}
