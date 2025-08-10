//
//  GameplayKitTrafficSimulation.swift
//  MiniCity
//
//  Traffic simulation using GameplayKit agents and behaviors
//

import GameplayKit
import simd

// MARK: - Vehicle Agent
class VehicleAgent: GKAgent2D {
    enum VehicleType {
        case car, bus, truck, emergency
        
        var maxSpeed: Float {
            switch self {
            case .car: return 15.0
            case .bus: return 10.0
            case .truck: return 8.0
            case .emergency: return 20.0
            }
        }
        
        var mass: Float {
            switch self {
            case .car: return 1.0
            case .bus: return 3.0
            case .truck: return 4.0
            case .emergency: return 1.5
            }
        }
        
        var color: SIMD4<Float> {
            switch self {
            case .car: return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
            case .bus: return SIMD4<Float>(0.9, 0.7, 0.2, 1.0)
            case .truck: return SIMD4<Float>(0.3, 0.3, 0.5, 1.0)
            case .emergency: return SIMD4<Float>(1.0, 0.2, 0.2, 1.0)
            }
        }
    }
    
    let vehicleType: VehicleType
    var currentRoad: TrafficRoadSegment?
    var destination: GKGraphNode2D?
    var path: [GKGraphNode2D] = []
    var pathIndex = 0
    
    init(vehicleType: VehicleType) {
        self.vehicleType = vehicleType
        super.init()
        
        // Configure agent properties
        self.radius = 2.0
        self.maxSpeed = vehicleType.maxSpeed
        self.maxAcceleration = 5.0
        self.mass = vehicleType.mass
        
        // Initial random position
        self.position = vector_float2(
            Float.random(in: -100...100),
            Float.random(in: -100...100)
        )
        
        // Random initial velocity direction (velocity is managed by agent system)
        _ = Float.random(in: 0...(2 * .pi))
        // The velocity will be set by the behavior system
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func get3DPosition() -> SIMD3<Float> {
        return SIMD3<Float>(position.x, 0.5, position.y)
    }
}

// MARK: - Traffic Light Agent
class TrafficLightAgent: GKAgent2D {
    enum LightState {
        case green, yellow, red
        
        var duration: TimeInterval {
            switch self {
            case .green: return 30.0
            case .yellow: return 3.0
            case .red: return 33.0
            }
        }
    }
    
    var currentState: LightState = .green
    var timeInState: TimeInterval = 0
    let intersection: GKGraphNode2D
    
    init(intersection: GKGraphNode2D) {
        self.intersection = intersection
        super.init()
        self.position = intersection.position
        self.radius = 10.0  // Influence radius
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func update(deltaTime: TimeInterval) {
        timeInState += deltaTime
        
        if timeInState >= currentState.duration {
            // Cycle to next state
            switch currentState {
            case .green:
                currentState = .yellow
            case .yellow:
                currentState = .red
            case .red:
                currentState = .green
            }
            timeInState = 0
        }
    }
}

// MARK: - Road Network
struct TrafficRoadSegment {
    let startNode: GKGraphNode2D
    let endNode: GKGraphNode2D
    let speedLimit: Float
    let lanes: Int
    
    var length: Float {
        let dx = endNode.position.x - startNode.position.x
        let dy = endNode.position.y - startNode.position.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Main Traffic Simulation
class GameplayKitTrafficSimulation {
    
    // GameplayKit components
    private var roadGraph: GKGraph!
    private var obstacleGraph: GKObstacleGraph<GKGraphNode2D>!
    // Remove component system - we'll update agents directly
    
    // Agents
    private var vehicleAgents: [VehicleAgent] = []
    private var trafficLights: [TrafficLightAgent] = []
    
    // Road network
    private var roadSegments: [TrafficRoadSegment] = []
    private var intersections: [GKGraphNode2D] = []
    
    // Simulation parameters
    private let maxVehicles = 200
    private(set) var isRunning = false  // Allow external read access
    private var simulationTime: TimeInterval = 0
    
    // Spawn parameters
    private let spawnInterval: TimeInterval = 2.0
    private var timeSinceLastSpawn: TimeInterval = 0
    
    init() {
        setupRoadNetwork()
        spawnInitialVehicles()
    }
    
    private func setupRoadNetwork() {
        // Create a grid-based road network using GKGraphNode2D
        roadGraph = GKGraph()
        intersections = []
        
        let gridSize = 5
        let spacing: Float = 40.0
        
        // Create intersection nodes
        for x in -gridSize...gridSize {
            for z in -gridSize...gridSize {
                let node = GKGraphNode2D(point: vector_float2(
                    Float(x) * spacing,
                    Float(z) * spacing
                ))
                intersections.append(node)
            }
        }
        
        roadGraph.add(intersections)
        
        // Connect adjacent intersections
        let nodesPerRow = gridSize * 2 + 1
        for i in 0..<intersections.count {
            let x = i % nodesPerRow
            let z = i / nodesPerRow
            
            var connections: [GKGraphNode2D] = []
            
            // Right neighbor
            if x < nodesPerRow - 1 {
                let rightNode = intersections[i + 1]
                connections.append(rightNode)
                roadSegments.append(TrafficRoadSegment(
                    startNode: intersections[i],
                    endNode: rightNode,
                    speedLimit: 15.0,
                    lanes: 2
                ))
            }
            
            // Bottom neighbor
            if z < nodesPerRow - 1 {
                let bottomNode = intersections[i + nodesPerRow]
                connections.append(bottomNode)
                roadSegments.append(TrafficRoadSegment(
                    startNode: intersections[i],
                    endNode: bottomNode,
                    speedLimit: 15.0,
                    lanes: 2
                ))
            }
            
            if !connections.isEmpty {
                intersections[i].addConnections(to: connections, bidirectional: true)
            }
        }
        
        // Add traffic lights at major intersections
        for i in stride(from: 0, to: intersections.count, by: 3) {
            let trafficLight = TrafficLightAgent(intersection: intersections[i])
            trafficLights.append(trafficLight)
        }
        
        // Create obstacle graph for buildings
        setupObstacles()
    }
    
    private func setupObstacles() {
        // Create obstacles for buildings to avoid
        var obstacles: [GKPolygonObstacle] = []
        
        // Add building obstacles (simplified as rectangles)
        for blockX in stride(from: -80, to: 80, by: 40) {
            for blockZ in stride(from: -80, to: 80, by: 40) {
                // Skip road intersections
                if abs(blockX) % 40 == 0 || abs(blockZ) % 40 == 0 {
                    continue
                }
                
                // Create building footprint
                let buildingSize: Float = 15.0
                let vertices = [
                    vector_float2(Float(blockX) - buildingSize, Float(blockZ) - buildingSize),
                    vector_float2(Float(blockX) + buildingSize, Float(blockZ) - buildingSize),
                    vector_float2(Float(blockX) + buildingSize, Float(blockZ) + buildingSize),
                    vector_float2(Float(blockX) - buildingSize, Float(blockZ) + buildingSize)
                ]
                
                let obstacle = GKPolygonObstacle(points: vertices)
                obstacles.append(obstacle)
            }
        }
        
        // Create nodes that avoid obstacles
        obstacleGraph = GKObstacleGraph(obstacles: obstacles, bufferRadius: 5.0)
    }
    
    
    private func spawnInitialVehicles() {
        for _ in 0..<50 {
            spawnVehicle()
        }
    }
    
    private func spawnVehicle() {
        guard vehicleAgents.count < maxVehicles else { return }
        
        // Random vehicle type
        let types: [VehicleAgent.VehicleType] = [.car, .car, .car, .bus, .truck]
        let vehicleType = types.randomElement()!
        
        let vehicle = VehicleAgent(vehicleType: vehicleType)
        
        // Set initial position at random intersection
        if let startNode = intersections.randomElement() {
            vehicle.position = startNode.position
            
            // Set random destination
            if let endNode = intersections.randomElement() {
                vehicle.destination = endNode
                
                // Find path
                if let path = roadGraph.findPath(from: startNode, to: endNode) as? [GKGraphNode2D] {
                    vehicle.path = path
                    vehicle.pathIndex = 0
                    
                    // Setup initial behavior
                    updateVehicleBehavior(vehicle)
                }
            }
        }
        
        vehicleAgents.append(vehicle)
    }
    
    private func updateVehicleBehavior(_ vehicle: VehicleAgent) {
        var goals: [(goal: GKGoal, weight: Float)] = []
        
        // Path following behavior
        if vehicle.pathIndex < vehicle.path.count {
            let targetNode = vehicle.path[vehicle.pathIndex]
            // Create a temporary agent at the target position
            let targetAgent = GKAgent2D()
            targetAgent.position = targetNode.position
            let seekGoal = GKGoal(toSeekAgent: targetAgent)
            goals.append((goal: seekGoal, weight: 1.0))
        }
        
        // Avoid other vehicles
        let nearbyVehicles = vehicleAgents.filter { other in
            other !== vehicle &&
            distance(vehicle.position, other.position) < 20.0
        }
        
        if !nearbyVehicles.isEmpty {
            let avoidGoal = GKGoal(toAvoid: nearbyVehicles, maxPredictionTime: 1.0)
            goals.append((goal: avoidGoal, weight: 2.0))
        }
        
        // Traffic light behavior
        for light in trafficLights {
            if distance(vehicle.position, light.position) < light.radius {
                if light.currentState == .red {
                    // Stop at red light
                    let stopGoal = GKGoal(toReachTargetSpeed: 0)
                    goals.append((goal: stopGoal, weight: 5.0))
                } else if light.currentState == .yellow {
                    // Slow down for yellow
                    let slowGoal = GKGoal(toReachTargetSpeed: vehicle.maxSpeed * 0.3)
                    goals.append((goal: slowGoal, weight: 3.0))
                }
            }
        }
        
        // Stay on road (align with road direction)
        if let currentRoad = findCurrentRoad(for: vehicle) {
            let roadDirection = normalize(currentRoad.endNode.position - currentRoad.startNode.position)
            let alignGoal = GKGoal(toAlignWith: [vehicle], maxDistance: 100, maxAngle: Float.pi / 4)
            goals.append((goal: alignGoal, weight: 0.5))
        }
        
        // Create composite behavior from goals
        let compositeBehavior = GKBehavior()
        for (goal, weight) in goals {
            compositeBehavior.setWeight(weight, for: goal)
        }
        vehicle.behavior = compositeBehavior
    }
    
    private func findCurrentRoad(for vehicle: VehicleAgent) -> TrafficRoadSegment? {
        // Find the road segment the vehicle is currently on
        return roadSegments.min { road1, road2 in
            distanceToLineSegment(point: vehicle.position,
                                 start: road1.startNode.position,
                                 end: road1.endNode.position) <
            distanceToLineSegment(point: vehicle.position,
                                 start: road2.startNode.position,
                                 end: road2.endNode.position)
        }
    }
    
    private func distanceToLineSegment(point: vector_float2, start: vector_float2, end: vector_float2) -> Float {
        let line = end - start
        let lenSquared = dot(line, line)
        if lenSquared == 0 { return distance(point, start) }
        
        let t = max(0, min(1, dot(point - start, line) / lenSquared))
        let projection = start + t * line
        return distance(point, projection)
    }
    
    // MARK: - Public Methods
    
    func start() {
        isRunning = true
    }
    
    func stop() {
        isRunning = false
    }
    
    func update(deltaTime: TimeInterval) {
        guard isRunning else { return }
        
        simulationTime += deltaTime
        
        // Update traffic lights
        for light in trafficLights {
            light.update(deltaTime: deltaTime)
        }
        
        // Update vehicle agents manually
        for vehicle in vehicleAgents {
            vehicle.update(deltaTime: deltaTime)
        }
        
        // Update vehicle behaviors and check destinations
        for vehicle in vehicleAgents {
            // Check if reached current waypoint
            if vehicle.pathIndex < vehicle.path.count {
                let targetNode = vehicle.path[vehicle.pathIndex]
                if distance(vehicle.position, targetNode.position) < 5.0 {
                    vehicle.pathIndex += 1
                    
                    // Reached destination?
                    if vehicle.pathIndex >= vehicle.path.count {
                        // Pick new destination
                        if let newDest = intersections.randomElement(),
                           let currentNode = intersections.min(by: { n1, n2 in
                               distance(n1.position, vehicle.position) < distance(n2.position, vehicle.position)
                           }),
                           let newPath = roadGraph.findPath(from: currentNode, to: newDest) as? [GKGraphNode2D] {
                            vehicle.destination = newDest
                            vehicle.path = newPath
                            vehicle.pathIndex = 0
                        }
                    }
                }
                
                // Update behavior for new target
                updateVehicleBehavior(vehicle)
            }
        }
        
        // Spawn new vehicles periodically
        timeSinceLastSpawn += deltaTime
        if timeSinceLastSpawn >= spawnInterval {
            spawnVehicle()
            timeSinceLastSpawn = 0
        }
        
        // Remove vehicles that are stuck or out of bounds
        vehicleAgents.removeAll { vehicle in
            let pos = vehicle.position
            return pos.x < -300 || pos.x > 300 || pos.y < -300 || pos.y > 300
        }
    }
    
    func getVehicles() -> [(position: SIMD3<Float>, color: SIMD4<Float>, type: VehicleAgent.VehicleType)] {
        return vehicleAgents.map { vehicle in
            (position: vehicle.get3DPosition(),
             color: vehicle.vehicleType.color,
             type: vehicle.vehicleType)
        }
    }
    
    func getVehicleCount() -> Int {
        return vehicleAgents.count
    }
    
    // isRunning property is already defined as private var above
}