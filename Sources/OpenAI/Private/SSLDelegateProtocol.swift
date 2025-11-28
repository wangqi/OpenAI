import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SSLDelegateProtocol: Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    )
}

// wangqi 2025-11-28: Adapter to use SSLDelegateProtocol with regular URLSession requests
/// Wraps an SSLDelegateProtocol to work as a URLSessionDelegate for non-streaming requests
/// This allows SSL certificate bypass for both streaming and non-streaming requests
public final class SSLURLSessionDelegateAdapter: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let sslDelegate: SSLDelegateProtocol

    public init(sslDelegate: SSLDelegateProtocol) {
        self.sslDelegate = sslDelegate
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        sslDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}
