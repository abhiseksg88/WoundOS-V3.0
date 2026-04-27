import UIKit
import Foundation
import Combine
import WoundCore
import WoundClinical
import WoundNetworking
import CaptureSync

// MARK: - Wound Assessment View Model

final class WoundAssessmentViewModel: ObservableObject {

    // MARK: - Context

    let scan: WoundScan
    var patient: Patient?
    var wound: Wound?

    // MARK: - Wound Bed (must sum to 100%)

    @Published var granulationPercent: Int = 0
    @Published var sloughPercent: Int = 0
    @Published var necroticPercent: Int = 0
    @Published var epithelialPercent: Int = 0
    @Published var otherTissuePercent: Int = 100

    var woundBedTotal: Int {
        granulationPercent + sloughPercent + necroticPercent + epithelialPercent + otherTissuePercent
    }

    var woundBedValid: Bool { woundBedTotal == 100 }

    // MARK: - Exudate

    @Published var exudateAmount: ExudateAmount = .none
    @Published var exudateType: ExudateType = .serous
    @Published var exudateColor: ExudateColor = .clear

    // MARK: - Surrounding Skin

    @Published var selectedPeriwoundConditions: Set<PeriwoundCondition> = [.intact]

    // MARK: - Pain

    @Published var painLevel: Int = 0
    @Published var painTiming: PainTiming = .atRest

    // MARK: - Odor

    @Published var odorLevel: OdorLevel = .none

    // MARK: - Manual Depth (shown when LiDAR depth is 0 or unavailable)

    @Published var manualDepthCm: String = ""

    var needsManualDepth: Bool {
        scan.primaryMeasurement.maxDepthMm <= 0.1
    }

    // MARK: - Clinical Notes

    @Published var clinicalNotes: String = ""

    // MARK: - State

    @Published var isSaving = false
    @Published var error: String?

    // MARK: - Navigation

    var onAssessmentComplete: ((WoundAssessment) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Dependencies

    private let clinicalStorage: ClinicalStorageProvider
    private let scanStorage: StorageProviderProtocol
    private let uploadManager: UploadManager
    private let tokenStore: ClinicalPlatformTokenStore
    private let clinicalPlatformClient: ClinicalPlatformClient

    // MARK: - Init

    init(
        scan: WoundScan,
        patient: Patient?,
        wound: Wound?,
        clinicalStorage: ClinicalStorageProvider,
        scanStorage: StorageProviderProtocol,
        uploadManager: UploadManager,
        tokenStore: ClinicalPlatformTokenStore,
        clinicalPlatformClient: ClinicalPlatformClient,
        manualMeasurementsFromResult: ManualMeasurements? = nil
    ) {
        self.scan = scan
        self.patient = patient
        self.wound = wound
        self.clinicalStorage = clinicalStorage
        self.scanStorage = scanStorage
        self.uploadManager = uploadManager
        self.tokenStore = tokenStore
        self.clinicalPlatformClient = clinicalPlatformClient
        self.prefilledManualMeasurements = manualMeasurementsFromResult
        if let m = manualMeasurementsFromResult {
            if let d = m.depthCm { self.manualDepthCm = String(d) }
        }
    }

    private var prefilledManualMeasurements: ManualMeasurements?

    // MARK: - Save

    func saveAssessment() {
        isSaving = true

        let manualMeasurements: ManualMeasurements?
        if let prefilled = prefilledManualMeasurements {
            var merged = prefilled
            if needsManualDepth, let depth = Double(manualDepthCm), depth > 0 {
                merged.depthCm = depth
            }
            manualMeasurements = merged
        } else if needsManualDepth, let depth = Double(manualDepthCm), depth > 0 {
            manualMeasurements = ManualMeasurements(
                depthCm: depth,
                source: .nurseEntered
            )
        } else {
            manualMeasurements = nil
        }

        let verifiedUser = tokenStore.loadVerifiedUser()
        let nurseId = verifiedUser?.userId ?? "unknown"
        let facilityId = verifiedUser?.facilityId ?? "unknown"

        let encounter = Encounter(
            patientId: patient?.id ?? UUID(),
            nurseId: nurseId,
            facilityId: facilityId,
            woundAssessmentIds: [],
            documentationStatus: .inProgress
        )

        let assessment = WoundAssessment(
            woundId: wound?.id ?? UUID(),
            encounterId: encounter.id,
            scanId: scan.id,
            woundBed: WoundBedDescription(
                granulationPercent: granulationPercent,
                sloughPercent: sloughPercent,
                necroticPercent: necroticPercent,
                epithelialPercent: epithelialPercent,
                otherPercent: otherTissuePercent
            ),
            exudate: ExudateAssessment(
                amount: exudateAmount,
                type: exudateType,
                color: exudateColor
            ),
            surroundingSkin: SurroundingSkinAssessment(
                conditions: Array(selectedPeriwoundConditions)
            ),
            pain: PainAssessment(level: painLevel, timing: painTiming),
            odor: odorLevel,
            manualMeasurements: manualMeasurements,
            clinicalNotes: clinicalNotes
        )

        Task { @MainActor in
            do {
                try await clinicalStorage.saveAssessment(assessment)

                var savedEncounter = encounter
                savedEncounter.woundAssessmentIds = [assessment.id]
                try await clinicalStorage.saveEncounter(savedEncounter)

                var updatedScan = scan
                updatedScan.woundId = wound?.id
                updatedScan.encounterId = encounter.id
                updatedScan.anatomicalLocation = wound?.anatomicalLocation.displayName
                try await scanStorage.saveScan(updatedScan)
                await uploadManager.enqueueUpload(scan: updatedScan)

                CrashLogger.shared.log(
                    "Assessment saved — encounter=\(encounter.id), nurse=\(nurseId), facility=\(facilityId)",
                    category: .storage
                )

                let uploadMsg = await self.uploadToReplit(scan: updatedScan, manualMeasurements: manualMeasurements, verifiedUser: verifiedUser)

                isSaving = false
                onAssessmentComplete?(assessment)

                if let msg = uploadMsg {
                    showToast(msg)
                }
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }

    // MARK: - Replit Upload

    private func showToast(_ message: String) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return }

        let toast = UILabel()
        toast.text = message
        toast.font = WOFonts.subheadline
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.numberOfLines = 2
        toast.layer.cornerRadius = 12
        toast.layer.cornerCurve = .continuous
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0

        window.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -24),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        UIView.animate(withDuration: 0.3) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 3.0) {
            toast.alpha = 0
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }

    @MainActor
    private func uploadToReplit(scan: WoundScan, manualMeasurements: ManualMeasurements?, verifiedUser: VerifiedUser?) async -> String? {
        guard let token = tokenStore.loadToken(),
              let baseURLString = tokenStore.loadBaseURL(),
              let baseURL = URL(string: baseURLString),
              let user = verifiedUser else {
            CrashLogger.shared.log("Replit upload skipped — no token configured", category: .network)
            return nil
        }

        let m = scan.primaryMeasurement
        let manualPayload: ManualMeasurementsPayload? = manualMeasurements.map {
            ManualMeasurementsPayload(
                lengthCm: $0.lengthCm,
                widthCm: $0.widthCm,
                depthCm: $0.depthCm,
                method: $0.source.rawValue
            )
        }

        let rgbBase64 = scan.captureData.rgbImageData.base64EncodedString()

        let payload = CaptureUploadPayload(
            captureId: scan.id,
            capturedAt: scan.capturedAt,
            device: DevicePayload.current(),
            capturedBy: CapturedByPayload(from: user),
            pushScore: Double(scan.pushScore.totalScore),
            notes: "",
            segmentation: SegmentationPayload(
                confidence: 0.95,
                maskCoveragePct: 0.0
            ),
            measurements: MeasurementsPayload(
                lengthCm: m.lengthMm / 10.0,
                widthCm: m.widthMm / 10.0,
                areaCm2: m.areaCm2,
                perimeterCm: m.perimeterMm / 10.0,
                depthCm: m.maxDepthMm / 10.0
            ),
            manualMeasurements: manualPayload,
            lidarMetadata: LiDARMetadataPayload(
                captureDistanceCm: 30.0,
                lidarConfidencePct: 85,
                frameCount: 1
            ),
            artifacts: ArtifactsPayload(
                rgbImageBase64: rgbBase64,
                maskImageBase64: "",
                overlayImageBase64: ""
            )
        )

        do {
            CrashLogger.shared.log(
                "Replit upload starting — url=\(baseURL.absoluteString)/api/v1/captures, bodySize=\(rgbBase64.count) chars base64",
                category: .network
            )
            let result = try await clinicalPlatformClient.upload(payload: payload, token: token, baseURL: baseURL)
            CrashLogger.shared.log(
                "Replit upload success — captureId=\(result.serverCaptureId), webUrl=\(result.webURL)",
                category: .network
            )
            return "Uploaded to Clinical Platform"
        } catch {
            CrashLogger.shared.log(
                "Replit upload failed (non-blocking): \(error)",
                category: .network,
                level: .warning
            )
            let shortError: String
            if let cpError = error as? ClinicalPlatformError {
                shortError = "\(cpError)"
            } else {
                shortError = error.localizedDescription
            }
            return "Upload failed: \(shortError.prefix(80))"
        }
    }
}
