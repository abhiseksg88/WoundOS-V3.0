import Foundation

// MARK: - API Endpoints

/// All backend API endpoint definitions.
/// Base URL is configured per environment.
public enum Endpoints {

    public enum Environment: String {
        case development = "http://localhost:8080"
        case staging = "https://api-staging.woundos.com"
        case production = "https://api.woundos.com"
    }

    public static var environment: Environment = .development

    public static var baseURL: URL {
        URL(string: environment.rawValue)!
    }

    // MARK: - Scan Upload

    /// POST /v1/scans/upload — Multipart upload of scan data
    public static var uploadScan: URL {
        baseURL.appendingPathComponent("v1/scans/upload")
    }

    // MARK: - Scan Queries

    /// GET /v1/scans/{scanId} — Fetch a single scan with all fields
    public static func scan(id: String) -> URL {
        baseURL.appendingPathComponent("v1/scans/\(id)")
    }

    /// GET /v1/patients/{patientId}/scans — List scans for a patient
    public static func patientScans(patientId: String) -> URL {
        baseURL.appendingPathComponent("v1/patients/\(patientId)/scans")
    }

    /// GET /v1/scans/{scanId}/status — Check processing status
    public static func scanStatus(id: String) -> URL {
        baseURL.appendingPathComponent("v1/scans/\(id)/status")
    }

    // MARK: - Review

    /// PATCH /v1/scans/{scanId}/review — Submit review for flagged scan
    public static func reviewScan(id: String) -> URL {
        baseURL.appendingPathComponent("v1/scans/\(id)/review")
    }

    // MARK: - Auth

    /// POST /v1/auth/token — Exchange Firebase token for API token
    public static var authToken: URL {
        baseURL.appendingPathComponent("v1/auth/token")
    }
}
