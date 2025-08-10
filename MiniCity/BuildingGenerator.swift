//
//  BuildingGenerator.swift
//  MiniCity
//
//  Advanced building generation with architectural details

import Foundation
import Metal
import simd

// BuildingType is now defined in CityGameController.swift
// Adding extensions for building-specific properties
extension BuildingType {
    var baseColor: SIMD3<Float> {
        switch self {
        case .residential:
            return SIMD3<Float>(0.9, 0.85, 0.8)  // Warm beige
        case .commercial:
            return SIMD3<Float>(0.7, 0.75, 0.8)  // Cool gray-blue
        case .office:
            return SIMD3<Float>(0.6, 0.65, 0.7)  // Steel gray
        case .industrial:
            return SIMD3<Float>(0.7, 0.7, 0.6)  // Industrial gray
        case .service:
            return SIMD3<Float>(0.5, 0.6, 0.75)  // Service blue
        }
    }
    
    var heightRange: ClosedRange<Float> {
        switch self {
        case .residential:
            return 5...15
        case .commercial:
            return 8...20
        case .office:
            return 15...35
        case .industrial:
            return 5...12
        case .service:
            return 3...8
        }
    }
}

struct DetailedBuilding {
    let position: SIMD3<Float>
    let size: SIMD3<Float>
    let type: BuildingType
    let rotation: Float
    let windowRows: Int
    let windowCols: Int
    let hasRooftop: Bool
}

class BuildingGenerator {
    let device: MTLDevice
    
    func generateDetailedBuildingMesh(buildings: [DetailedBuilding]) -> (vertices: [Float], indices: [UInt16]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        for building in buildings {
            let (buildingVerts, buildingIndices) = createDetailedBuilding(building, startVertex: currentVertex)
            vertices.append(contentsOf: buildingVerts)
            indices.append(contentsOf: buildingIndices)
            currentVertex += UInt16(buildingVerts.count / 6)  // 6 floats per vertex
        }
        
        return (vertices, indices)
    }
    
    private func createDetailedBuilding(_ building: DetailedBuilding, startVertex: UInt16) -> ([Float], [UInt16]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        let pos = building.position
        let size = building.size
        let baseColor = building.type.baseColor
        
        // Building main body
        let halfWidth = size.x / 2
        let halfDepth = size.z / 2
        let height = size.y
        
        // Main building faces with slight color variations
        // Front face
        vertices.append(contentsOf: createWallWithWindows(
            bottomLeft: SIMD3<Float>(pos.x - halfWidth, pos.y, pos.z - halfDepth),
            bottomRight: SIMD3<Float>(pos.x + halfWidth, pos.y, pos.z - halfDepth),
            height: height,
            color: baseColor * 0.95,
            windowRows: building.windowRows,
            windowCols: building.windowCols,
            isGlassBuilding: building.type == .office
        ))
        
        // Back face
        vertices.append(contentsOf: createWallWithWindows(
            bottomLeft: SIMD3<Float>(pos.x + halfWidth, pos.y, pos.z + halfDepth),
            bottomRight: SIMD3<Float>(pos.x - halfWidth, pos.y, pos.z + halfDepth),
            height: height,
            color: baseColor * 0.85,
            windowRows: building.windowRows,
            windowCols: building.windowCols,
            isGlassBuilding: building.type == .office
        ))
        
        // Left face
        vertices.append(contentsOf: createWallWithWindows(
            bottomLeft: SIMD3<Float>(pos.x - halfWidth, pos.y, pos.z + halfDepth),
            bottomRight: SIMD3<Float>(pos.x - halfWidth, pos.y, pos.z - halfDepth),
            height: height,
            color: baseColor * 0.9,
            windowRows: building.windowRows,
            windowCols: Int(building.windowCols / 2),
            isGlassBuilding: building.type == .office
        ))
        
        // Right face
        vertices.append(contentsOf: createWallWithWindows(
            bottomLeft: SIMD3<Float>(pos.x + halfWidth, pos.y, pos.z - halfDepth),
            bottomRight: SIMD3<Float>(pos.x + halfWidth, pos.y, pos.z + halfDepth),
            height: height,
            color: baseColor * 0.9,
            windowRows: building.windowRows,
            windowCols: Int(building.windowCols / 2),
            isGlassBuilding: building.type == .office
        ))
        
        // Rooftop
        if building.hasRooftop {
            vertices.append(contentsOf: createRooftop(
                position: SIMD3<Float>(pos.x, pos.y + height, pos.z),
                width: size.x,
                depth: size.z,
                type: building.type
            ))
        } else {
            // Flat roof
            let roofColor = baseColor * 0.7
            vertices.append(contentsOf: [
                pos.x - halfWidth, pos.y + height, pos.z - halfDepth, roofColor.x, roofColor.y, roofColor.z,
                pos.x + halfWidth, pos.y + height, pos.z - halfDepth, roofColor.x, roofColor.y, roofColor.z,
                pos.x + halfWidth, pos.y + height, pos.z + halfDepth, roofColor.x, roofColor.y, roofColor.z,
                pos.x - halfWidth, pos.y + height, pos.z + halfDepth, roofColor.x, roofColor.y, roofColor.z,
            ])
        }
        
        // Generate indices for all faces
        for face in 0..<5 {
            let baseIdx = startVertex + UInt16(face * 4)
            indices.append(contentsOf: [
                baseIdx, baseIdx + 1, baseIdx + 2,
                baseIdx, baseIdx + 2, baseIdx + 3
            ])
        }
        
        return (vertices, indices)
    }
    
    private func createWallWithWindows(bottomLeft: SIMD3<Float>, 
                                       bottomRight: SIMD3<Float>,
                                       height: Float,
                                       color: SIMD3<Float>,
                                       windowRows: Int,
                                       windowCols: Int,
                                       isGlassBuilding: Bool) -> [Float] {
        var vertices: [Float] = []
        
        // For glass buildings, make the entire face reflective
        let wallColor = isGlassBuilding ? SIMD3<Float>(0.6, 0.7, 0.85) : color
        
        // Create main wall
        let topLeft = SIMD3<Float>(bottomLeft.x, bottomLeft.y + height, bottomLeft.z)
        let topRight = SIMD3<Float>(bottomRight.x, bottomRight.y + height, bottomRight.z)
        
        vertices.append(contentsOf: [
            bottomLeft.x, bottomLeft.y, bottomLeft.z, wallColor.x, wallColor.y, wallColor.z,
            bottomRight.x, bottomRight.y, bottomRight.z, wallColor.x, wallColor.y, wallColor.z,
            topRight.x, topRight.y, topRight.z, wallColor.x * 1.1, wallColor.y * 1.1, wallColor.z * 1.1,
            topLeft.x, topLeft.y, topLeft.z, wallColor.x * 1.1, wallColor.y * 1.1, wallColor.z * 1.1,
        ])
        
        return vertices
    }
    
    private func createRooftop(position: SIMD3<Float>, width: Float, depth: Float, type: BuildingType) -> [Float] {
        var vertices: [Float] = []
        let roofColor = SIMD3<Float>(0.4, 0.4, 0.45)
        
        // Simple peaked roof for residential, flat with details for others
        if type == .residential {
            // Peaked roof
            let peak = SIMD3<Float>(position.x, position.y + 3, position.z)
            vertices.append(contentsOf: [
                position.x - width/2, position.y, position.z - depth/2, roofColor.x, roofColor.y, roofColor.z,
                position.x + width/2, position.y, position.z - depth/2, roofColor.x, roofColor.y, roofColor.z,
                peak.x, peak.y, peak.z, roofColor.x * 1.2, roofColor.y * 1.2, roofColor.z * 1.2,
                position.x - width/2, position.y, position.z - depth/2, roofColor.x, roofColor.y, roofColor.z,  // Dummy for quad
            ])
        } else {
            // Flat roof with HVAC unit representation
            // _ = SIMD3<Float>(0.5, 0.5, 0.55) // hvacColor unused for now
            vertices.append(contentsOf: [
                position.x - width/2, position.y, position.z - depth/2, roofColor.x, roofColor.y, roofColor.z,
                position.x + width/2, position.y, position.z - depth/2, roofColor.x, roofColor.y, roofColor.z,
                position.x + width/2, position.y, position.z + depth/2, roofColor.x, roofColor.y, roofColor.z,
                position.x - width/2, position.y, position.z + depth/2, roofColor.x, roofColor.y, roofColor.z,
            ])
        }
        
        return vertices
    }
    
    init(device: MTLDevice) {
        self.device = device
    }
}