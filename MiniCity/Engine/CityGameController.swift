//
//  CityGameController.swift
//  MiniCity
//
//  Main game controller integrating Metal rendering with GameplayKit

import MetalKit
import GameplayKit
import Combine
import simd
import UIKit

class CityGameController: NSObject {
    
    // Core components
    private var metalEngine: MetalEngine!
    private var view: MTKView!
    
    // GameplayKit
    private var stateMachine: GKStateMachine!
    private var entityManager: GKEntity!  // Using GKEntity as manager for now
    private var componentSystems: [GKComponentSystem<GKComponent>] = []
    private var entities: [GKEntity] = []  // Track entities manually
    
    // Game state
    private var cityGrid: CityGrid!
    private var economyManager: EconomyManager!
    private var populationManager: PopulationManager!
    private var trafficManager: TrafficManager!
    
    // Simulation systems
    private var trafficSimulation: GameplayKitTrafficSimulation!
    
    // UI
    private var hudOverlay: HUDOverlay!
    
    // Camera
    private(set) var cameraController: CameraController!
    
    // Input handling
    private var inputHandler: InputHandler!
    
    // Timing
    private var lastUpdateTime: TimeInterval = 0
    private var deltaTime: TimeInterval = 0
    
    // UI State
    @Published var population: Int = 0
    @Published var budget: Float = 100000
    @Published var happiness: Float = 0.5
    @Published var selectedTool: BuildTool = .none
    
    override init() {
        super.init()
        setupGameSystems()
    }
    
    func setup(with view: MTKView) {
        self.view = view
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        
        guard let device = view.device else {
            fatalError("Metal device not available")
        }
        
        do {
            // Initialize Metal engine
            let config = EngineConfiguration(
                maxBuildings: 5000,
                maxVehicles: 500,
                maxTrees: 2000,
                enableTessellation: device.supportsFamily(.apple4),
                enableInstancing: true,
                enableCompute: true
            )
            metalEngine = try MetalEngine(device: device, config: config)
            
            // Setup camera with better initial position
            cameraController = CameraController()
            // Camera position will be set internally
            cameraController.setupGestures(for: view)
            
            // Initialize GameplayKit traffic simulation
            trafficSimulation = GameplayKitTrafficSimulation()
            trafficSimulation.start()
            
            // Setup HUD overlay
            setupHUDOverlay()
            
            // Setup input
            inputHandler = InputHandler()
            inputHandler.delegate = self
            
            // Initialize city
            initializeCity()
            
            print("City initialized with \(entities.count) entities")
            print("Camera position: \(cameraController.position)")
            print("Metal engine initialized successfully")
            
        } catch {
            fatalError("Failed to initialize Metal engine: \(error)")
        }
    }
    
    private func setupGameSystems() {
        // Entity manager placeholder
        entityManager = GKEntity()
        
        // State machine for game states
        let menuState = MenuState(controller: self)
        let playingState = PlayingState(controller: self)
        let buildingState = BuildingState(controller: self)
        let pausedState = PausedState(controller: self)
        
        stateMachine = GKStateMachine(states: [menuState, playingState, buildingState, pausedState])
        stateMachine.enter(PlayingState.self)
        
        // Component systems
        let buildingSystem = GKComponentSystem(componentClass: BuildingComponent.self)
        let roadSystem = GKComponentSystem(componentClass: RoadComponent.self)
        let economySystem = GKComponentSystem(componentClass: EconomyComponent.self)
        let populationSystem = GKComponentSystem(componentClass: GKComponent.self)
        
        componentSystems = [buildingSystem as GKComponentSystem<GKComponent>, 
                           roadSystem as GKComponentSystem<GKComponent>, 
                           economySystem as GKComponentSystem<GKComponent>, 
                           populationSystem]
        
        // Managers
        cityGrid = CityGrid(width: 100, height: 100)
        economyManager = EconomyManager(initialBudget: 100000)
        populationManager = PopulationManager()
        trafficManager = TrafficManager()
    }
    
    private func setupHUDOverlay() {
        guard let view = view else { return }
        
        hudOverlay = HUDOverlay(frame: view.bounds)
        hudOverlay.delegate = self
        hudOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hudOverlay)
        
        // Initial stats update
        updateHUDStats()
    }
    
    private func initializeCity() {
        // Generate initial terrain
        generateTerrain()
        
        // Place initial roads
        placeInitialRoads()
        
        // Add some starter buildings
        placeStarterBuildings()
    }
    
    private func generateTerrain() {
        // Use Perlin noise for terrain height
        let noise = GKNoise(GKPerlinNoiseSource())
        _ = GKNoiseMap(noise, size: vector_double2(512, 512), 
                                  origin: vector_double2(0, 0), 
                                  sampleCount: vector_int2(512, 512), 
                                  seamless: true)
        
        // Convert to height data and send to Metal engine  
        // TODO: Implement terrain height map update
        // metalEngine.updateTerrainHeightMap(noiseMap)
    }
    
    private func placeInitialRoads() {
        // Create main avenue grid
        for i in stride(from: 10, to: 90, by: 20) {
            // North-South roads
            for j in 0..<100 {
                cityGrid.placeRoad(at: GridPosition(x: i, y: j), type: .avenue)
            }
            
            // East-West roads
            for j in 0..<100 {
                cityGrid.placeRoad(at: GridPosition(x: j, y: i), type: .avenue)
            }
        }
    }
    
    private func placeStarterBuildings() {
        // Place some initial buildings with more variety and density
        let buildingTypes: [BuildingType] = [.residential, .commercial, .industrial, .office, .service]
        
        // Place buildings in a more organized pattern
        for blockX in stride(from: 20, to: 80, by: 10) {
            for blockY in stride(from: 20, to: 80, by: 10) {
                // Place 2-3 buildings per block
                for _ in 0..<3 {
                    let x = blockX + Int.random(in: 0..<8)
                    let y = blockY + Int.random(in: 0..<8)
                    let type = buildingTypes.randomElement()!
                    
                    if cityGrid.canPlaceBuilding(at: GridPosition(x: x, y: y)) {
                        let building = createBuilding(type: type, position: GridPosition(x: x, y: y))
                        entities.append(building)  // Track manually
                        
                        // Pass building data to Metal engine
                        let pos = GridPosition(x: x, y: y).toWorldPosition()
                        metalEngine.addBuilding(at: pos, type: type, height: Float.random(in: 10...50))
                    }
                }
            }
        }
        
        print("Placed \(entities.count) starter buildings")
    }
    
    private func createBuilding(type: BuildingType, position: GridPosition) -> GKEntity {
        let entity = GKEntity()
        
        // Add components
        let buildingComponent = BuildingComponent()
        buildingComponent.buildingType = type
        buildingComponent.population = type == .residential ? Int.random(in: 10...100) : 0
        entity.addComponent(buildingComponent)
        
        let renderComponent = RenderComponent()
        renderComponent.modelType = .building
        renderComponent.position = position.toWorldPosition()
        entity.addComponent(renderComponent)
        
        let economyComponent = EconomyComponent()
        economyComponent.balance = 0
        economyComponent.income = type == .commercial ? Float.random(in: 100...500) : 0
        entity.addComponent(economyComponent)
        
        // Register with systems
        for system in componentSystems {
            system.addComponent(foundIn: entity)
        }
        
        // Update city grid
        cityGrid.placeBuilding(at: position, entity: entity)
        
        return entity
    }
    
    func update(deltaTime: TimeInterval) {
        self.deltaTime = deltaTime
        
        // Update state machine
        stateMachine.update(deltaTime: deltaTime)
        
        // Update component systems
        for system in componentSystems {
            system.update(deltaTime: deltaTime)
        }
        
        // Update managers
        economyManager.update(deltaTime: deltaTime)
        populationManager.update(deltaTime: deltaTime)
        trafficManager.update(deltaTime: deltaTime)
        
        // Update published properties
        population = populationManager.totalPopulation
        budget = economyManager.currentBudget
        happiness = populationManager.averageHappiness
        
        // Update camera
        cameraController.update(deltaTime: deltaTime)
        
        // Update traffic simulation
        trafficSimulation.update(deltaTime: deltaTime)
        
        // Update HUD stats
        updateHUDStats()
    }
}

// MARK: - MTKViewDelegate
extension CityGameController: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        cameraController.updateAspectRatio(Float(size.width / size.height))
    }
    
    func draw(in view: MTKView) {
        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let deltaTime = currentTime - lastUpdateTime
        lastUpdateTime = currentTime
        
        // Update game logic
        update(deltaTime: deltaTime)
        
        // Render frame with traffic
        metalEngine.render(in: view, camera: cameraController, trafficSimulation: trafficSimulation)
    }
}

// MARK: - Input Handling
// MARK: - HUD Management
extension CityGameController {
    private func updateHUDStats() {
        // Guard against division by zero
        let fps = deltaTime > 0 ? Int(1.0 / deltaTime) : 60
        let day = Int(CACurrentMediaTime() / 60) % 365 + 1
        let hour = Int(CACurrentMediaTime() / 2.5) % 24
        
        hudOverlay?.updateStats(
            population: population,
            money: Int(budget),
            day: day,
            hour: hour,
            fps: fps
        )
    }
}

// MARK: - HUD Overlay Delegate
extension CityGameController: HUDOverlayDelegate {
    func hudOverlay(_ overlay: HUDOverlay, didSelectBuildingType type: BuildingCategory) {
        // Convert UI building type to game building type
        switch type {
        case .residential:
            selectedTool = .placeBuilding(.residential)
        case .commercial:
            selectedTool = .placeBuilding(.commercial)
        case .industrial:
            selectedTool = .placeBuilding(.industrial)
        case .park:
            selectedTool = .placeBuilding(.service)
        case .road:
            selectedTool = .placeRoad(.street)
        }
    }
    
    func handleTapAtWorldPosition(_ position: SIMD3<Float>) {
        // Call the existing building placement method
        hudOverlay?.placeBuildingAt(position: position)
    }
    
    func hudOverlay(_ overlay: HUDOverlay, didPlaceBuildingAt position: SIMD3<Float>) {
        let gridPos = cityGrid.worldToGrid(position)
        
        switch selectedTool {
        case .placeBuilding(let type):
            if cityGrid.canPlaceBuilding(at: gridPos) {
                let cost = type.constructionCost
                if economyManager.canAfford(cost) {
                    economyManager.spend(cost)
                    let building = createBuilding(type: type, position: gridPos)
                    entities.append(building)
                    
                    // Add to Metal engine
                    let worldPos = gridPos.toWorldPosition()
                    metalEngine.addBuilding(at: worldPos, type: type, height: Float.random(in: 10...50))
                }
            }
        default:
            break
        }
        
        overlay.endPlacementMode()
    }
    
    func hudOverlayDidToggleSimulation(_ overlay: HUDOverlay) {
        if trafficSimulation.isRunning {
            trafficSimulation.stop()
            stateMachine.enter(PausedState.self)
        } else {
            trafficSimulation.start()
            stateMachine.enter(PlayingState.self)
        }
    }
    
    func hudOverlayDidRequestStats(_ overlay: HUDOverlay) {
        // Show detailed stats panel
        print("Population: \(population)")
        print("Budget: $\(Int(budget))")
        print("Happiness: \(Int(happiness * 100))%")
        print("Active vehicles: \(trafficSimulation.getVehicleCount())")
    }
}

extension CityGameController: InputHandlerDelegate {
    
    func didTapAt(position: CGPoint, in view: UIView) {
        // Convert screen position to world position
        let worldPos = cameraController.screenToWorld(position, in: view)
        let gridPos = cityGrid.worldToGrid(worldPos)
        
        switch selectedTool {
        case .placeBuilding(let type):
            if cityGrid.canPlaceBuilding(at: gridPos) {
                let cost = type.constructionCost
                if economyManager.canAfford(cost) {
                    economyManager.spend(cost)
                    let building = createBuilding(type: type, position: gridPos)
                    entities.append(building)  // Track manually
                }
            }
            
        case .placeRoad(let type):
            if cityGrid.canPlaceRoad(at: gridPos) {
                let cost = type.constructionCost
                if economyManager.canAfford(cost) {
                    economyManager.spend(cost)
                    cityGrid.placeRoad(at: gridPos, type: type)
                }
            }
            
        case .demolish:
            if let entity = cityGrid.getEntity(at: gridPos) {
                entities.removeAll { $0 === entity }  // Remove manually
                cityGrid.removeEntity(at: gridPos)
            }
            
        case .none:
            // Select entity for inspection
            if cityGrid.getEntity(at: gridPos) != nil {
                // Show entity info panel
            }
        }
    }
    
    func didDragFrom(start: CGPoint, to end: CGPoint, in view: UIView) {
        // Handle zone placement or multi-selection
    }
}

// MARK: - Game States
class MenuState: GKState {
    weak var controller: CityGameController?
    
    init(controller: CityGameController) {
        self.controller = controller
        super.init()
    }
    
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        return stateClass is PlayingState.Type
    }
}

class PlayingState: GKState {
    weak var controller: CityGameController?
    
    init(controller: CityGameController) {
        self.controller = controller
        super.init()
    }
    
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        return stateClass is BuildingState.Type || stateClass is PausedState.Type
    }
    
    override func update(deltaTime seconds: TimeInterval) {
        // Normal game update
    }
}

class BuildingState: GKState {
    weak var controller: CityGameController?
    
    init(controller: CityGameController) {
        self.controller = controller
        super.init()
    }
    
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        return stateClass is PlayingState.Type
    }
    
    override func didEnter(from previousState: GKState?) {
        // Show building UI
    }
    
    override func willExit(to nextState: GKState) {
        // Hide building UI
    }
}

class PausedState: GKState {
    weak var controller: CityGameController?
    
    init(controller: CityGameController) {
        self.controller = controller
        super.init()
    }
    
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        return stateClass is PlayingState.Type || stateClass is MenuState.Type
    }
}

// MARK: - Supporting Types
enum BuildTool {
    case none
    case placeBuilding(BuildingType)
    case placeRoad(RoadType)
    case demolish
}

// Types moved to GameTypes.swift

// MARK: - GameplayKit Components

class BuildingComponent: GKComponent {
    var buildingType: BuildingType = .residential
    var population: Int = 0
    var powerConsumption: Float = 0
    var waterConsumption: Float = 0
    var taxRevenue: Float = 0
}

class RoadComponent: GKComponent {
    var capacity: Int = 100
    var currentTraffic: Int = 0
    var speedLimit: Float = 50
}

class VehicleComponent: GKComponent {
    var currentSpeed: Float = 0
    var destination: SIMD3<Float> = .zero
    var path: [SIMD3<Float>] = []
}

class EconomyComponent: GKComponent {
    var balance: Float = 100000
    var income: Float = 0
    var expenses: Float = 0
}

// BuildingType moved to top of file to avoid conflicts

// MARK: - Component Systems
class BuildingSystem: GKComponentSystem<BuildingComponent> {
    override func update(deltaTime seconds: TimeInterval) {
        for _ in components {
            // Update building simulation
        }
    }
}

class RoadSystem: GKComponentSystem<RoadComponent> {
    override func update(deltaTime seconds: TimeInterval) {
        for _ in components {
            // Update traffic flow
        }
    }
}

class EconomySystem: GKComponentSystem<EconomyComponent> {
    override func update(deltaTime seconds: TimeInterval) {
        for _ in components {
            // Calculate income/expenses
        }
    }
}

class PopulationSystem: GKComponentSystem<GKComponent> {
    override func update(deltaTime seconds: TimeInterval) {
        // Update population dynamics
    }
}

// MARK: - Helper Components
class RenderComponent: GKComponent {
    var modelType: ModelType = .building
    var position: SIMD3<Float> = .zero
    var rotation: Float = 0
    var scale: SIMD3<Float> = .one
}

enum ModelType {
    case building, road, tree, vehicle
}

// MARK: - Delegate Protocols
protocol InputHandlerDelegate: AnyObject {
    func didTapAt(position: CGPoint, in view: UIView)
    func didDragFrom(start: CGPoint, to end: CGPoint, in view: UIView)
}

class InputHandler {
    weak var delegate: InputHandlerDelegate?
    
    // Handle gestures and input
}