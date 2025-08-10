//
//  GameTypes.swift
//  MiniCity
//
//  Shared type definitions to avoid conflicts
//

import Foundation
import simd

// MARK: - Building Types

enum BuildingType: Int, CaseIterable {
    case residential = 0
    case commercial = 1
    case industrial = 2
    case office = 3
    case service = 4
    
    var constructionCost: Float {
        switch self {
        case .residential: return 100
        case .commercial: return 200
        case .industrial: return 300
        case .office: return 500
        case .service: return 150
        }
    }
}

// MARK: - Road Types

enum RoadType {
    case street, avenue, highway
    
    var constructionCost: Float {
        switch self {
        case .street: return 10
        case .avenue: return 25
        case .highway: return 100
        }
    }
}

// MARK: - Road Segment

struct RoadSegment {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
    let width: Float
    let type: RoadType
    
    var length: Float {
        return distance(start, end)
    }
    
    var midpoint: SIMD3<Float> {
        return (start + end) * 0.5
    }
}