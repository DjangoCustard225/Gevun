import Foundation

func friendlyError(_ error: Error) -> String {
    if let error = error as? URLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "You're offline. Connect to your network and try again."
        case .timedOut: return "The server took too long to respond. Try again."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "Couldn't reach your server. Check its address, network, and VPN."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .secureConnectionFailed:
            return "The server's secure connection could not be verified. Check its HTTPS certificate."
        default: return "The connection failed. Check your server and try again."
        }
    }
    return error.localizedDescription
}
