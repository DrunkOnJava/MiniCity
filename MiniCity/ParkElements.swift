//
//  ParkElements.swift
//  MiniCity
//
//  Parks, trees, and green spaces for the city

import Foundation
import Metal
import simd

struct Tree {
    let position: SIMD3<Float>
    let height: Float
    let canopyRadius: Float
    let type: TreeType
}

enum TreeType {
    case oak
    case pine
    case palm
    
    var trunkColor: SIMD3<Float> {
        switch self {
        case .oak: return SIMD3<Float>(0.35, 0.25, 0.15)  // Brown
        case .pine: return SIMD3<Float>(0.3, 0.2, 0.1)    // Dark brown
        case .palm: return SIMD3<Float>(0.45, 0.35, 0.25) // Light brown
        }
    }
    
    var canopyColor: SIMD3<Float> {
        switch self {
        case .oak: return SIMD3<Float>(0.2, 0.5, 0.1)     // Medium green
        case .pine: return SIMD3<Float>(0.1, 0.3, 0.05)   // Dark green
        case .palm: return SIMD3<Float>(0.3, 0.6, 0.2)    // Tropical green
        }
    }
}

struct Park {
    let center: SIMD2<Float>
    let size: SIMD2<Float>
    let hasPond: Bool
    let hasPlayground: Bool
}

class ParkGenerator {
    let device: MTLDevice
    
    var parkVertexBuffer: MTLBuffer?
    var parkIndexBuffer: MTLBuffer?
    var parkIndexCount: Int = 0
    
    var treeVertexBuffer: MTLBuffer?
    var treeIndexBuffer: MTLBuffer?
    var treeIndexCount: Int = 0
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func generateParks(cityBlocks: [(x: Float, z: Float, isEmpty: Bool)]) -> [Park] {
        var parks: [Park] = []
        
        // Create parks in empty blocks
        for block in cityBlocks where block.isEmpty {
            let park = Park(
                center: SIMD2<Float>(block.x, block.z),
                size: SIMD2<Float>(18, 18),  // Slightly smaller than block size
                hasPond: Bool.random(),
                hasPlayground: Bool.random()
            )
            parks.append(park)
        }
        
        // Add a central park
        parks.append(Park(
            center: SIMD2<Float>(0, 0),
            size: SIMD2<Float>(40, 40),
            hasPond: true,
            hasPlayground: true
        ))
        
        return parks
    }
    
    func generateTrees(parks: [Park], streetPositions: [(x: Float, z: Float)]) -> [Tree] {
        var trees: [Tree] = []
        
        // Trees in parks
        for park in parks {
            let treeCount = Int.random(in: 8...15)
            for _ in 0..<treeCount {
                let x = park.center.x + Float.random(in: -park.size.x/2...park.size.x/2)
                let z = park.center.y + Float.random(in: -park.size.y/2...park.size.y/2)
                
                // Avoid pond area if present
                if park.hasPond {
                    let pondCenter = park.center
                    let pondRadius: Float = 5.0
                    let distToPond = sqrt(pow(x - pondCenter.x, 2) + pow(z - pondCenter.y, 2))
                    if distToPond < pondRadius {
                        continue
                    }
                }
                
                trees.append(Tree(
                    position: SIMD3<Float>(x, 0, z),
                    height: Float.random(in: 8...15),
                    canopyRadius: Float.random(in: 3...5),
                    type: [.oak, .pine].randomElement()!
                ))
            }
        }
        
        // Street trees along major roads
        for position in streetPositions {
            if Int.random(in: 0...3) == 0 {  // 25% chance for street tree
                trees.append(Tree(
                    position: SIMD3<Float>(position.x, 0, position.z),
                    height: Float.random(in: 6...10),
                    canopyRadius: Float.random(in: 2...3),
                    type: .oak
                ))
            }
        }
        
        return trees
    }
    
    func createParkMesh(parks: [Park]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        let grassColor = SIMD3<Float>(0.3, 0.6, 0.2)      // Lush green
        let pathColor = SIMD3<Float>(0.75, 0.7, 0.6)      // Sandy path
        let pondColor = SIMD3<Float>(0.2, 0.4, 0.6)       // Water blue
        let playgroundColor = SIMD3<Float>(0.9, 0.6, 0.3) // Rubber orange
        
        for park in parks {
            // Main grass area
            let halfWidth = park.size.x / 2
            let halfDepth = park.size.y / 2
            
            vertices.append(contentsOf: [
                park.center.x - halfWidth, 0.01, park.center.y - halfDepth, grassColor.x, grassColor.y, grassColor.z,
                park.center.x + halfWidth, 0.01, park.center.y - halfDepth, grassColor.x, grassColor.y, grassColor.z,
                park.center.x + halfWidth, 0.01, park.center.y + halfDepth, grassColor.x, grassColor.y, grassColor.z,
                park.center.x - halfWidth, 0.01, park.center.y + halfDepth, grassColor.x, grassColor.y, grassColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Walking paths (cross pattern)
            let pathWidth: Float = 1.5
            
            // North-South path
            vertices.append(contentsOf: [
                park.center.x - pathWidth/2, 0.02, park.center.y - halfDepth, pathColor.x, pathColor.y, pathColor.z,
                park.center.x + pathWidth/2, 0.02, park.center.y - halfDepth, pathColor.x, pathColor.y, pathColor.z,
                park.center.x + pathWidth/2, 0.02, park.center.y + halfDepth, pathColor.x, pathColor.y, pathColor.z,
                park.center.x - pathWidth/2, 0.02, park.center.y + halfDepth, pathColor.x, pathColor.y, pathColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // East-West path
            vertices.append(contentsOf: [
                park.center.x - halfWidth, 0.02, park.center.y - pathWidth/2, pathColor.x, pathColor.y, pathColor.z,
                park.center.x + halfWidth, 0.02, park.center.y - pathWidth/2, pathColor.x, pathColor.y, pathColor.z,
                park.center.x + halfWidth, 0.02, park.center.y + pathWidth/2, pathColor.x, pathColor.y, pathColor.z,
                park.center.x - halfWidth, 0.02, park.center.y + pathWidth/2, pathColor.x, pathColor.y, pathColor.z,
            ])
            
            indices.append(contentsOf: [
                currentVertex, currentVertex + 1, currentVertex + 2,
                currentVertex, currentVertex + 2, currentVertex + 3
            ])
            currentVertex += 4
            
            // Pond (circular approximation with octagon)
            if park.hasPond {
                let pondRadius: Float = 5.0
                let segments = 8
                
                // Center vertex
                vertices.append(contentsOf: [
                    park.center.x, -0.5, park.center.y, pondColor.x, pondColor.y, pondColor.z
                ])
                let centerVertex = currentVertex
                currentVertex += 1
                
                // Pond vertices
                for i in 0..<segments {
                    let angle = Float(i) * (2.0 * Float.pi / Float(segments))
                    let x = park.center.x + cos(angle) * pondRadius
                    let z = park.center.y + sin(angle) * pondRadius
                    vertices.append(contentsOf: [
                        x, -0.5, z, pondColor.x, pondColor.y, pondColor.z
                    ])
                }
                
                // Create triangles for pond
                for i in 0..<segments {
                    let next = (i + 1) % segments
                    indices.append(contentsOf: [
                        centerVertex,
                        centerVertex + UInt16(i + 1),
                        centerVertex + UInt16(next + 1)
                    ])
                }
                currentVertex += UInt16(segments)
            }
            
            // Playground area
            if park.hasPlayground {
                let playgroundSize: Float = 6.0
                let playgroundX = park.center.x + park.size.x/4
                let playgroundZ = park.center.y + park.size.y/4
                
                vertices.append(contentsOf: [
                    playgroundX - playgroundSize/2, 0.02, playgroundZ - playgroundSize/2, 
                    playgroundColor.x, playgroundColor.y, playgroundColor.z,
                    playgroundX + playgroundSize/2, 0.02, playgroundZ - playgroundSize/2, 
                    playgroundColor.x, playgroundColor.y, playgroundColor.z,
                    playgroundX + playgroundSize/2, 0.02, playgroundZ + playgroundSize/2, 
                    playgroundColor.x, playgroundColor.y, playgroundColor.z,
                    playgroundX - playgroundSize/2, 0.02, playgroundZ + playgroundSize/2, 
                    playgroundColor.x, playgroundColor.y, playgroundColor.z,
                ])
                
                indices.append(contentsOf: [
                    currentVertex, currentVertex + 1, currentVertex + 2,
                    currentVertex, currentVertex + 2, currentVertex + 3
                ])
                currentVertex += 4
            }
        }
        
        parkIndexCount = indices.count
        
        if !vertices.isEmpty {
            parkVertexBuffer = device.makeBuffer(bytes: vertices,
                                                length: vertices.count * MemoryLayout<Float>.size,
                                                options: [])
            parkIndexBuffer = device.makeBuffer(bytes: indices,
                                               length: indices.count * MemoryLayout<UInt16>.size,
                                               options: [])
        }
    }
    
    func createTreeMesh(trees: [Tree]) {
        var vertices: [Float] = []
        var indices: [UInt16] = []
        var currentVertex: UInt16 = 0
        
        for tree in trees {
            let trunkColor = tree.type.trunkColor
            let canopyColor = tree.type.canopyColor
            
            // Trunk (cylinder approximation with box)
            let trunkWidth: Float = 0.5
            let trunkHeight = tree.height * 0.3
            
            vertices.append(contentsOf: [
                tree.position.x - trunkWidth/2, tree.position.y, tree.position.z - trunkWidth/2,
                trunkColor.x, trunkColor.y, trunkColor.z,
                tree.position.x + trunkWidth/2, tree.position.y, tree.position.z - trunkWidth/2,
                trunkColor.x, trunkColor.y, trunkColor.z,
                tree.position.x + trunkWidth/2, tree.position.y, tree.position.z + trunkWidth/2,
                trunkColor.x, trunkColor.y, trunkColor.z,
                tree.position.x - trunkWidth/2, tree.position.y, tree.position.z + trunkWidth/2,
                trunkColor.x, trunkColor.y, trunkColor.z,
                
                tree.position.x - trunkWidth/2, tree.position.y + trunkHeight, tree.position.z - trunkWidth/2,
                trunkColor.x * 0.8, trunkColor.y * 0.8, trunkColor.z * 0.8,
                tree.position.x + trunkWidth/2, tree.position.y + trunkHeight, tree.position.z - trunkWidth/2,
                trunkColor.x * 0.8, trunkColor.y * 0.8, trunkColor.z * 0.8,
                tree.position.x + trunkWidth/2, tree.position.y + trunkHeight, tree.position.z + trunkWidth/2,
                trunkColor.x * 0.8, trunkColor.y * 0.8, trunkColor.z * 0.8,
                tree.position.x - trunkWidth/2, tree.position.y + trunkHeight, tree.position.z + trunkWidth/2,
                trunkColor.x * 0.8, trunkColor.y * 0.8, trunkColor.z * 0.8,
            ])
            
            // Trunk indices
            indices.append(contentsOf: [
                // Sides
                currentVertex + 0, currentVertex + 1, currentVertex + 5,
                currentVertex + 0, currentVertex + 5, currentVertex + 4,
                currentVertex + 1, currentVertex + 2, currentVertex + 6,
                currentVertex + 1, currentVertex + 6, currentVertex + 5,
                currentVertex + 2, currentVertex + 3, currentVertex + 7,
                currentVertex + 2, currentVertex + 7, currentVertex + 6,
                currentVertex + 3, currentVertex + 0, currentVertex + 4,
                currentVertex + 3, currentVertex + 4, currentVertex + 7,
            ])
            currentVertex += 8
            
            // Canopy (octahedron shape for simplicity)
            let canopyY = tree.position.y + trunkHeight
            let canopyTop = canopyY + tree.height * 0.7
            
            // Canopy vertices (pyramid-like shape)
            vertices.append(contentsOf: [
                // Bottom square of canopy
                tree.position.x - tree.canopyRadius, canopyY, tree.position.z - tree.canopyRadius,
                canopyColor.x * 0.9, canopyColor.y * 0.9, canopyColor.z * 0.9,
                tree.position.x + tree.canopyRadius, canopyY, tree.position.z - tree.canopyRadius,
                canopyColor.x * 0.9, canopyColor.y * 0.9, canopyColor.z * 0.9,
                tree.position.x + tree.canopyRadius, canopyY, tree.position.z + tree.canopyRadius,
                canopyColor.x * 0.9, canopyColor.y * 0.9, canopyColor.z * 0.9,
                tree.position.x - tree.canopyRadius, canopyY, tree.position.z + tree.canopyRadius,
                canopyColor.x * 0.9, canopyColor.y * 0.9, canopyColor.z * 0.9,
                
                // Middle tier
                tree.position.x - tree.canopyRadius * 0.7, canopyY + (canopyTop - canopyY) * 0.5, 
                tree.position.z - tree.canopyRadius * 0.7,
                canopyColor.x, canopyColor.y, canopyColor.z,
                tree.position.x + tree.canopyRadius * 0.7, canopyY + (canopyTop - canopyY) * 0.5, 
                tree.position.z - tree.canopyRadius * 0.7,
                canopyColor.x, canopyColor.y, canopyColor.z,
                tree.position.x + tree.canopyRadius * 0.7, canopyY + (canopyTop - canopyY) * 0.5, 
                tree.position.z + tree.canopyRadius * 0.7,
                canopyColor.x, canopyColor.y, canopyColor.z,
                tree.position.x - tree.canopyRadius * 0.7, canopyY + (canopyTop - canopyY) * 0.5, 
                tree.position.z + tree.canopyRadius * 0.7,
                canopyColor.x, canopyColor.y, canopyColor.z,
                
                // Top point
                tree.position.x, canopyTop, tree.position.z,
                canopyColor.x * 1.1, canopyColor.y * 1.1, canopyColor.z * 1.1,
            ])
            
            // Canopy indices
            let base = currentVertex
            indices.append(contentsOf: [
                // Bottom to middle connections
                base + 0, base + 1, base + 5,
                base + 0, base + 5, base + 4,
                base + 1, base + 2, base + 6,
                base + 1, base + 6, base + 5,
                base + 2, base + 3, base + 7,
                base + 2, base + 7, base + 6,
                base + 3, base + 0, base + 4,
                base + 3, base + 4, base + 7,
                
                // Middle to top
                base + 4, base + 5, base + 8,
                base + 5, base + 6, base + 8,
                base + 6, base + 7, base + 8,
                base + 7, base + 4, base + 8,
            ])
            currentVertex += 9
        }
        
        treeIndexCount = indices.count
        
        if !vertices.isEmpty {
            treeVertexBuffer = device.makeBuffer(bytes: vertices,
                                                length: vertices.count * MemoryLayout<Float>.size,
                                                options: [])
            treeIndexBuffer = device.makeBuffer(bytes: indices,
                                               length: indices.count * MemoryLayout<UInt16>.size,
                                               options: [])
        }
    }
}