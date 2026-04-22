import ARKit

// MARK: - Confidence Map Summary

/// Summary of depth confidence across the current frame.
/// Used by the SwiftUI heatmap overlay to render green/yellow/red zones.
public struct ConfidenceMapSummary: Sendable {
    /// Fraction of pixels at each confidence level (0=low, 1=medium, 2=high)
    public let highFraction: Float
    public let mediumFraction: Float
    public let lowFraction: Float

    /// Overall confidence score (0...1)
    public var overallScore: Float {
        highFraction * 1.0 + mediumFraction * 0.5
    }

    /// Downsampled grid of confidence levels for efficient SwiftUI rendering.
    /// Nil if not requested or unavailable.
    public let downsampledGrid: [[UInt8]]?
    public let gridWidth: Int
    public let gridHeight: Int

    public init(
        highFraction: Float,
        mediumFraction: Float,
        lowFraction: Float,
        downsampledGrid: [[UInt8]]? = nil,
        gridWidth: Int = 0,
        gridHeight: Int = 0
    ) {
        self.highFraction = highFraction
        self.mediumFraction = mediumFraction
        self.lowFraction = lowFraction
        self.downsampledGrid = downsampledGrid
        self.gridWidth = gridWidth
        self.gridHeight = gridHeight
    }

    #if !targetEnvironment(simulator)
    /// Initialize from an ARDepthData's confidence map.
    /// Extracts fractions and downsamples to a ~40×30 grid.
    public init(from sceneDepth: ARDepthData) {
        guard let confidenceMap = sceneDepth.confidenceMap else {
            self.init(highFraction: 0, mediumFraction: 0, lowFraction: 0)
            return
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)

        guard let base = CVPixelBufferGetBaseAddress(confidenceMap) else {
            self.init(highFraction: 0, mediumFraction: 0, lowFraction: 0)
            return
        }

        // Count confidence levels
        var highCount: Float = 0
        var medCount: Float = 0
        var lowCount: Float = 0
        let total = Float(width * height)

        for row in 0..<height {
            let rowPtr = base.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                switch rowPtr[col] {
                case 2: highCount += 1
                case 1: medCount += 1
                default: lowCount += 1
                }
            }
        }

        // Downsample to ~40×30 grid
        let targetW = min(40, width)
        let targetH = min(30, height)
        let stepX = max(1, width / targetW)
        let stepY = max(1, height / targetH)

        var grid = [[UInt8]]()
        grid.reserveCapacity(targetH)
        for row in stride(from: 0, to: height, by: stepY) {
            var gridRow = [UInt8]()
            gridRow.reserveCapacity(targetW)
            let rowPtr = base.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for col in stride(from: 0, to: width, by: stepX) {
                gridRow.append(rowPtr[col])
            }
            grid.append(gridRow)
        }

        self.init(
            highFraction: total > 0 ? highCount / total : 0,
            mediumFraction: total > 0 ? medCount / total : 0,
            lowFraction: total > 0 ? lowCount / total : 0,
            downsampledGrid: grid,
            gridWidth: grid.first?.count ?? 0,
            gridHeight: grid.count
        )
    }
    #endif
}
