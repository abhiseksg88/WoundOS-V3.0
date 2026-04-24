import XCTest
@testable import CaptureSync

final class CaptureUploadPayloadTests: XCTestCase {

    // MARK: - Reference Fixture

    private let referenceFixture = """
    {
      "capture_id": "550e8400-e29b-41d4-a716-446655440000",
      "captured_at": "2026-04-24T18:30:15.123Z",
      "device": {
        "model": "iPhone 15 Pro",
        "os_version": "17.5.1",
        "app_version": "v5-build-26"
      },
      "captured_by": {
        "user_id": "user-abc-123",
        "user_name": "Test Nurse"
      },
      "notes": "Room 302, left heel ulcer",
      "segmentation": {
        "segmenter": "coreml.boundaryseg.v1.2",
        "model_version": "1.2",
        "model_sha256": "0a5b7bb951f5cb47dcc37b81e3fc352643dfe8f2df433d17f25bc4b2b5658a44",
        "confidence": 0.94,
        "mask_coverage_pct": 4.8,
        "fallback_triggered": false,
        "fallback_reason": null,
        "quality_gate_result": "accept"
      },
      "measurements": {
        "length_cm": 4.2,
        "width_cm": 2.8,
        "area_cm2": 9.1,
        "perimeter_cm": 11.4,
        "depth_cm": null
      },
      "lidar_metadata": {
        "capture_distance_cm": 29.3,
        "lidar_confidence_pct": 87,
        "frame_count": 12
      },
      "artifacts": {
        "rgb_image_base64": "dGVzdC1yZ2I=",
        "mask_image_base64": "dGVzdC1tYXNr",
        "overlay_image_base64": "dGVzdC1vdmVybGF5"
      }
    }
    """

    // MARK: - Test: All Required Keys Present

    func testPayloadContainsAllRequiredTopLevelKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let requiredKeys = [
            "capture_id", "captured_at", "device", "captured_by",
            "notes", "segmentation", "measurements", "lidar_metadata", "artifacts"
        ]

        for key in requiredKeys {
            XCTAssertNotNil(json[key], "Missing required top-level key: \(key)")
        }
    }

    // MARK: - Test: Device Object Keys

    func testDeviceObjectKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let device = json["device"] as! [String: Any]

        XCTAssertNotNil(device["model"])
        XCTAssertNotNil(device["os_version"])
        XCTAssertNotNil(device["app_version"])
        XCTAssertEqual(device.count, 3, "Device should have exactly 3 keys")
    }

    // MARK: - Test: Captured By Object Keys

    func testCapturedByObjectKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let capturedBy = json["captured_by"] as! [String: Any]

        XCTAssertEqual(capturedBy["user_id"] as? String, "user-abc-123")
        XCTAssertEqual(capturedBy["user_name"] as? String, "Test Nurse")
        XCTAssertEqual(capturedBy.count, 2)
    }

    // MARK: - Test: Segmentation Object Keys

    func testSegmentationObjectKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let seg = json["segmentation"] as! [String: Any]

        let requiredKeys = [
            "segmenter", "model_version", "model_sha256", "confidence",
            "mask_coverage_pct", "fallback_triggered", "fallback_reason",
            "quality_gate_result"
        ]

        for key in requiredKeys {
            XCTAssertTrue(seg.keys.contains(key), "Missing segmentation key: \(key)")
        }

        XCTAssertEqual(seg["segmenter"] as? String, "coreml.boundaryseg.v1.2")
        XCTAssertEqual(seg["model_sha256"] as? String,
                       "0a5b7bb951f5cb47dcc37b81e3fc352643dfe8f2df433d17f25bc4b2b5658a44")
        XCTAssertEqual(seg["fallback_triggered"] as? Bool, false)
    }

    // MARK: - Test: Measurements Object Keys and Nullability

    func testMeasurementsObjectKeysWithNullDepth() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let measurements = json["measurements"] as! [String: Any]

        XCTAssertEqual(measurements["length_cm"] as? Double, 4.2)
        XCTAssertEqual(measurements["width_cm"] as? Double, 2.8)
        XCTAssertEqual(measurements["area_cm2"] as? Double, 9.1)
        XCTAssertEqual(measurements["perimeter_cm"] as? Double, 11.4)
        XCTAssertTrue(measurements.keys.contains("depth_cm"), "depth_cm key must be present even when null")
        XCTAssertTrue(measurements["depth_cm"] is NSNull, "depth_cm should be null")
    }

    // MARK: - Test: LiDAR Metadata Object Keys

    func testLidarMetadataObjectKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let lidar = json["lidar_metadata"] as! [String: Any]

        XCTAssertEqual(lidar["capture_distance_cm"] as? Double, 29.3)
        XCTAssertEqual(lidar["lidar_confidence_pct"] as? Int, 87)
        XCTAssertEqual(lidar["frame_count"] as? Int, 12)
        XCTAssertEqual(lidar.count, 3)
    }

    // MARK: - Test: Artifacts Object Keys

    func testArtifactsObjectKeys() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let artifacts = json["artifacts"] as! [String: Any]

        XCTAssertNotNil(artifacts["rgb_image_base64"])
        XCTAssertNotNil(artifacts["mask_image_base64"])
        XCTAssertNotNil(artifacts["overlay_image_base64"])
        XCTAssertEqual(artifacts.count, 3)
    }

    // MARK: - Test: capture_id is Lowercase UUID

    func testCaptureIdIsLowercaseUUID() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let captureId = json["capture_id"] as! String

        XCTAssertEqual(captureId, captureId.lowercased(), "capture_id must be lowercase")
        XCTAssertNotNil(UUID(uuidString: captureId), "capture_id must be valid UUID")
    }

    // MARK: - Test: captured_at is ISO8601 with Fractional Seconds

    func testCapturedAtFormatIncludesMilliseconds() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let capturedAt = json["captured_at"] as! String

        let regex = try NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z$"#)
        let range = NSRange(capturedAt.startIndex..., in: capturedAt)
        XCTAssertNotNil(
            regex.firstMatch(in: capturedAt, range: range),
            "captured_at must be ISO8601 with fractional seconds: got \(capturedAt)"
        )
    }

    // MARK: - Test: Notes Truncated to 2000 Characters

    func testNotesTruncatedTo2000Characters() throws {
        let longNotes = String(repeating: "a", count: 3000)
        let payload = CaptureUploadPayload(
            captureId: UUID(),
            capturedAt: Date(),
            device: DevicePayload(model: "Test", osVersion: "17.0", appVersion: "v5-build-1"),
            capturedBy: CapturedByPayload(userId: "u", userName: "n"),
            notes: longNotes,
            segmentation: makeTestSegmentation(),
            measurements: makeTestMeasurements(),
            lidarMetadata: makeTestLidar(),
            artifacts: ArtifactsPayload(rgbImageBase64: "", maskImageBase64: "", overlayImageBase64: "")
        )

        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let notes = json["notes"] as! String
        XCTAssertEqual(notes.count, 2000)
    }

    // MARK: - Test: Snapshot Against Reference Fixture

    func testPayloadMatchesReferenceFixtureStructure() throws {
        let referenceData = referenceFixture.data(using: .utf8)!
        let referenceJSON = try JSONSerialization.jsonObject(with: referenceData) as! [String: Any]

        let payload = makeTestPayload()
        let payloadData = try JSONEncoder().encode(payload)
        let payloadJSON = try JSONSerialization.jsonObject(with: payloadData) as! [String: Any]

        assertSameKeyStructure(reference: referenceJSON, actual: payloadJSON, path: "root")
    }

    // MARK: - Test: Round-Trip Encode/Decode

    func testPayloadRoundTrip() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CaptureUploadPayload.self, from: data)

        XCTAssertEqual(decoded.captureId, payload.captureId)
        XCTAssertEqual(decoded.notes, payload.notes)
        XCTAssertEqual(decoded.segmentation.segmenter, payload.segmentation.segmenter)
        XCTAssertEqual(decoded.measurements.lengthCm, payload.measurements.lengthCm)
        XCTAssertEqual(decoded.lidarMetadata.frameCount, payload.lidarMetadata.frameCount)
    }

    // MARK: - Test: Fallback Reason Null When Not Triggered

    func testFallbackReasonNullWhenNotTriggered() throws {
        let payload = makeTestPayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let seg = json["segmentation"] as! [String: Any]

        XCTAssertTrue(seg.keys.contains("fallback_reason"), "fallback_reason key must be present")
        XCTAssertTrue(seg["fallback_reason"] is NSNull, "fallback_reason should be null when not triggered")
    }

    // MARK: - Helpers

    private func makeTestPayload() -> CaptureUploadPayload {
        CaptureUploadPayload(
            captureId: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            capturedAt: Date(timeIntervalSince1970: 1_782_339_015.123),
            device: DevicePayload(model: "iPhone 15 Pro", osVersion: "17.5.1", appVersion: "v5-build-26"),
            capturedBy: CapturedByPayload(userId: "user-abc-123", userName: "Test Nurse"),
            notes: "Room 302, left heel ulcer",
            segmentation: makeTestSegmentation(),
            measurements: makeTestMeasurements(),
            lidarMetadata: makeTestLidar(),
            artifacts: ArtifactsPayload(
                rgbImageBase64: "dGVzdC1yZ2I=",
                maskImageBase64: "dGVzdC1tYXNr",
                overlayImageBase64: "dGVzdC1vdmVybGF5"
            )
        )
    }

    private func makeTestSegmentation() -> SegmentationPayload {
        SegmentationPayload(
            confidence: 0.94,
            maskCoveragePct: 4.8
        )
    }

    private func makeTestMeasurements() -> MeasurementsPayload {
        MeasurementsPayload(
            lengthCm: 4.2,
            widthCm: 2.8,
            areaCm2: 9.1,
            perimeterCm: 11.4,
            depthCm: nil
        )
    }

    private func makeTestLidar() -> LiDARMetadataPayload {
        LiDARMetadataPayload(
            captureDistanceCm: 29.3,
            lidarConfidencePct: 87,
            frameCount: 12
        )
    }

    private func assertSameKeyStructure(reference: [String: Any], actual: [String: Any], path: String) {
        for key in reference.keys {
            XCTAssertTrue(actual.keys.contains(key), "Missing key at \(path).\(key)")

            if let refDict = reference[key] as? [String: Any],
               let actDict = actual[key] as? [String: Any] {
                assertSameKeyStructure(reference: refDict, actual: actDict, path: "\(path).\(key)")
            }
        }

        for key in actual.keys {
            XCTAssertTrue(reference.keys.contains(key), "Extra unexpected key at \(path).\(key)")
        }
    }
}
