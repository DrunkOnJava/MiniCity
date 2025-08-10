//
//  MathExtensions.swift
//  MiniCity
//
//  Math helper functions for Metal rendering

import simd
import Foundation
import Metal

// MARK: - Matrix Transforms

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    
    return float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * nearZ, 0)
    ))
}

func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
    let z = normalize(eye - target)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    
    return float4x4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    ))
}

func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
    return float4x4(columns: (
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    
    return float4x4(columns: (
        SIMD4<Float>(ct + x * x * ci, x * y * ci - z * st, x * z * ci + y * st, 0),
        SIMD4<Float>(y * x * ci + z * st, ct + y * y * ci, y * z * ci - x * st, 0),
        SIMD4<Float>(z * x * ci - y * st, z * y * ci + x * st, ct + z * z * ci, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

func matrix_ortho_right_hand(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
    let width = right - left
    let height = top - bottom
    let depth = farZ - nearZ
    
    return float4x4(columns: (
        SIMD4<Float>(2 / width, 0, 0, 0),
        SIMD4<Float>(0, 2 / height, 0, 0),
        SIMD4<Float>(0, 0, -2 / depth, 0),
        SIMD4<Float>(-(right + left) / width, -(top + bottom) / height, -(farZ + nearZ) / depth, 1)
    ))
}

// MARK: - Extensions

extension float4x4 {
    func upperLeft3x3() -> float3x3 {
        return float3x3(columns: (
            SIMD3<Float>(self.columns.0.x, self.columns.0.y, self.columns.0.z),
            SIMD3<Float>(self.columns.1.x, self.columns.1.y, self.columns.1.z),
            SIMD3<Float>(self.columns.2.x, self.columns.2.y, self.columns.2.z)
        ))
    }
}

extension SIMD3 where Scalar == Float {
    static let one = SIMD3<Float>(1, 1, 1)
    static let zero = SIMD3<Float>(0, 0, 0)
}

// Additional helpers for common tasks
func degreesToRadians(_ degrees: Float) -> Float {
    return degrees * .pi / 180.0
}

// Matrix identity helpers
func matrix3x3_identity() -> float3x3 {
    return float3x3(diagonal: SIMD3<Float>(1, 1, 1))
}