import Foundation
import WoundCore

public final class CMSComplianceChecker: Sendable {

    public init() {}

    public func check(
        assessment: WoundAssessment,
        hasLidarMeasurements: Bool,
        hasPhoto: Bool,
        hasTreatmentPlan: Bool,
        woundType: WoundClassification?,
        anatomicalLocation: AnatomicalLocation?,
        pushScore: Int?
    ) -> [ComplianceCheckItem] {
        var items: [ComplianceCheckItem] = []

        let hasMeasurements = hasLidarMeasurements || assessment.manualMeasurements != nil
        items.append(ComplianceCheckItem(
            requirement: "Wound measurements documented (L × W × D)",
            cmsGuideline: "CMS requires wound dimensions at each visit",
            isMet: hasMeasurements
        ))

        items.append(ComplianceCheckItem(
            requirement: "Wound bed description present",
            cmsGuideline: "Tissue type and percentage must be documented",
            isMet: assessment.woundBed.totalPercent == 100
        ))

        items.append(ComplianceCheckItem(
            requirement: "Exudate documented",
            cmsGuideline: "Drainage amount and type required",
            isMet: true
        ))

        items.append(ComplianceCheckItem(
            requirement: "Surrounding skin assessed",
            cmsGuideline: "Periwound skin condition must be documented",
            isMet: !assessment.surroundingSkin.conditions.isEmpty
        ))

        items.append(ComplianceCheckItem(
            requirement: "Pain assessed",
            cmsGuideline: "Pain level should be documented at each visit",
            isMet: assessment.pain != nil
        ))

        items.append(ComplianceCheckItem(
            requirement: "Treatment plan documented",
            cmsGuideline: "Plan of care must be present for billing",
            isMet: hasTreatmentPlan
        ))

        items.append(ComplianceCheckItem(
            requirement: "Wound type/etiology documented",
            cmsGuideline: "Wound classification required for ICD-10 coding",
            isMet: woundType != nil
        ))

        items.append(ComplianceCheckItem(
            requirement: "Anatomical location specified",
            cmsGuideline: "Wound location must be documented",
            isMet: anatomicalLocation != nil
        ))

        items.append(ComplianceCheckItem(
            requirement: "PUSH/BWAT score calculated",
            cmsGuideline: "Standardized wound assessment tool required",
            isMet: pushScore != nil
        ))

        items.append(ComplianceCheckItem(
            requirement: "Photo documentation present",
            cmsGuideline: "Photographic evidence recommended at each visit",
            isMet: hasPhoto
        ))

        return items
    }
}
