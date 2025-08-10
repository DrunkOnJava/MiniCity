//
//  GameComponents.swift
//  MiniCity
//
//  Supporting types and components for the city simulation

import GameplayKit
import simd

// MARK: - Grid and City Management

struct GridPosition {
    var x: Int
    var y: Int
    
    func toWorldPosition() -> SIMD3<Float> {
        return SIMD3<Float>(Float(x) * 2.0, 0, Float(y) * 2.0)
    }
}

class CityGrid {
    private let width: Int
    private let height: Int
    private var cells: [[CellType]]
    private var entities: [[GKEntity?]]
    
    enum CellType {
        case empty
        case building
        case road
        case park
        case water
    }
    
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: Array(repeating: .empty, count: width), count: height)
        self.entities = Array(repeating: Array(repeating: nil, count: width), count: height)
    }
    
    func canPlaceBuilding(at position: GridPosition) -> Bool {
        guard isValid(position: position) else { return false }
        return cells[position.y][position.x] == .empty
    }
    
    func canPlaceRoad(at position: GridPosition) -> Bool {
        guard isValid(position: position) else { return false }
        let cell = cells[position.y][position.x]
        return cell == .empty || cell == .road
    }
    
    func placeBuilding(at position: GridPosition, entity: GKEntity) {
        guard isValid(position: position) else { return }
        cells[position.y][position.x] = .building
        entities[position.y][position.x] = entity
    }
    
    func placeRoad(at position: GridPosition, type: RoadType) {
        guard isValid(position: position) else { return }
        cells[position.y][position.x] = .road
    }
    
    func getEntity(at position: GridPosition) -> GKEntity? {
        guard isValid(position: position) else { return nil }
        return entities[position.y][position.x]
    }
    
    func removeEntity(at position: GridPosition) {
        guard isValid(position: position) else { return }
        cells[position.y][position.x] = .empty
        entities[position.y][position.x] = nil
    }
    
    func worldToGrid(_ worldPosition: SIMD3<Float>) -> GridPosition {
        let x = Int((worldPosition.x / 2.0).rounded())
        let y = Int((worldPosition.z / 2.0).rounded())
        return GridPosition(x: x, y: y)
    }
    
    private func isValid(position: GridPosition) -> Bool {
        return position.x >= 0 && position.x < width && 
               position.y >= 0 && position.y < height
    }
}

// MARK: - Economy Management

class EconomyManager {
    private(set) var currentBudget: Float
    private var monthlyIncome: Float = 0
    private var monthlyExpenses: Float = 0
    private var taxRate: Float = 0.1
    
    init(initialBudget: Float) {
        self.currentBudget = initialBudget
    }
    
    func canAfford(_ cost: Float) -> Bool {
        return currentBudget >= cost
    }
    
    func spend(_ amount: Float) {
        currentBudget -= amount
    }
    
    func earn(_ amount: Float) {
        currentBudget += amount
    }
    
    func update(deltaTime: TimeInterval) {
        // Update budget based on time (monthly cycles)
        let monthProgress = deltaTime / 30.0 // Assuming 30 seconds = 1 game month
        currentBudget += (monthlyIncome - monthlyExpenses) * Float(monthProgress)
    }
    
    func setTaxRate(_ rate: Float) {
        taxRate = max(0, min(0.5, rate))
    }
}

// MARK: - Population Management

class PopulationManager {
    private(set) var totalPopulation: Int = 0
    private(set) var averageHappiness: Float = 0.5
    private var populationByType: [BuildingType: Int] = [:]
    private var happinessFactor: Float = 0.5
    
    func update(deltaTime: TimeInterval) {
        // Update population growth based on happiness and available housing
        let growthRate = averageHappiness * 0.01
        totalPopulation = Int(Float(totalPopulation) * (1.0 + growthRate * Float(deltaTime)))
    }
    
    func addPopulation(_ amount: Int, type: BuildingType) {
        totalPopulation += amount
        populationByType[type, default: 0] += amount
    }
    
    func removePopulation(_ amount: Int, type: BuildingType) {
        totalPopulation -= amount
        populationByType[type, default: 0] -= amount
    }
    
    func calculateHappiness(services: Float, pollution: Float, taxes: Float) {
        // Happiness based on various factors
        averageHappiness = (services * 0.4 + (1.0 - pollution) * 0.3 + (1.0 - taxes) * 0.3)
        averageHappiness = max(0, min(1, averageHappiness))
    }
}

// MARK: - Traffic Management

class TrafficManager {
    private var vehicles: [VehicleComponent] = []
    private var trafficFlow: Float = 1.0
    private var congestionLevel: Float = 0
    
    func update(deltaTime: TimeInterval) {
        // Update traffic simulation
        for vehicle in vehicles {
            // Update vehicle positions along their paths
        }
        
        // Calculate congestion
        let capacity: Float = 1000 // Base road capacity
        congestionLevel = min(1.0, Float(vehicles.count) / capacity)
        trafficFlow = 1.0 - congestionLevel * 0.5
    }
    
    func addVehicle(_ vehicle: VehicleComponent) {
        vehicles.append(vehicle)
    }
    
    func removeVehicle(_ vehicle: VehicleComponent) {
        vehicles.removeAll { $0 === vehicle }
    }
    
    func getCongestionAt(position: SIMD3<Float>) -> Float {
        // Return local congestion level
        return congestionLevel
    }
}