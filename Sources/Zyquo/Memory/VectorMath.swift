import Accelerate
import Foundation

// MARK: - VectorMath

/// Pure Swift vector operations backed by the Accelerate framework (vDSP).
///
/// Provides fast cosine similarity, dot product, normalization, and other
/// vector arithmetic for the embedding pipeline.
///
/// Reference: CLAUDE.md V2 Phase 3 - Embeddings & Local Vector Memory
public enum VectorMath {

    /// Compute the cosine similarity between two vectors.
    ///
    /// Returns `dot(a, b) / (norm(a) * norm(b))`.
    /// Returns 0 if either vector has zero norm.
    ///
    /// - Parameters:
    ///   - a: First vector.
    ///   - b: Second vector (must have the same length as `a`).
    /// - Returns: Cosine similarity in the range [-1, 1].
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "Vectors must have equal dimensions")
        guard !a.isEmpty else { return 0 }

        let dot = dotProduct(a, b)
        let normA = norm(a)
        let normB = norm(b)

        guard normA > 0 && normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    /// Compute the dot product of two vectors using vDSP.
    ///
    /// - Parameters:
    ///   - a: First vector.
    ///   - b: Second vector (must have the same length as `a`).
    /// - Returns: The scalar dot product.
    public static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "Vectors must have equal dimensions")
        guard !a.isEmpty else { return 0 }

        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    /// Compute the L2 (Euclidean) norm of a vector using vDSP.
    ///
    /// - Parameter v: The input vector.
    /// - Returns: The L2 norm.
    public static func norm(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }

        var result: Float = 0
        vDSP_svesq(v, 1, &result, vDSP_Length(v.count))
        return sqrtf(result)
    }

    /// Normalize a vector to unit length.
    ///
    /// Returns a zero vector if the input has zero norm.
    ///
    /// - Parameter v: The input vector.
    /// - Returns: A unit-length vector in the same direction.
    public static func normalize(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return [] }

        let n = norm(v)
        guard n > 0 else { return [Float](repeating: 0, count: v.count) }

        return scale(v, by: 1.0 / n)
    }

    /// Element-wise addition of two vectors using vDSP.
    ///
    /// - Parameters:
    ///   - a: First vector.
    ///   - b: Second vector (must have the same length as `a`).
    /// - Returns: Element-wise sum.
    public static func add(_ a: [Float], _ b: [Float]) -> [Float] {
        precondition(a.count == b.count, "Vectors must have equal dimensions")
        guard !a.isEmpty else { return [] }

        var result = [Float](repeating: 0, count: a.count)
        vDSP_vadd(a, 1, b, 1, &result, 1, vDSP_Length(a.count))
        return result
    }

    /// Scale a vector by a scalar using vDSP.
    ///
    /// - Parameters:
    ///   - v: The input vector.
    ///   - scalar: The scaling factor.
    /// - Returns: The scaled vector.
    public static func scale(_ v: [Float], by scalar: Float) -> [Float] {
        guard !v.isEmpty else { return [] }

        var s = scalar
        var result = [Float](repeating: 0, count: v.count)
        vDSP_vsmul(v, 1, &s, &result, 1, vDSP_Length(v.count))
        return result
    }
}
