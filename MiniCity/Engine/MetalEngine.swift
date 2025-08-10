//
//  MetalEngine.swift
//  MiniCity
//
//  Core Metal rendering engine for city simulation
//  Utilizes Metal 3/4 features including instanced rendering, compute shaders, and tessellation

import Metal
import MetalKit
import simd
import GameplayKit

// MARK: - Engine Configuration
struct EngineConfiguration {
    var maxBuildings: Int = 10000
    var maxVehicles: Int = 1000
    var maxTrees: Int = 5000
    var shadowMapSize: Int = 2048
    var enableTessellation: Bool = true
    var enableInstancing: Bool = true
    var enableCompute: Bool = true
}

// MARK: - Main Metal Engine
class MetalEngine: NSObject {
    
    // Core Metal objects
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Configuration
    private var config: EngineConfiguration
    
    // Render pipelines
    private var terrainPipeline: MTLRenderPipelineState!
    private var buildingPipeline: MTLRenderPipelineState!
    private var instancedBuildingPipeline: MTLRenderPipelineState!
    private var roadPipeline: MTLRenderPipelineState!
    private var vegetationPipeline: MTLRenderPipelineState!
    private var shadowPipeline: MTLRenderPipelineState!
    private var waterPipeline: MTLRenderPipelineState!
    
    // Compute pipelines
    // Traffic is now handled by GameplayKit instead of compute shaders
    // private var trafficSimulationPipeline: MTLComputePipelineState!
    private var economySimulationPipeline: MTLComputePipelineState!
    private var growthSimulationPipeline: MTLComputePipelineState!
    
    // Depth stencil states
    private var depthStencilState: MTLDepthStencilState!
    private var shadowDepthStencilState: MTLDepthStencilState!
    
    // Textures
    private var shadowMap: MTLTexture!
    private var terrainHeightMap: MTLTexture!
    private var terrainNormalMap: MTLTexture!
    
    // Buffers
    private var uniformBuffer: MTLBuffer!
    private var instanceBuffer: MTLBuffer!
    private var terrainVertexBuffer: MTLBuffer!
    private var terrainIndexBuffer: MTLBuffer!
    private var buildingMeshBuffer: MTLBuffer!
    private var roadMeshBuffer: MTLBuffer!
    
    // Buffer pools for dynamic objects
    private var buildingInstancePool: BufferPool!
    private var vehicleInstancePool: BufferPool!
    private var treeInstancePool: BufferPool!
    
    // GameplayKit integration
    private var entities: [GKEntity] = []
    private var componentSystems: [GKComponentSystem<GKComponent>] = []
    
    // Scene data
    private var camera: CameraData
    private var sunLight: DirectionalLight
    private var buildings: [BuildingInstance] = []
    private var roads: [RoadSegment] = []
    private var trees: [TreeInstance] = []
    
    // Timing
    private var lastUpdateTime: TimeInterval = 0
    
    init(device: MTLDevice, config: EngineConfiguration = EngineConfiguration()) throws {
        self.device = device
        self.config = config
        
        guard let queue = device.makeCommandQueue() else {
            throw EngineError.initialization("Failed to create command queue")
        }
        self.commandQueue = queue
        commandQueue.label = "MiniCity.CommandQueue"
        
        guard let lib = device.makeDefaultLibrary() else {
            throw EngineError.initialization("Failed to create default library")
        }
        self.library = lib
        
        // Initialize camera and lighting with better defaults
        self.camera = CameraData(
            position: SIMD3<Float>(100, 100, 100),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0),
            fov: 60.0,
            aspectRatio: 1.77,
            nearPlane: 0.1,
            farPlane: 1000.0
        )
        self.sunLight = DirectionalLight()
        
        super.init()
        
        try setupRenderPipelines()
        try setupComputePipelines()
        setupDepthStencilStates()
        try setupTextures()
        try setupBuffers()
        setupGameplayKit()
    }
    
    // MARK: - Pipeline Setup
    
    private func setupRenderPipelines() throws {
        // Terrain pipeline with tessellation support
        terrainPipeline = try createTerrainPipeline()
        
        // Building pipeline with instancing
        buildingPipeline = try createBuildingPipeline()
        instancedBuildingPipeline = try createInstancedBuildingPipeline()
        
        // Road pipeline
        roadPipeline = try createRoadPipeline()
        
        // Vegetation pipeline with instancing
        vegetationPipeline = try createVegetationPipeline()
        
        // Shadow map pipeline
        shadowPipeline = try createShadowPipeline()
        
        // Water pipeline with reflections
        waterPipeline = try createWaterPipeline()
    }
    
    private func createTerrainPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Terrain Pipeline"
        
        // Check if running in simulator
        #if targetEnvironment(simulator)
        // Use standard shaders in simulator
        descriptor.vertexFunction = library.makeFunction(name: "terrainVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "terrainFragment")
        #else
        // Use optimized shaders on device
        if config.enableTessellation && device.supportsFamily(.apple4) {
            // Tessellation support for devices (to be implemented)
            descriptor.vertexFunction = library.makeFunction(name: "terrainVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "terrainFragment")
        } else {
            descriptor.vertexFunction = library.makeFunction(name: "terrainVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "terrainFragment")
        }
        #endif
        
        // Configure vertex descriptor for terrain
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        // Configure for HDR rendering
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = false
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createInstancedBuildingPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Instanced Building Pipeline"
        
        descriptor.vertexFunction = library.makeFunction(name: "buildingVertexInstanced")
        descriptor.fragmentFunction = library.makeFunction(name: "buildingFragmentPBR")
        
        // Vertex layout for building mesh
        let vertexDescriptor = MTLVertexDescriptor()
        
        // Per-vertex data
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        // Per-instance data - matrix must be split into 4 float4 attributes
        // Transform matrix columns (4x float4)
        for i in 0..<4 {
            vertexDescriptor.attributes[3 + i].format = .float4
            vertexDescriptor.attributes[3 + i].offset = i * 16
            vertexDescriptor.attributes[3 + i].bufferIndex = 1
        }
        
        vertexDescriptor.attributes[7].format = .float4 // color tint (after 4 matrix columns)
        vertexDescriptor.attributes[7].offset = 64
        vertexDescriptor.attributes[7].bufferIndex = 1
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        vertexDescriptor.layouts[1].stride = 80
        vertexDescriptor.layouts[1].stepFunction = .perInstance
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        // Configure render targets
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createBuildingPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Building Pipeline"
        // Use non-instanced shader for individual building draws
        descriptor.vertexFunction = library.makeFunction(name: "buildingVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "buildingFragmentPBR")
        
        // Add vertex descriptor for building mesh
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createRoadPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Road Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "roadVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "roadFragment")
        
        // Add vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createVegetationPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Vegetation Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "vegetationVertexInstanced")
        descriptor.fragmentFunction = library.makeFunction(name: "vegetationFragment")
        
        // Add vertex descriptor (same as building for instanced rendering)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createShadowPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Shadow Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "shadowVertex")
        descriptor.depthAttachmentPixelFormat = .depth32Float
        
        // Add minimal vertex descriptor for shadow pass
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position only
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 12 // Just position
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createWaterPipeline() throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Water Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "waterVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "waterFragment")
        
        // Add vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3 // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3 // normal
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2 // texcoord
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = 32
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // MARK: - Compute Pipelines
    
    private func setupComputePipelines() throws {
        if config.enableCompute {
            // Traffic is now handled by GameplayKit, not compute shaders
            // trafficSimulationPipeline = try createComputePipeline(function: "updateTraffic")
            // economySimulationPipeline = try createComputePipeline(function: "economySimulation") // TODO: Add shader
            growthSimulationPipeline = try createComputePipeline(function: "cityGrowthSimulation")
        }
    }
    
    private func createComputePipeline(function: String) throws -> MTLComputePipelineState {
        guard let computeFunction = library.makeFunction(name: function) else {
            throw EngineError.shader("Compute function \(function) not found")
        }
        return try device.makeComputePipelineState(function: computeFunction)
    }
    
    // MARK: - State Setup
    
    private func setupDepthStencilStates() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)
        
        let shadowDescriptor = MTLDepthStencilDescriptor()
        shadowDescriptor.depthCompareFunction = .less
        shadowDescriptor.isDepthWriteEnabled = true
        shadowDepthStencilState = device.makeDepthStencilState(descriptor: shadowDescriptor)
    }
    
    // MARK: - Resource Setup
    
    private func setupTextures() throws {
        // Shadow map
        let shadowDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: config.shadowMapSize,
            height: config.shadowMapSize,
            mipmapped: false
        )
        shadowDescriptor.usage = [.renderTarget, .shaderRead]
        shadowDescriptor.storageMode = .private
        shadowMap = device.makeTexture(descriptor: shadowDescriptor)
        
        // Terrain height map
        let terrainDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: 512,
            height: 512,
            mipmapped: true
        )
        terrainDescriptor.usage = [.shaderRead, .shaderWrite]
        terrainHeightMap = device.makeTexture(descriptor: terrainDescriptor)
        terrainNormalMap = device.makeTexture(descriptor: terrainDescriptor)
    }
    
    private func createCubeMesh(device: MTLDevice, size: Float) -> MTLBuffer? {
        let s = size / 2.0
        let vertices: [Float] = [
            // Front face
            -s, -s,  s,   s, -s,  s,   s,  s,  s,
            -s, -s,  s,   s,  s,  s,  -s,  s,  s,
            // Back face
            -s, -s, -s,  -s,  s, -s,   s,  s, -s,
            -s, -s, -s,   s,  s, -s,   s, -s, -s,
            // Top face
            -s,  s,  s,   s,  s,  s,   s,  s, -s,
            -s,  s,  s,   s,  s, -s,  -s,  s, -s,
            // Bottom face
            -s, -s,  s,  -s, -s, -s,   s, -s, -s,
            -s, -s,  s,   s, -s, -s,   s, -s,  s,
            // Right face
             s, -s,  s,   s, -s, -s,   s,  s, -s,
             s, -s,  s,   s,  s, -s,   s,  s,  s,
            // Left face
            -s, -s, -s,  -s, -s,  s,  -s,  s,  s,
            -s, -s, -s,  -s,  s,  s,  -s,  s, -s
        ]
        
        return device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }
    
    private func setupBuffers() throws {
        // Uniform buffer for frame constants (triple buffered)
        let uniformSize = MemoryLayout<FrameUniforms>.stride
        uniformBuffer = device.makeBuffer(length: uniformSize * 3, options: .storageModeShared)
        uniformBuffer?.label = "MiniCity.UniformBuffer"
        
        // Instance buffers with triple buffering
        let maxInstances = max(config.maxBuildings, config.maxVehicles, config.maxTrees)
        let instanceSize = MemoryLayout<InstanceData>.stride * maxInstances
        instanceBuffer = device.makeBuffer(length: instanceSize * 3, options: .storageModeShared)
        instanceBuffer?.label = "MiniCity.InstanceBuffer"
        
        // Create buffer pools
        buildingInstancePool = BufferPool(device: device, elementSize: MemoryLayout<BuildingInstance>.stride, capacity: config.maxBuildings)
        vehicleInstancePool = BufferPool(device: device, elementSize: MemoryLayout<VehicleInstance>.stride, capacity: config.maxVehicles)
        treeInstancePool = BufferPool(device: device, elementSize: MemoryLayout<TreeInstance>.stride, capacity: config.maxTrees)
        
        // Generate terrain mesh
        generateTerrainMesh()
        
        // Generate building mesh
        generateBuildingMesh()
        
        // Generate road mesh
        generateRoadMesh()
    }
    
    private func generateRoadMesh() {
        // Create a simple quad for road segments
        let vertices: [Float] = [
            // Position      Normal      TexCoord
            -1, 0,  1,      0, 1, 0,    0, 0,
             1, 0,  1,      0, 1, 0,    1, 0,
             1, 0, -1,      0, 1, 0,    1, 1,
            
            -1, 0,  1,      0, 1, 0,    0, 0,
             1, 0, -1,      0, 1, 0,    1, 1,
            -1, 0, -1,      0, 1, 0,    0, 1,
        ]
        
        roadMeshBuffer = device.makeBuffer(bytes: vertices,
                                          length: vertices.count * MemoryLayout<Float>.stride,
                                          options: [])
        roadMeshBuffer?.label = "MiniCity.RoadMesh"
    }
    
    private func generateBuildingMesh() {
        // Simple cube vertices with triangles (36 vertices for 12 triangles)
        var vertices: [Float] = []
        
        // Front face (2 triangles)
        vertices += [
            -1, -1,  1,  0,  0,  1, 0, 0,
             1, -1,  1,  0,  0,  1, 1, 0,
             1,  1,  1,  0,  0,  1, 1, 1,
            
            -1, -1,  1,  0,  0,  1, 0, 0,
             1,  1,  1,  0,  0,  1, 1, 1,
            -1,  1,  1,  0,  0,  1, 0, 1,
        ]
        
        // Back face
        vertices += [
             1, -1, -1,  0,  0, -1, 0, 0,
            -1, -1, -1,  0,  0, -1, 1, 0,
            -1,  1, -1,  0,  0, -1, 1, 1,
            
             1, -1, -1,  0,  0, -1, 0, 0,
            -1,  1, -1,  0,  0, -1, 1, 1,
             1,  1, -1,  0,  0, -1, 0, 1,
        ]
        
        // Top face  
        vertices += [
            -1,  1,  1,  0,  1,  0, 0, 0,
             1,  1,  1,  0,  1,  0, 1, 0,
             1,  1, -1,  0,  1,  0, 1, 1,
            
            -1,  1,  1,  0,  1,  0, 0, 0,
             1,  1, -1,  0,  1,  0, 1, 1,
            -1,  1, -1,  0,  1,  0, 0, 1,
        ]
        
        // Bottom face
        vertices += [
            -1, -1, -1,  0, -1,  0, 0, 0,
             1, -1, -1,  0, -1,  0, 1, 0,
             1, -1,  1,  0, -1,  0, 1, 1,
            
            -1, -1, -1,  0, -1,  0, 0, 0,
             1, -1,  1,  0, -1,  0, 1, 1,
            -1, -1,  1,  0, -1,  0, 0, 1,
        ]
        
        // Right face
        vertices += [
             1, -1,  1,  1,  0,  0, 0, 0,
             1, -1, -1,  1,  0,  0, 1, 0,
             1,  1, -1,  1,  0,  0, 1, 1,
            
             1, -1,  1,  1,  0,  0, 0, 0,
             1,  1, -1,  1,  0,  0, 1, 1,
             1,  1,  1,  1,  0,  0, 0, 1,
        ]
        
        // Left face
        vertices += [
            -1, -1, -1, -1,  0,  0, 0, 0,
            -1, -1,  1, -1,  0,  0, 1, 0,
            -1,  1,  1, -1,  0,  0, 1, 1,
            
            -1, -1, -1, -1,  0,  0, 0, 0,
            -1,  1,  1, -1,  0,  0, 1, 1,
            -1,  1, -1, -1,  0,  0, 0, 1,
        ]
        
        buildingMeshBuffer = device.makeBuffer(bytes: vertices, 
                                               length: vertices.count * MemoryLayout<Float>.stride,
                                               options: [])
        buildingMeshBuffer?.label = "MiniCity.BuildingMesh"
    }
    
    private func generateTerrainMesh() {
        // Generate a grid mesh for terrain - make it much larger
        let gridSize = 300  // Triple the size
        let cellSize: Float = 2.0
        var vertices: [TerrainVertex] = []
        var indices: [UInt32] = []
        
        for z in 0...gridSize {
            for x in 0...gridSize {
                let posX = Float(x - gridSize/2) * cellSize
                let posZ = Float(z - gridSize/2) * cellSize
                let posY: Float = 0 // Will be displaced by height map
                
                let u = Float(x) / Float(gridSize)
                let v = Float(z) / Float(gridSize)
                
                vertices.append(TerrainVertex(
                    position: SIMD3<Float>(posX, posY, posZ),
                    normal: SIMD3<Float>(0, 1, 0),
                    texcoord: SIMD2<Float>(u, v)
                ))
            }
        }
        
        // Generate indices for triangle strip
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let topLeft = UInt32(z * (gridSize + 1) + x)
                let topRight = topLeft + 1
                let bottomLeft = topLeft + UInt32(gridSize + 1)
                let bottomRight = bottomLeft + 1
                
                indices.append(contentsOf: [
                    topLeft, bottomLeft, topRight,
                    topRight, bottomLeft, bottomRight
                ])
            }
        }
        
        terrainVertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<TerrainVertex>.stride, options: [])
        terrainIndexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride, options: [])
    }
    
    // MARK: - GameplayKit Integration
    
    private func setupGameplayKit() {
        // Create component systems - keeping empty for now as they're in CityGameController
        componentSystems = []
    }
    
    // MARK: - Rendering
    
    func render(in view: MTKView, camera: CameraController, trafficSimulation: GameplayKitTrafficSimulation? = nil) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        
        commandBuffer.label = "MiniCity.Frame.\(CACurrentMediaTime())"
        
        // Add debug signpost for profiling
        commandBuffer.pushDebugGroup("MiniCity Render")
        
        // Update uniforms
        updateUniforms(camera: camera)
        
        // Shadow pass (if enabled)
        if sunLight.castsShadows {
            renderShadowPass(commandBuffer: commandBuffer)
        }
        
        // Main render pass
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        // Properly configure depth attachment
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.storeAction = .store
        
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.label = "Main Pass"
            renderEncoder.setDepthStencilState(depthStencilState)
            
            // Render terrain
            renderTerrain(encoder: renderEncoder)
            
            // Render roads
            renderRoads(encoder: renderEncoder)
            
            // Render buildings (instanced)
            renderBuildings(encoder: renderEncoder)
            
            // Render traffic vehicles
            if let traffic = trafficSimulation {
                renderTraffic(encoder: renderEncoder, trafficSimulation: traffic)
            }
            
            // Render vegetation
            renderVegetation(encoder: renderEncoder)
            
            // Render water
            renderWater(encoder: renderEncoder)
            
            renderEncoder.endEncoding()
        }
        
        // Compute pass for simulations
        if config.enableCompute {
            runSimulations(commandBuffer: commandBuffer)
        }
        
        commandBuffer.popDebugGroup()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func updateUniforms(camera: CameraController) {
        let viewMatrix = camera.getViewMatrix()
        let projectionMatrix = matrix_perspective_right_hand(
            fovyRadians: Float.pi / 3.0,
            aspectRatio: Float(1.77), // Will be updated from view
            nearZ: 1.0,  // Increased near plane for better depth precision
            farZ: 500.0  // Reduced far plane for better depth precision
        )
        
        var uniforms = FrameUniforms(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewProjectionMatrix: projectionMatrix * viewMatrix,
            lightViewProjectionMatrix: calculateLightMatrix(),
            cameraPosition: camera.position,
            time: Float(CACurrentMediaTime()),
            sunDirection: sunLight.direction,
            sunColor: sunLight.color,
            sunIntensity: sunLight.intensity
        )
        
        // Update uniform buffer
        let bufferPointer = uniformBuffer.contents().bindMemory(to: FrameUniforms.self, capacity: 1)
        bufferPointer.pointee = uniforms
    }
    
    private func calculateLightMatrix() -> float4x4 {
        // Calculate light view-projection matrix for shadows
        let lightView = matrix_look_at_right_hand(
            eye: sunLight.direction * -100,
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        let lightProjection = matrix_ortho_right_hand(
            left: -50, right: 50,
            bottom: -50, top: 50,
            nearZ: 1, farZ: 200
        )
        return lightProjection * lightView
    }
    
    private func renderShadowPass(commandBuffer: MTLCommandBuffer) {
        // TODO: Implement shadow pass
    }
    
    private func renderTerrain(encoder: MTLRenderCommandEncoder) {
        encoder.pushDebugGroup("Terrain")
        encoder.setRenderPipelineState(terrainPipeline)
        encoder.setVertexBuffer(terrainVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexTexture(terrainHeightMap, index: 0)
        encoder.setFragmentTexture(terrainHeightMap, index: 0) // Grass texture placeholder
        encoder.setFragmentTexture(terrainNormalMap, index: 1) // Rock texture placeholder
        encoder.setFragmentTexture(shadowMap, index: 2)
        
        if let indexBuffer = terrainIndexBuffer {
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6 * 300 * 300, // Grid size squared * 6 indices per quad
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }
        encoder.popDebugGroup()
    }
    
    private func renderTraffic(encoder: MTLRenderCommandEncoder, trafficSimulation: GameplayKitTrafficSimulation) {
        encoder.pushDebugGroup("Traffic")
        
        // Get vehicle data from simulation
        let vehicles = trafficSimulation.getVehicles()
        guard !vehicles.isEmpty else {
            encoder.popDebugGroup()
            return
        }
        
        // Use building pipeline for now (vehicles as small boxes)
        encoder.setRenderPipelineState(buildingPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Simple cube for vehicle representation
        // Create simple cube mesh for vehicles
        let vehicleMesh = createCubeMesh(device: device, size: 2.0)
        encoder.setVertexBuffer(vehicleMesh, offset: 0, index: 0)
        
        // Render each vehicle
        for vehicle in vehicles {
            // Different scales based on vehicle type
            let scale: SIMD3<Float>
            switch vehicle.type {
            case .car:
                scale = SIMD3<Float>(2.0, 1.5, 3.0)
            case .bus:
                scale = SIMD3<Float>(2.5, 2.5, 6.0)
            case .truck:
                scale = SIMD3<Float>(2.5, 2.0, 5.0)
            case .emergency:
                scale = SIMD3<Float>(2.0, 1.5, 3.5)
            }
            
            var instanceData = InstanceData(
                modelMatrix: matrix4x4_translation(vehicle.position.x, vehicle.position.y, vehicle.position.z) *
                            matrix4x4_scale(scale.x, scale.y, scale.z),
                normalMatrix: matrix3x3_identity(),
                color: vehicle.color,
                metallic: 0.7,
                roughness: 0.3
            )
            
            encoder.setVertexBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        }
        
        encoder.popDebugGroup()
    }
    
    private func renderRoads(encoder: MTLRenderCommandEncoder) {
        encoder.pushDebugGroup("Roads")
        encoder.setRenderPipelineState(roadPipeline)
        encoder.setVertexBuffer(roadMeshBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Use polygon offset to prevent z-fighting
        encoder.setDepthBias(0.001, slopeScale: 1.0, clamp: 0.001)
        
        // Generate road grid
        let roadWidth: Float = 10
        let blockSize: Float = 30
        let gridSpacing = Int(blockSize + roadWidth)
        
        // Draw horizontal roads
        for z in stride(from: -200, through: 200, by: gridSpacing) {
            for x in stride(from: -200, through: 200, by: gridSpacing) {
                // Horizontal road segment - slightly above ground at 0.02
                var transform = matrix4x4_translation(Float(x) + blockSize/2, 0.02, Float(z) - roadWidth/2)
                transform = transform * matrix4x4_scale(blockSize/2, 1, roadWidth/2)
                
                var instanceData = InstanceData(
                    modelMatrix: transform,
                    normalMatrix: transform.upperLeft3x3(),
                    color: SIMD4<Float>(0.15, 0.15, 0.17, 1.0), // Much darker, almost black
                    metallic: 0.05,
                    roughness: 0.95
                )
                
                encoder.setVertexBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
                encoder.setFragmentBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
        
        // Draw vertical roads
        for x in stride(from: -200, through: 200, by: gridSpacing) {
            for z in stride(from: -200, through: 200, by: gridSpacing) {
                // Vertical road segment - slightly above ground at 0.02
                var transform = matrix4x4_translation(Float(x) - roadWidth/2, 0.02, Float(z) + blockSize/2)
                transform = transform * matrix4x4_scale(roadWidth/2, 1, blockSize/2)
                
                var instanceData = InstanceData(
                    modelMatrix: transform,
                    normalMatrix: transform.upperLeft3x3(),
                    color: SIMD4<Float>(0.15, 0.15, 0.17, 1.0), // Much darker, almost black
                    metallic: 0.05,
                    roughness: 0.95
                )
                
                encoder.setVertexBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
                encoder.setFragmentBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }
        
        encoder.popDebugGroup()
    }
    
    private func renderBuildings(encoder: MTLRenderCommandEncoder) {
        // Create city blocks with roads between them
        if buildings.isEmpty {
            let blockSize: Float = 30  // Size of each city block
            let roadWidth: Float = 10  // Width of roads
            let buildingSpacing: Float = 8  // Space between buildings in a block
            
            // Create a grid of city blocks
            for blockX in stride(from: -90, to: 90, by: Int(blockSize + roadWidth)) {
                for blockZ in stride(from: -90, to: 90, by: Int(blockSize + roadWidth)) {
                    // Place 3x3 buildings per block
                    for buildingX in 0..<3 {
                        for buildingZ in 0..<3 {
                            let x = Float(blockX) + Float(buildingX) * buildingSpacing
                            let z = Float(blockZ) + Float(buildingZ) * buildingSpacing
                            let height = Float.random(in: 10...45)
                            let types: [BuildingType] = [.residential, .commercial, .office, .industrial]
                            let type = types.randomElement()!
                            addBuilding(at: SIMD3<Float>(x, 0, z), 
                                       type: type, 
                                       height: height)
                        }
                    }
                }
            }
        }
        
        guard !buildings.isEmpty else { return }
        
        encoder.pushDebugGroup("Buildings")
        encoder.setRenderPipelineState(buildingPipeline)
        encoder.setVertexBuffer(buildingMeshBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Draw each building individually for now
        for building in buildings {
            var instanceData = InstanceData(
                modelMatrix: building.transform,
                normalMatrix: building.transform.upperLeft3x3(),
                color: building.color,
                metallic: 0.1,
                roughness: 0.7
            )
            
            encoder.setVertexBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
            encoder.setFragmentBytes(&instanceData, length: MemoryLayout<InstanceData>.size, index: 2)
            
            // Draw cube (6 faces * 2 triangles * 3 vertices)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        }
        
        encoder.popDebugGroup()
    }
    
    private func renderVegetation(encoder: MTLRenderCommandEncoder) {
        guard !trees.isEmpty else { return }
        
        encoder.setRenderPipelineState(vegetationPipeline)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        
        // TODO: Render trees
    }
    
    private func renderWater(encoder: MTLRenderCommandEncoder) {
        // TODO: Render water surfaces if any
    }
    
    private func runSimulations(commandBuffer: MTLCommandBuffer) {
        // TODO: Run compute shaders for traffic, economy, etc.
    }
}

// MARK: - Data Structures

struct FrameUniforms {
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
    var viewProjectionMatrix: float4x4
    var lightViewProjectionMatrix: float4x4
    var cameraPosition: SIMD3<Float>
    var time: Float
    var sunDirection: SIMD3<Float>
    var sunColor: SIMD3<Float>
    var sunIntensity: Float
}

struct InstanceData {
    var modelMatrix: float4x4
    var normalMatrix: float3x3
    var color: SIMD4<Float>
    var metallic: Float
    var roughness: Float
}

struct TerrainVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var texcoord: SIMD2<Float>
}

struct BuildingInstance {
    var transform: float4x4
    var color: SIMD4<Float>
    var buildingType: Int32
    var height: Float
}

struct VehicleInstance {
    var transform: float4x4
    var color: SIMD4<Float>
    var speed: Float
    var destination: SIMD3<Float>
}

struct TreeInstance {
    var position: SIMD3<Float>
    var scale: Float
    var rotation: Float
    var treeType: Int32
}

// RoadSegment moved to GameTypes.swift

struct CameraData {
    var position: SIMD3<Float> = SIMD3<Float>(50, 50, 50)
    var target: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    var fov: Float = 60.0
    var aspectRatio: Float = 1.0
    var nearPlane: Float = 0.1
    var farPlane: Float = 1000.0
}

struct DirectionalLight {
    var direction: SIMD3<Float> = normalize(SIMD3<Float>(-1, -1, -1))
    var color: SIMD3<Float> = SIMD3<Float>(1, 0.95, 0.8)
    var intensity: Float = 1.0
    var castsShadows: Bool = true
}

// MARK: - Buffer Pool

class BufferPool {
    private let device: MTLDevice
    private let elementSize: Int
    private let capacity: Int
    private var buffers: [MTLBuffer] = []
    private var currentIndex = 0
    
    init(device: MTLDevice, elementSize: Int, capacity: Int) {
        self.device = device
        self.elementSize = elementSize
        self.capacity = capacity
        
        // Create triple-buffered pools
        for _ in 0..<3 {
            if let buffer = device.makeBuffer(length: elementSize * capacity, options: .storageModeShared) {
                buffers.append(buffer)
            }
        }
    }
    
    func nextBuffer() -> MTLBuffer? {
        guard !buffers.isEmpty else { return nil }
        let buffer = buffers[currentIndex]
        currentIndex = (currentIndex + 1) % buffers.count
        return buffer
    }
}

// BuildingComponent, RoadComponent, VehicleComponent, EconomyComponent, and BuildingType
// are now defined in CityGameController.swift to avoid duplicates

// MARK: - Error Types

// MARK: - Public API

extension MetalEngine {
    func addBuilding(at position: SIMD3<Float>, type: BuildingType, height: Float) {
        let transform = matrix4x4_translation(position.x, height/2, position.z) *
                       matrix4x4_scale(5, height/2, 5)
        
        let colorMap: [BuildingType: SIMD4<Float>] = [
            .residential: SIMD4<Float>(0.7, 0.7, 0.8, 1.0),
            .commercial: SIMD4<Float>(0.6, 0.7, 0.9, 1.0),
            .industrial: SIMD4<Float>(0.8, 0.7, 0.6, 1.0),
            .office: SIMD4<Float>(0.7, 0.8, 0.9, 1.0),
            .service: SIMD4<Float>(0.6, 0.8, 0.7, 1.0)
        ]
        
        buildings.append(BuildingInstance(
            transform: transform,
            color: colorMap[type] ?? SIMD4<Float>(0.7, 0.7, 0.7, 1.0),
            buildingType: Int32(type.rawValue),
            height: height
        ))
    }
}

enum EngineError: Error {
    case initialization(String)
    case shader(String)
    case resource(String)
}