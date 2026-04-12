import Foundation

// MARK: - Review Status

/// Tracks the clinical review lifecycle of a flagged scan.
public struct ReviewStatus: Codable, Sendable, Equatable {

    /// Current state of review
    public let state: ReviewState

    /// ID of the clinician who reviewed (nil if not yet reviewed)
    public let reviewedBy: String?

    /// When the review was completed
    public let reviewedAt: Date?

    /// Clinician's notes during review
    public let reviewNotes: String?

    /// If the clinician provided a corrected boundary, its ID
    public let correctedBoundaryId: UUID?

    public init(
        state: ReviewState = .notFlagged,
        reviewedBy: String? = nil,
        reviewedAt: Date? = nil,
        reviewNotes: String? = nil,
        correctedBoundaryId: UUID? = nil
    ) {
        self.state = state
        self.reviewedBy = reviewedBy
        self.reviewedAt = reviewedAt
        self.reviewNotes = reviewNotes
        self.correctedBoundaryId = correctedBoundaryId
    }
}

// MARK: - Review State

public enum ReviewState: String, Codable, Sendable {
    /// Not flagged — no review needed
    case notFlagged = "not_flagged"
    /// Flagged by agreement metrics — awaiting review
    case pendingReview = "pending_review"
    /// Reviewed and nurse measurement accepted as correct
    case reviewedAccepted = "reviewed_accepted"
    /// Reviewed and clinician provided corrected boundary
    case reviewedAdjusted = "reviewed_adjusted"
    /// Reviewed and rejected (e.g., scan quality too poor)
    case reviewedRejected = "reviewed_rejected"
}
