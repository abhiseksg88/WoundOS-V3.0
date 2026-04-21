import Foundation

// MARK: - API Endpoints

/// All backend API endpoint URL construction.
/// Uses APIConfig for base URL; defaults to Cloud Run staging.
public enum Endpoints {

    public static var config = APIConfig.staging

    // MARK: - Health

    /// GET /health — No version prefix per backend spec.
    public static var health: URL {
        config.baseURL.appendingPathComponent("health")
    }

    // MARK: - Auth

    /// POST /v1/auth/token — Exchange Firebase token for API bearer token.
    public static var authToken: URL {
        config.versionedURL.appendingPathComponent("auth/token")
    }

    // MARK: - Scan Upload

    /// POST /v1/scans/upload — Multipart upload of scan data.
    public static var uploadScan: URL {
        config.versionedURL.appendingPathComponent("scans/upload")
    }

    // MARK: - Scan Queries

    /// GET /v1/scans/{scanId} — Fetch a single scan with all fields.
    public static func scan(id: String) -> URL {
        config.versionedURL.appendingPathComponent("scans/\(id)")
    }

    /// GET /v1/patients/{patientId}/scans — List scans for a patient.
    public static func patientScans(patientId: String) -> URL {
        config.versionedURL.appendingPathComponent("patients/\(patientId)/scans")
    }

    /// GET /v1/scans/{scanId}/status — Check processing status.
    public static func scanStatus(id: String) -> URL {
        config.versionedURL.appendingPathComponent("scans/\(id)/status")
    }

    // MARK: - Review

    /// PATCH /v1/scans/{scanId}/review — Submit review for flagged scan.
    public static func reviewScan(id: String) -> URL {
        config.versionedURL.appendingPathComponent("scans/\(id)/review")
    }
}
