import Foundation
import simd

// MARK: - SIMD3<Float> Extensions

extension SIMD3 where Scalar == Float {

    /// Euclidean distance to another point
    public func distance(to other: SIMD3<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Cross product with another vector
    public func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(self, other)
    }

    /// Dot product with another vector
    public func dot(_ other: SIMD3<Float>) -> Float {
        simd_dot(self, other)
    }

    /// Length / magnitude of the vector
    public var magnitude: Float {
        simd_length(self)
    }

    /// Unit vector in the same direction
    public var normalized: SIMD3<Float> {
        simd_normalize(self)
    }

    /// Convert meters to centimeters
    public var toCentimeters: SIMD3<Float> {
        self * 100.0
    }

    /// Convert meters to millimeters
    public var toMillimeters: SIMD3<Float> {
        self * 1000.0
    }
}

// MARK: - SIMD2<Float> Extensions

extension SIMD2 where Scalar == Float {

    /// Euclidean distance to another 2D point
    public func distance(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }

    /// Length / magnitude
    public var magnitude: Float {
        simd_length(self)
    }

    /// Unit vector
    public var normalized: SIMD2<Float> {
        simd_normalize(self)
    }

    /// 2D cross product (returns scalar: z-component of the 3D cross product)
    public func cross2D(_ other: SIMD2<Float>) -> Float {
        x * other.y - y * other.x
    }
}

// MARK: - simd_float4x4 Extensions

extension simd_float4x4 {

    /// Extract the 3D translation component
    public var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Extract the upper-left 3×3 rotation/scale matrix
    public var upperLeft3x3: simd_float3x3 {
        simd_float3x3(
            SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z),
            SIMD3<Float>(columns.1.x, columns.1.y, columns.1.z),
            SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
        )
    }

    /// Transform a 3D point by this matrix (applies translation)
    public func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let p4 = self * SIMD4<Float>(point.x, point.y, point.z, 1.0)
        return SIMD3<Float>(p4.x, p4.y, p4.z)
    }

    /// Transform a 3D direction by this matrix (ignores translation)
    public func transformDirection(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let d4 = self * SIMD4<Float>(direction.x, direction.y, direction.z, 0.0)
        return SIMD3<Float>(d4.x, d4.y, d4.z)
    }
}
