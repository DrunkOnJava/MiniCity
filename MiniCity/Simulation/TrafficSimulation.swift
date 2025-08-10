//
//  TrafficSimulation.swift
//  MiniCity
//
//  Real-time traffic simulation using Metal compute shaders
//

import Metal
import MetalKit
import simd

struct Vehicle {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var destination: SIMD3<Float>
    var type: UInt32  // 0: car, 1: bus, 2: truck
    var speed: Float
    var color: SIMD4<Float>
}

class TrafficSimulation {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Compute pipeline
    private var trafficUpdatePipeline: MTLComputePipelineState?
    private var pathfindingPipeline: MTLComputePipelineState?
    
    // Buffers
    private var vehicleBuffer: MTLBuffer?
    private var roadNetworkBuffer: MTLBuffer?
    private var trafficLightBuffer: MTLBuffer?
    
    // Simulation parameters
    private let maxVehicles = 500
    private var vehicleCount = 0
    private var vehicles: [Vehicle] = []
    private var simulationTime: Float = 0
    private var isRunning = false
    
    // Road network
    private var roadNodes: [SIMD3<Float>] = []
    private var roadConnections: [(Int, Int)] = []
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        setupComputePipelines()
        setupBuffers()
        generateRoadNetwork()
        spawnInitialVehicles()
    }
    
    private func setupComputePipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to create Metal library")
            return
        }
        
        // Traffic update compute pipeline
        if let trafficFunction = library.makeFunction(name: "updateTraffic") {
            do {
                trafficUpdatePipeline = try device.makeComputePipelineState(function: trafficFunction)
            } catch {
                print("Failed to create traffic update pipeline: \(error)")
            }
        }
        
        // Pathfinding compute pipeline
        if let pathFunction = library.makeFunction(name: "calculatePath") {
            do {
                pathfindingPipeline = try device.makeComputePipelineState(function: pathFunction)
            } catch {
                print("Failed to create pathfinding pipeline: \(error)")
            }
        }
    }
    
    private func setupBuffers() {
        // Allocate vehicle buffer
        let vehicleSize = MemoryLayout<Vehicle>.stride * maxVehicles
        vehicleBuffer = device.makeBuffer(length: vehicleSize, options: .storageModeShared)
        
        // Initialize with empty vehicles
        vehicles = Array(repeating: Vehicle(
            position: SIMD3<Float>(0, 0, 0),
            velocity: SIMD3<Float>(0, 0, 0),
            destination: SIMD3<Float>(0, 0, 0),
            type: 0,
            speed: 0,
            color: SIMD4<Float>(0, 0, 0, 0)
        ), count: maxVehicles)
    }
    
    private func generateRoadNetwork() {
        // Create a grid-based road network
        let gridSize = 10
        let spacing: Float = 30.0
        
        // Generate road nodes
        for x in -gridSize...gridSize {
            for z in -gridSize...gridSize {
                let position = SIMD3<Float>(
                    Float(x) * spacing,
                    0.02,  // Slightly above ground
                    Float(z) * spacing
                )
                roadNodes.append(position)
            }
        }
        
        // Connect adjacent nodes
        let nodesPerRow = gridSize * 2 + 1
        for i in 0..<roadNodes.count {
            let x = i % nodesPerRow
            let z = i / nodesPerRow
            
            // Connect to right neighbor
            if x < nodesPerRow - 1 {
                roadConnections.append((i, i + 1))
            }
            
            // Connect to bottom neighbor
            if z < nodesPerRow - 1 {
                roadConnections.append((i, i + nodesPerRow))
            }
        }
    }
    
    private func spawnInitialVehicles() {
        // Spawn initial set of vehicles
        let initialCount = 50
        
        for i in 0..<initialCount {
            let startNode = Int.random(in: 0..<roadNodes.count)
            let endNode = Int.random(in: 0..<roadNodes.count)
            
            var vehicle = Vehicle(
                position: roadNodes[startNode],
                velocity: SIMD3<Float>(0, 0, 0),
                destination: roadNodes[endNode],
                type: UInt32.random(in: 0...2),
                speed: Float.random(in: 8...15),  // m/s
                color: randomVehicleColor()
            )
            
            // Offset position slightly for lane
            let laneOffset = Float.random(in: -2...2)
            vehicle.position.x += laneOffset
            
            vehicles[i] = vehicle
        }
        
        vehicleCount = initialCount
        updateVehicleBuffer()
    }
    
    private func randomVehicleColor() -> SIMD4<Float> {
        let colors: [SIMD4<Float>] = [
            SIMD4<Float>(0.8, 0.2, 0.2, 1.0),  // Red
            SIMD4<Float>(0.2, 0.4, 0.8, 1.0),  // Blue
            SIMD4<Float>(0.3, 0.7, 0.3, 1.0),  // Green
            SIMD4<Float>(0.9, 0.9, 0.9, 1.0),  // White
            SIMD4<Float>(0.2, 0.2, 0.2, 1.0),  // Black
            SIMD4<Float>(0.9, 0.7, 0.2, 1.0),  // Yellow
        ]
        return colors.randomElement()!
    }
    
    private func updateVehicleBuffer() {
        guard let buffer = vehicleBuffer else { return }
        
        let pointer = buffer.contents().bindMemory(to: Vehicle.self, capacity: maxVehicles)
        for i in 0..<maxVehicles {
            pointer[i] = vehicles[i]
        }
    }
    
    // MARK: - Public Methods
    
    func start() {
        isRunning = true
    }
    
    func stop() {
        isRunning = false
    }
    
    func update(deltaTime: Float) {
        guard isRunning else { return }
        
        simulationTime += deltaTime
        
        // Update vehicles on CPU for now (will move to GPU compute)
        updateVehiclesCPU(deltaTime: deltaTime)
        
        // Spawn new vehicles periodically
        if Int(simulationTime * 2) % 10 == 0 && vehicleCount < maxVehicles - 10 {
            spawnNewVehicle()
        }
        
        updateVehicleBuffer()
    }
    
    private func updateVehiclesCPU(deltaTime: Float) {
        for i in 0..<vehicleCount {
            var vehicle = vehicles[i]
            
            // Calculate direction to destination
            let toDestination = vehicle.destination - vehicle.position
            let distance = length(toDestination)
            
            if distance < 2.0 {
                // Reached destination, pick a new one
                let newNode = Int.random(in: 0..<roadNodes.count)
                vehicle.destination = roadNodes[newNode]
            } else {
                // Move towards destination
                let direction = normalize(toDestination)
                vehicle.velocity = direction * vehicle.speed
                
                // Simple collision avoidance
                for j in 0..<vehicleCount where j != i {
                    let other = vehicles[j]
                    let separation = vehicle.position - other.position
                    let sepDistance = length(separation)
                    
                    if sepDistance < 5.0 && sepDistance > 0.001 {
                        // Too close, adjust velocity
                        let avoidance = normalize(separation) * (5.0 - sepDistance)
                        vehicle.velocity += avoidance * 2.0
                    }
                }
                
                // Clamp velocity
                if length(vehicle.velocity) > vehicle.speed {
                    vehicle.velocity = normalize(vehicle.velocity) * vehicle.speed
                }
                
                // Update position
                vehicle.position += vehicle.velocity * deltaTime
                vehicle.position.y = 0.5  // Keep vehicles at road level
            }
            
            vehicles[i] = vehicle
        }
    }
    
    private func spawnNewVehicle() {
        guard vehicleCount < maxVehicles else { return }
        
        let startNode = Int.random(in: 0..<roadNodes.count)
        let endNode = Int.random(in: 0..<roadNodes.count)
        
        var vehicle = Vehicle(
            position: roadNodes[startNode],
            velocity: SIMD3<Float>(0, 0, 0),
            destination: roadNodes[endNode],
            type: UInt32.random(in: 0...2),
            speed: Float.random(in: 8...15),
            color: randomVehicleColor()
        )
        
        // Offset for lane
        vehicle.position.x += Float.random(in: -2...2)
        
        vehicles[vehicleCount] = vehicle
        vehicleCount += 1
    }
    
    func getVehicleBuffer() -> MTLBuffer? {
        return vehicleBuffer
    }
    
    func getVehicleCount() -> Int {
        return vehicleCount
    }
    
    func getVehicles() -> [Vehicle] {
        return Array(vehicles.prefix(vehicleCount))
    }
    
    // MARK: - GPU Compute (To be implemented)
    
    func updateWithGPU(commandBuffer: MTLCommandBuffer, deltaTime: Float) {
        // This will use Metal compute shaders for parallel vehicle updates
        // Currently using CPU simulation
    }
}