import Foundation
import WoundAutoSegmentation

// MARK: - Segmentation Error Messages

/// Maps segmentation errors to cause-specific, user-facing messages.
/// Every message includes a "Draw Manually" fallback call-to-action.
enum SegmentationErrorMessages {

    static func userMessage(for error: Error) -> String {
        guard let segError = error as? SegmentationError else {
            return "Segmentation failed unexpectedly. Use Draw Manually."
        }
        switch segError {
        case .unsupportedOSVersion:
            return "Auto-detect requires iOS 17+. Use Draw Manually."
        case .noForegroundDetected:
            return "No wound detected in the image. Use Draw Manually."
        case .tapPointMissedAllInstances:
            return "Tap missed the wound. Try tapping directly on it, or use Draw Manually."
        case .maskGenerationFailed:
            return "Could not generate wound mask. Use Draw Manually."
        case .contourExtractionFailed:
            return "Could not trace wound outline. Use Draw Manually."
        case .invalidInputImage:
            return "Captured image is invalid. Recapture or use Draw Manually."
        case .modelLoadFailed:
            return "Wound detection model failed to load. Use Draw Manually."
        case .predictionFailed:
            return "On-device detection failed. Use Draw Manually."
        case .serviceUnavailable(let underlying):
            return serviceUnavailableMessage(underlying: underlying)
        }
    }

    private static func serviceUnavailableMessage(underlying: Error?) -> String {
        guard let underlying else {
            return "Server segmentation unavailable. Check your connection or use Draw Manually."
        }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Use Draw Manually."
            case NSURLErrorTimedOut:
                return "Server request timed out. Retry or use Draw Manually."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return "Cannot reach segmentation server. Use Draw Manually."
            default:
                return "Network error. Check connection or use Draw Manually."
            }
        }
        return "Server segmentation failed. Retry or use Draw Manually."
    }
}
