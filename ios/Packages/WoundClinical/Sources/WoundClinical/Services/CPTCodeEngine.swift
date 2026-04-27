import Foundation
import WoundCore

public final class CPTCodeEngine: Sendable {

    public init() {}

    public func suggestCodes(
        woundType: WoundClassification,
        assessment: WoundAssessment,
        areaCm2: Double,
        proceduresPerformed: [WoundProcedure] = []
    ) -> [CPTCodeSuggestion] {
        var suggestions: [CPTCodeSuggestion] = []

        suggestions.append(CPTCodeSuggestion(
            code: "97597",
            description: "Debridement, open wound, first 20 sq cm",
            category: .debridement,
            isSelected: false,
            confidenceReason: "Wound area \(String(format: "%.1f", areaCm2)) cm² — applies to first 20 cm²"
        ))

        if areaCm2 > 20 {
            let additionalUnits = Int(ceil((areaCm2 - 20) / 20))
            suggestions.append(CPTCodeSuggestion(
                code: "97598",
                description: "Debridement, open wound, each additional 20 sq cm (\(additionalUnits) unit\(additionalUnits > 1 ? "s" : ""))",
                category: .debridement,
                isSelected: false,
                confidenceReason: "Wound exceeds 20 cm² — \(additionalUnits) additional unit(s)"
            ))
        }

        for procedure in proceduresPerformed {
            switch procedure {
            case .negativePressure:
                suggestions.append(CPTCodeSuggestion(
                    code: "97605",
                    description: "Negative pressure wound therapy, ≤ 50 sq cm",
                    category: .negativePressure,
                    isSelected: true,
                    confidenceReason: "Negative pressure therapy documented"
                ))
            case .skinSubstitute:
                suggestions.append(CPTCodeSuggestion(
                    code: "15271",
                    description: "Application of skin substitute graft, trunk/extremities, first 25 sq cm",
                    category: .skinSubstitute,
                    isSelected: true,
                    confidenceReason: "Skin substitute application documented"
                ))
            default:
                break
            }
        }

        return suggestions
    }
}
