//
//  GroundRenderer.swift
//  MiniCity
//
//  Robust ground plane rendering with checkerboard pattern

import Foundation
import Metal
import simd

class GroundRenderer {
    let device: MTLDevice
    
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0
    private var pipelineState: MTLRenderPipelineState?
    
    init(device: MTLDevice) {
        self.device = device
        setupPipeline()
        createGroundMesh()
    }
    
    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create default library")
            return
        }
        
        let vertexFunction = library.makeFunction(name: "checkerboardVertexShader")
        let fragmentFunction = library.makeFunction(name: "checkerboardFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "CheckerboardGroundPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        // Configure for opaque rendering
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create ground pipeline state: \(error)")
        }
    }
    
    private func createGroundMesh() {
        let gridSize = 100
        let cellSize: Float = 1.0
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        // Create a grid of quads for the ground
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = Float(col - gridSize/2) * cellSize
                let z = Float(row - gridSize/2) * cellSize
                
                // Determine if this is a brown or green square
                let isBrown = (row + col) % 2 == 0
                let color = isBrown ? 
                    SIMD3<Float>(0.4, 0.3, 0.2) :  // Brown dirt
                    SIMD3<Float>(0.2, 0.5, 0.15)   // Green grass
                
                // Add vertices for this quad (position + color + grid coords)
                let baseIndex = vertices.count / 8
                
                // Bottom-left
                vertices.append(contentsOf: [
                    x, 0.0, z,
                    color.x, color.y, color.z,
                    Float(col), Float(row)
                ])
                
                // Bottom-right
                vertices.append(contentsOf: [
                    x + cellSize, 0.0, z,
                    color.x, color.y, color.z,
                    Float(col + 1), Float(row)
                ])
                
                // Top-right
                vertices.append(contentsOf: [
                    x + cellSize, 0.0, z + cellSize,
                    color.x, color.y, color.z,
                    Float(col + 1), Float(row + 1)
                ])
                
                // Top-left
                vertices.append(contentsOf: [
                    x, 0.0, z + cellSize,
                    color.x, color.y, color.z,
                    Float(col), Float(row + 1)
                ])
                
                // Add indices for two triangles
                let vertexIndex = UInt16(baseIndex)
                indices.append(contentsOf: [
                    vertexIndex, vertexIndex + 1, vertexIndex + 2,
                    vertexIndex, vertexIndex + 2, vertexIndex + 3
                ])
            }
        }
        
        indexCount = indices.count
        
        // Create Metal buffers
        vertexBuffer = device.makeBuffer(bytes: vertices,
                                        length: vertices.count * MemoryLayout<Float>.size,
                                        options: [])
        vertexBuffer?.label = "GroundVertexBuffer"
        
        indexBuffer = device.makeBuffer(bytes: indices,
                                       length: indices.count * MemoryLayout<UInt16>.size,
                                       options: [])
        indexBuffer?.label = "GroundIndexBuffer"
        
        print("Ground mesh created: \(gridSize)x\(gridSize) grid, \(indexCount/6) quads")
    }
    
    func draw(in renderEncoder: MTLRenderCommandEncoder, uniforms: MTLBuffer, offset: Int) {
        guard let pipeline = pipelineState,
              let vertexBuf = vertexBuffer,
              let indexBuf = indexBuffer else {
            print("Ground renderer not properly initialized")
            return
        }
        
        renderEncoder.pushDebugGroup("Draw Checkerboard Ground")
        renderEncoder.setRenderPipelineState(pipeline)
        renderEncoder.setVertexBuffer(vertexBuf, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniforms, offset: offset, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentBuffer(uniforms, offset: offset, index: BufferIndex.uniforms.rawValue)
        
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                           indexCount: indexCount,
                                           indexType: .uint16,
                                           indexBuffer: indexBuf,
                                           indexBufferOffset: 0)
        renderEncoder.popDebugGroup()
    }
}