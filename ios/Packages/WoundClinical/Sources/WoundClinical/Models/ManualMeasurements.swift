import Foundation

public struct ManualMeasurements: Codable, Sendable {
    public var lengthCm: Double?
    public var widthCm: Double?
    public var depthCm: Double?
    public var source: ManualMeasurementSource

    public init(
        lengthCm: Double? = nil,
        widthCm: Double? = nil,
        depthCm: Double? = nil,
        source: ManualMeasurementSource = .nurseEntered
    ) {
        self.lengthCm = lengthCm
        self.widthCm = widthCm
        self.depthCm = depthCm
        self.source = source
    }
}

public enum ManualMeasurementSource: String, Codable, Sendable {
    case nurseEntered
    case rulerPhoto
    case lidarPartial
}
