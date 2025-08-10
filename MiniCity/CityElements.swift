//
//  CityElements.swift
//  MiniCity
//
//  3D buildings and roads for the city

import Foundation
import Metal
import simd

struct Building {
    let position: SIMD3<Float>
    let size: SIMD3<Float>  // width, height, depth
    let color: SIMD3<Float>
}

struct Road {
    let start: SIMD2<Float>
    let end: SIMD2<Float>
    let width: Float
    let hasMedian: Bool
}

class CityBuilder {
    let device: MTLDevice
    
    // Building buffers
    var buildingVertexBuffer: MTLBuffer?
    var buildingIndexBuffer: MTLBuffer?
    var buildingIndexCount: Int = 0
    
    // Road buffers
    var roadVertexBuffer: MTLBuffer?
    var roadIndexBuffer: MTLBuffer?
    var roadIndexCount: Int = 0
    
    // Park generator
    var parkGenerator: ParkGenerator?
    
    init(device: MTLDevice) {
        self.device = device
        self.parkGenerator = ParkGenerator(device: device)
    }
    
    func generateCity() {
        // Generate buildings with more variety
        var buildings: [Building] = []
        var emptyBlocks: [(x: Float, z: Float, isEmpty: Bool)] = []
        var streetTreePositions: [(x: Float, z: Float)] = []
        
        // Create a more realistic city layout
        let blockSize: Float = 20.0
        let roadWidth: Float = 5.0
        let sidewalkWidth: Float = 1.5
        let gridCount = 6
        
        // City center has taller buildings
        for row in 0..<gridCount {
            for col in 0..<gridCount {
                let x = Float(col - gridCount/2) * (blockSize + roadWidth)
                let z = Float(row - gridCount/2) * (blockSize + roadWidth)
                
                // Distance from center affects building height
                let distFromCenter = sqrt(x * x + z * z)
                let heightMultiplier = 1.0 + max(0, 1.0 - distFromCenter / 100.0)
                
                // Create 2-4 buildings per block
                let buildingsPerBlock = Int.random(in: 2...4)
                
                // Sometimes leave space for a park (more parks further from center)
                let parkChance = distFromCenter > 50 ? 0...8 : 0...12
                let isParkBlock = Int.random(in: parkChance) == 0
                if isParkBlock {
                    emptyBlocks.append((x: x, z: z, isEmpty: true))
                    continue  // Skip this block for parks
                }
                
                for _ in 0..<buildingsPerBlock {
                    let bx = x + Float.random(in: -blockSize/3...blockSize/3)
                    let bz = z + Float.random(in: -blockSize/3...blockSize/3)
                    
                    // Vary building types based on location
                    let buildingType: BuildingType
                    if distFromCenter < 30 {
                        buildingType = Bool.random() ? .office : .commercial
                    } else if distFromCenter < 60 {
                        buildingType = [.commercial, .office, .residential].randomElement()!
                    } else {
                        buildingType = Bool.random() ? .residential : .commercial
                    }
                    
                    let heightRange = buildingType.heightRange
                    let height = Float.random(in: heightRange) * Float(heightMultiplier)
                    let width = Float.random(in: 4...10)
                    let depth = Float.random(in: 4...10)
                    
                    // Use building type colors with variation
                    let baseColor = buildingType.baseColor
                    let variation = Float.random(in: 0.9...1.1)
                    let color = baseColor * variation
                    
                    buildings.append(Building(
                        position: SIMD3<Float>(bx, 0, bz),
                        size: SIMD3<Float>(width, height, depth),
                        color: color
                    ))
                }
                
                // Add street tree positions along this block
                if Int.random(in: 0...2) == 0 {
                    streetTreePositions.append((x: x - blockSize/2 - roadWidth/2, z: z))
                    streetTreePositions.append((x: x + blockSize/2 + roadWidth/2, z: z))
                    streetTreePositions.append((x: x, z: z - blockSize/2 - roadWidth/2))
                    streetTreePositions.append((x: x, z: z + blockSize/2 + roadWidth/2))
                }
            }
        }
        
        createBuildingMesh(buildings: buildings)
        createEnhancedRoadMesh(gridCount: gridCount, blockSize: blockSize, roadWidth: roadWidth, sidewalkWidth: sidewalkWidth)
        
        // Generate parks and trees
        if let parkGen = parkGenerator {
            let parks = parkGen.generateParks(cityBlocks: emptyBlocks)
            let trees = parkGen.generateTrees(parks: parks, streetPositions: streetTreePositions)
            
            parkGen.createParkMesh(parks: parks)
            parkGen.createTreeMesh(trees: trees)
        }
    }
    
    func createBuildingMesh(buildings: [Building]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        for building in buildings {
            let pos = building.position
            let size = building.size
            let color = building.color
            
            // Create a simple box for each building
            let halfWidth = size.x / 2
            let halfDepth = size.z / 2
            let height = size.y
            
            // 8 vertices for a box (position + color)
            let boxVertices: [Float] = [
                // Bottom face
                pos.x - halfWidth, pos.y, pos.z - halfDepth, color.x, color.y, color.z,
                pos.x + halfWidth, pos.y, pos.z - halfDepth, color.x, color.y, color.z,
                pos.x + halfWidth, pos.y, pos.z + halfDepth, color.x, color.y, color.z,
                pos.x - halfWidth, pos.y, pos.z + halfDepth, color.x, color.y, color.z,
                // Top face (slightly brighter)
                pos.x - halfWidth, pos.y + height, pos.z - halfDepth, color.x * 1.2, color.y * 1.2, color.z * 1.2,
                pos.x + halfWidth, pos.y + height, pos.z - halfDepth, color.x * 1.2, color.y * 1.2, color.z * 1.2,
                pos.x + halfWidth, pos.y + height, pos.z + halfDepth, color.x * 1.2, color.y * 1.2, color.z * 1.2,
                pos.x - halfWidth, pos.y + height, pos.z + halfDepth, color.x * 1.2, color.y * 1.2, color.z * 1.2,
            ]
            
            vertices.append(contentsOf: boxVertices)
            
            // Indices for the box (12 triangles, 2 per face)
            let boxIndices: [UInt16] = [
                // Bottom face
                currentVertex + 0, currentVertex + 2, currentVertex + 1,
                currentVertex + 0, currentVertex + 3, currentVertex + 2,
                // Top face
                currentVertex + 4, currentVertex + 5, currentVertex + 6,
                currentVertex + 4, currentVertex + 6, currentVertex + 7,
                // Front face
                currentVertex + 0, currentVertex + 1, currentVertex + 5,
                currentVertex + 0, currentVertex + 5, currentVertex + 4,
                // Back face
                currentVertex + 2, currentVertex + 3, currentVertex + 7,
                currentVertex + 2, currentVertex + 7, currentVertex + 6,
                // Left face
                currentVertex + 0, currentVertex + 4, currentVertex + 7,
                currentVertex + 0, currentVertex + 7, currentVertex + 3,
                // Right face
                currentVertex + 1, currentVertex + 2, currentVertex + 6,
                currentVertex + 1, currentVertex + 6, currentVertex + 5,
            ]
            
            indices.append(contentsOf: boxIndices)
            currentVertex += 8
        }
        
        buildingIndexCount = indices.count
        
        if !vertices.isEmpty {
            buildingVertexBuffer = device.makeBuffer(bytes: vertices,
                                                    length: vertices.count * MemoryLayout<Float>.size,
                                                    options: [])
            buildingIndexBuffer = device.makeBuffer(bytes: indices,
                                                   length: indices.count * MemoryLayout<UInt16>.size,
                                                   options: [])
        }
    }
    
    func createEnhancedRoadMesh(gridCount: Int, blockSize: Float, roadWidth: Float, sidewalkWidth: Float) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        let roadColor = SIMD3<Float>(0.25, 0.25, 0.28)  // Dark asphalt
        let lineColor = SIMD3<Float>(0.9, 0.85, 0.3)   // Yellow lane lines
        let sidewalkColor = SIMD3<Float>(0.65, 0.65, 0.68)  // Concrete gray
        let crosswalkColor = SIMD3<Float>(0.95, 0.95, 0.95)  // White stripes
        
        let extent = Float(gridCount) * (blockSize + roadWidth) / 2.0
        
        // Create roads with sidewalks
        for i in 0...gridCount {
            let offset = Float(i - gridCount/2) * (blockSize + roadWidth) - roadWidth/2
            
            // North-South roads
            // Main road
            vertices.append(contentsOf: [
                offset - roadWidth/2, 0.02, -extent, roadColor.x, roadColor.y, roadColor.z,
                offset + roadWidth/2, 0.02, -extent, roadColor.x, roadColor.y, roadColor.z,
                offset + roadWidth/2, 0.02, extent, roadColor.x, roadColor.y, roadColor.z,
                offset - roadWidth/2, 0.02, extent, roadColor.x, roadColor.y, roadColor.z,
            ])
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Sidewalks on both sides
            vertices.append(contentsOf: [
                offset - roadWidth/2 - sidewalkWidth, 0.05, -extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset - roadWidth/2, 0.05, -extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset - roadWidth/2, 0.05, extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset - roadWidth/2 - sidewalkWidth, 0.05, extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
            ])
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            vertices.append(contentsOf: [
                offset + roadWidth/2, 0.05, -extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset + roadWidth/2 + sidewalkWidth, 0.05, -extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset + roadWidth/2 + sidewalkWidth, 0.05, extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
                offset + roadWidth/2, 0.05, extent, sidewalkColor.x, sidewalkColor.y, sidewalkColor.z,
            ])
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Dashed center line
            let dashLength: Float = 3.0
            let gapLength: Float = 2.0
            var currentPos: Float = -extent
            while currentPos < extent {
                vertices.append(contentsOf: [
                    offset - 0.1, 0.03, currentPos, lineColor.x, lineColor.y, lineColor.z,
                    offset + 0.1, 0.03, currentPos, lineColor.x, lineColor.y, lineColor.z,
                    offset + 0.1, 0.03, min(currentPos + dashLength, extent), lineColor.x, lineColor.y, lineColor.z,
                    offset - 0.1, 0.03, min(currentPos + dashLength, extent), lineColor.x, lineColor.y, lineColor.z,
                ])
                indices.append(contentsOf: [
                    currentVertex, currentVertex + 1, currentVertex + 2,
                    currentVertex, currentVertex + 2, currentVertex + 3
                ])
                currentVertex += 4
                currentPos += dashLength + gapLength
            }
            
            // East-West roads (similar structure)
            // Main road
            vertices.append(contentsOf: [
                -extent, 0.02, offset - roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                extent, 0.02, offset - roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                extent, 0.02, offset + roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                -extent, 0.02, offset + roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
            ])
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Add crosswalks at intersections
            if i < gridCount {
                for j in 0...gridCount {
                    let crossOffset = Float(j - gridCount/2) * (blockSize + roadWidth) - roadWidth/2
                    
                    // Crosswalk stripes
                    for stripe in 0..<5 {
                        let stripeOffset = Float(stripe) * 1.5 - 3.0
                        vertices.append(contentsOf: [
                            crossOffset - roadWidth/2, 0.04, offset + stripeOffset - 0.3, crosswalkColor.x, crosswalkColor.y, crosswalkColor.z,
                            crossOffset + roadWidth/2, 0.04, offset + stripeOffset - 0.3, crosswalkColor.x, crosswalkColor.y, crosswalkColor.z,
                            crossOffset + roadWidth/2, 0.04, offset + stripeOffset + 0.3, crosswalkColor.x, crosswalkColor.y, crosswalkColor.z,
                            crossOffset - roadWidth/2, 0.04, offset + stripeOffset + 0.3, crosswalkColor.x, crosswalkColor.y, crosswalkColor.z,
                        ])
                        indices.append(contentsOf: [
                            currentVertex, currentVertex + 1, currentVertex + 2,
                            currentVertex, currentVertex + 2, currentVertex + 3
                        ])
                        currentVertex += 4
                    }
                }
            }
        }
        
        roadIndexCount = indices.count
        
        if !vertices.isEmpty {
            roadVertexBuffer = device.makeBuffer(bytes: vertices,
                                                length: vertices.count * MemoryLayout<Float>.size,
                                                options: [])
            roadIndexBuffer = device.makeBuffer(bytes: indices,
                                               length: indices.count * MemoryLayout<UInt16>.size,
                                               options: [])
        }
    }
    
    func createRoadMesh(gridCount: Int, blockSize: Float, roadWidth: Float) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        let roadColor = SIMD3<Float>(0.3, 0.3, 0.3)  // Dark gray
        let lineColor = SIMD3<Float>(1.0, 1.0, 0.0)  // Yellow for lines
        let extent = Float(gridCount) * (blockSize + roadWidth) / 2.0
        
        // Create main avenues (north-south and east-west)
        for i in 0...gridCount {
            let offset = Float(i - gridCount/2) * (blockSize + roadWidth) - roadWidth/2
            
            // North-South avenue
            vertices.append(contentsOf: [
                offset - roadWidth/2, 0.02, -extent, roadColor.x, roadColor.y, roadColor.z,
                offset + roadWidth/2, 0.02, -extent, roadColor.x, roadColor.y, roadColor.z,
                offset + roadWidth/2, 0.02, extent, roadColor.x, roadColor.y, roadColor.z,
                offset - roadWidth/2, 0.02, extent, roadColor.x, roadColor.y, roadColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Add median line
            vertices.append(contentsOf: [
                offset - 0.05, 0.03, -extent, lineColor.x, lineColor.y, lineColor.z,
                offset + 0.05, 0.03, -extent, lineColor.x, lineColor.y, lineColor.z,
                offset + 0.05, 0.03, extent, lineColor.x, lineColor.y, lineColor.z,
                offset - 0.05, 0.03, extent, lineColor.x, lineColor.y, lineColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // East-West avenue
            vertices.append(contentsOf: [
                -extent, 0.02, offset - roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                extent, 0.02, offset - roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                extent, 0.02, offset + roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
                -extent, 0.02, offset + roadWidth/2, roadColor.x, roadColor.y, roadColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Add median line
            vertices.append(contentsOf: [
                -extent, 0.03, offset - 0.05, lineColor.x, lineColor.y, lineColor.z,
                extent, 0.03, offset - 0.05, lineColor.x, lineColor.y, lineColor.z,
                extent, 0.03, offset + 0.05, lineColor.x, lineColor.y, lineColor.z,
                -extent, 0.03, offset + 0.05, lineColor.x, lineColor.y, lineColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
        }
        
        roadIndexCount = indices.count
        
        if !vertices.isEmpty {
            roadVertexBuffer = device.makeBuffer(bytes: vertices,
                                                length: vertices.count * MemoryLayout<Float>.size,
                                                options: [])
            roadIndexBuffer = device.makeBuffer(bytes: indices,
                                               length: indices.count * MemoryLayout<UInt16>.size,
                                               options: [])
        }
    }
}