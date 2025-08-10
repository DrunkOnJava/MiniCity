//
//  Renderer.swift
//  MiniCity
//
//  Created by Griffin on 8/9/25.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

// The 256 byte aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100

let maxBuffersInFlight = 3

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var uniforms: UnsafeMutablePointer<Uniforms>
    
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var viewMatrix: matrix_float4x4 = matrix_float4x4()
    
    // Camera controller reference
    var cameraController: CameraController?
    
    // Grid properties
    let gridSize = 100
    let cellSize: Float = 1.0
    var gridVertexBuffer: MTLBuffer!
    var gridIndexBuffer: MTLBuffer!
    var gridIndexCount: Int = 0
    
    // Ground plane
    var groundVertexBuffer: MTLBuffer!
    var groundIndexBuffer: MTLBuffer!
    var groundTexture: MTLTexture!
    var groundPipelineState: MTLRenderPipelineState!
    var groundRenderer: GroundRenderer!
    
    // City elements
    var cityBuilder: CityBuilder!
    
    @MainActor
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        
        guard let buffer = self.device.makeBuffer(length:uniformBufferSize, options:[MTLResourceOptions.storageModeShared]) else { return nil }
        dynamicUniformBuffer = buffer
        
        self.dynamicUniformBuffer.label = "UniformBuffer"
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents()).bindMemory(to:Uniforms.self, capacity:1)
        
        metalKitView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                       metalKitView: metalKitView,
                                                                       mtlVertexDescriptor: mtlVertexDescriptor)
        } catch {
            print("Unable to compile render pipeline state.  Error info: \(error)")
            return nil
        }
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = MTLCompareFunction.lessEqual
        depthStateDescriptor.isDepthWriteEnabled = true
        depthStateDescriptor.label = "Depth State"
        guard let state = device.makeDepthStencilState(descriptor:depthStateDescriptor) else { return nil }
        depthState = state
        
        super.init()
        
        // Build city grid and ground
        buildCityGrid()
        buildGroundPlane()
        createGroundTexture()
        
        // Create the new ground renderer
        groundRenderer = GroundRenderer(device: device)
        
        // Create city elements
        cityBuilder = CityBuilder(device: device)
        cityBuilder.generateCity()
        
        // Build ground pipeline
        do {
            groundPipelineState = try buildGroundPipeline(device: device, metalKitView: metalKitView)
            print("Ground pipeline created successfully")
        } catch {
            print("Failed to create ground pipeline: \(error)")
            groundPipelineState = nil
        }
    }
    
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Create a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices
        
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = 12
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = 8
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    @MainActor
    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        /// Build a render state pipeline object
        
        let library = device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "gridVertexShader")
        let fragmentFunction = library?.makeFunction(name: "gridFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "RenderPipeline"
        pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = nil  // We're using vertex ID indexing
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func buildCityGrid() {
        // Create grid vertices and indices
        var vertices: [Float] = []
        var indices: [UInt16] = []
        
        // Generate grid lines
        for i in 0...gridSize {
            let pos = Float(i) * cellSize - Float(gridSize) * cellSize * 0.5
            
            // Horizontal lines (slightly raised to avoid z-fighting)
            vertices += [
                -Float(gridSize) * cellSize * 0.5, 0.01, pos,  // Start point
                0.9, 0.9, 0.9,  // Color (light gray)
                Float(gridSize) * cellSize * 0.5, 0.01, pos,   // End point
                0.9, 0.9, 0.9   // Color
            ]
            
            // Vertical lines
            vertices += [
                pos, 0.01, -Float(gridSize) * cellSize * 0.5,  // Start point
                0.9, 0.9, 0.9,  // Color
                pos, 0.01, Float(gridSize) * cellSize * 0.5,   // End point
                0.9, 0.9, 0.9   // Color
            ]
        }
        
        // Generate indices for line segments
        for i in 0..<(gridSize + 1) * 4 {
            indices.append(UInt16(i))
        }
        
        gridIndexCount = indices.count
        
        // Create buffers
        gridVertexBuffer = device.makeBuffer(bytes: vertices,
                                            length: vertices.count * MemoryLayout<Float>.size,
                                            options: [])
        gridIndexBuffer = device.makeBuffer(bytes: indices,
                                           length: indices.count * MemoryLayout<UInt16>.size,
                                           options: [])
    }
    
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset).bindMemory(to:Uniforms.self, capacity:1)
    }
    
    private func updateGameState() {
        /// Update any game state before rendering
        
        uniforms[0].projectionMatrix = projectionMatrix
        
        // Get view matrix from camera controller
        if let cameraController = cameraController {
            let viewMatrix = cameraController.getViewMatrix()
            uniforms[0].modelViewMatrix = viewMatrix
        } else {
            // Default view matrix if no camera controller
            let defaultView = matrix_look_at_right_hand(
                eye: SIMD3<Float>(50, 50, 50),
                target: SIMD3<Float>(0, 0, 0),
                up: SIMD3<Float>(0, 1, 0)
            )
            uniforms[0].modelViewMatrix = defaultView
        }
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            self.updateDynamicBufferState()
            
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            
            // Set clear color to sky blue with fog
            renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0)
            
            if let renderPassDescriptor = renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                /// Final pass rendering code here
                renderEncoder.label = "Primary Render Encoder"
                
                renderEncoder.pushDebugGroup("Draw Box")
                
                renderEncoder.setCullMode(.back)
                
                renderEncoder.setFrontFacing(.counterClockwise)
                
                renderEncoder.setRenderPipelineState(pipelineState)
                
                renderEncoder.setDepthStencilState(depthState)
                
                // Draw the new checkerboard ground first
                groundRenderer.draw(in: renderEncoder, uniforms: dynamicUniformBuffer, offset: uniformBufferOffset)
                
                // Draw roads
                if let roadVertexBuffer = cityBuilder.roadVertexBuffer,
                   let roadIndexBuffer = cityBuilder.roadIndexBuffer,
                   cityBuilder.roadIndexCount > 0 {
                    renderEncoder.setRenderPipelineState(pipelineState)
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setVertexBuffer(roadVertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                       indexCount: cityBuilder.roadIndexCount,
                                                       indexType: .uint16,
                                                       indexBuffer: roadIndexBuffer,
                                                       indexBufferOffset: 0)
                }
                
                // Draw parks
                if let parkGen = cityBuilder.parkGenerator,
                   let parkVertexBuffer = parkGen.parkVertexBuffer,
                   let parkIndexBuffer = parkGen.parkIndexBuffer,
                   parkGen.parkIndexCount > 0 {
                    renderEncoder.setRenderPipelineState(pipelineState)
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setVertexBuffer(parkVertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                       indexCount: parkGen.parkIndexCount,
                                                       indexType: .uint16,
                                                       indexBuffer: parkIndexBuffer,
                                                       indexBufferOffset: 0)
                }
                
                // Draw trees
                if let parkGen = cityBuilder.parkGenerator,
                   let treeVertexBuffer = parkGen.treeVertexBuffer,
                   let treeIndexBuffer = parkGen.treeIndexBuffer,
                   parkGen.treeIndexCount > 0 {
                    renderEncoder.setRenderPipelineState(pipelineState)
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setVertexBuffer(treeVertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                       indexCount: parkGen.treeIndexCount,
                                                       indexType: .uint16,
                                                       indexBuffer: treeIndexBuffer,
                                                       indexBufferOffset: 0)
                }
                
                // Draw buildings
                if let buildingVertexBuffer = cityBuilder.buildingVertexBuffer,
                   let buildingIndexBuffer = cityBuilder.buildingIndexBuffer,
                   cityBuilder.buildingIndexCount > 0 {
                    renderEncoder.setRenderPipelineState(pipelineState)
                    renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset:uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
                    renderEncoder.setVertexBuffer(buildingVertexBuffer, offset: 0, index: 0)
                    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                       indexCount: cityBuilder.buildingIndexCount,
                                                       indexType: .uint16,
                                                       indexBuffer: buildingIndexBuffer,
                                                       indexBufferOffset: 0)
                }
                
                // Grid lines removed - checkerboard provides visual reference
                
                renderEncoder.popDebugGroup()
                
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians(fromDegrees: 65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
    }
    
    func buildGroundPlane() {
        let halfSize = Float(gridSize) * cellSize * 0.5
        
        // Just positions for simple test
        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(-halfSize, -0.1, -halfSize),  // Bottom-left
            SIMD3<Float>( halfSize, -0.1, -halfSize),  // Bottom-right  
            SIMD3<Float>( halfSize, -0.1,  halfSize),  // Top-right
            SIMD3<Float>(-halfSize, -0.1,  halfSize)   // Top-left
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,  // First triangle
            0, 2, 3   // Second triangle
        ]
        
        groundVertexBuffer = device.makeBuffer(bytes: vertices,
                                              length: vertices.count * MemoryLayout<SIMD3<Float>>.size,
                                              options: [])
        groundIndexBuffer = device.makeBuffer(bytes: indices,
                                            length: indices.count * MemoryLayout<UInt16>.size,
                                            options: [])
        
        print("Ground buffers created - vertex: \(groundVertexBuffer != nil), index: \(groundIndexBuffer != nil)")
        print("Ground size: \(halfSize * 2) x \(halfSize * 2)")
    }
    
    func createGroundTexture() {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 512,
            height: 512,
            mipmapped: true
        )
        textureDescriptor.usage = [.shaderRead]
        
        groundTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // Create a grass-like texture procedurally
        var pixels = [UInt8](repeating: 0, count: 512 * 512 * 4)
        
        for y in 0..<512 {
            for x in 0..<512 {
                let index = (y * 512 + x) * 4
                
                // Add some noise for grass variation
                let noise = Float.random(in: 0...1)
                let baseGreen = UInt8(80 + noise * 40)  // Vary green from 80-120
                let darkFactor = UInt8(noise * 20)
                
                pixels[index] = 30 + darkFactor      // R (dark green)
                pixels[index + 1] = baseGreen        // G (main green)
                pixels[index + 2] = 20 + darkFactor  // B (slight blue tint)
                pixels[index + 3] = 255               // A (opaque)
            }
        }
        
        groundTexture.replace(region: MTLRegionMake2D(0, 0, 512, 512),
                             mipmapLevel: 0,
                             withBytes: pixels,
                             bytesPerRow: 512 * 4)
    }
    
    func buildGroundPipeline(device: MTLDevice, metalKitView: MTKView) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()
        
        // Try simple shader first
        var vertexFunction = library?.makeFunction(name: "simpleGroundVertex")
        var fragmentFunction = library?.makeFunction(name: "simpleGroundFragment")
        
        if vertexFunction == nil {
            print("ERROR: Could not find simpleGroundVertex shader")
            // Fallback to original shader
            vertexFunction = library?.makeFunction(name: "groundVertexShader")
            fragmentFunction = library?.makeFunction(name: "groundFragmentShader")
            
            if vertexFunction == nil {
                print("ERROR: Could not find groundVertexShader either")
            }
        }
        
        // Create vertex descriptor for simple vertex
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "GroundPipeline"
        pipelineDescriptor.rasterSampleCount = metalKitView.sampleCount
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}

// Matrix math functions are in MathExtensions.swift
func radians(fromDegrees degrees: Float) -> Float {
    return degrees * Float.pi / 180
}

// Matrix functions are now in MathExtensions.swift
