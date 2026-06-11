import Foundation
import CoreGraphics

// MARK: - Render models

struct RenderWorld: Codable {
    let grid: GridInfo
    let rooms: [RenderRoom]
    let corridors: [Corridor]
    let party: Party

    struct GridInfo: Codable {
        let cols: Int
        let rows: Int
        let tileSize: Int?
    }

    struct RenderRoom: Codable, Identifiable {
        let id: String
        let label: String
        let col: Int
        let row: Int
        let widthTiles: Int?
        let heightTiles: Int?
        let floorTile: String?
        let wallTile: String?
        let isCurrentRoom: Bool
        let doors: [Door]?
        let objects: [RoomObject]

        // legacy fallback for old API shape
        let connections: [String]?
    }

    struct Door: Codable {
        let direction: String
        let toRoom: String
        let tileX: Int
        let tileY: Int
        let locked: Bool
    }

    struct RoomObject: Codable, Identifiable {
        let id: String
        let sprite: String?
        let tileX: Int?
        let tileY: Int?
        let state: String
        let interacted: Bool
        let takeable: Bool
        let interactable: Bool
        let scenic: Bool?
    }

    struct Corridor: Codable {
        let fromRoom: String
        let toRoom: String
        let direction: String
    }

    struct Party: Codable {
        let currentRoom: String
        let inventory: [String]
        let tick: Int
    }
}

// MARK: - Top-level API response

struct GenerateResponse: Codable {
    let render: RenderWorld
    let sprites: [String: String]?  // objectId → base64 PNG
    let solver: SolverLog?
}

// MARK: - Solver result

struct SolverLog: Codable {
    let won: Bool
    let ticks: Int
    let optimal: Int
    let reward: Double
    let efficiency: Double
    let wasted: Int
    let history: [String]
}

// MARK: - Streaming progress events

struct StreamEvent: Codable {
    let type: String
    let stage: String?
    let message: String?
    let current: Int?
    let total: Int?
    let detail: String?
}

// MARK: - Streaming solver tick events

struct SolverTickEvent: Codable, Identifiable {
    var id: Int { tick }

    let type: String  // "tick"
    let tick: Int
    let room: String
    let thought: String?
    let plan: String?
    let finalAction: String?
    let currentGoal: String?
    let nextPlanStep: String?
    let prevOutcome: PrevOutcome?
    let newMilestones: [String]?
    let gatesFired: [String]?
    let render: RenderWorld?

    struct PrevOutcome: Codable {
        let action: String?
        let note: String?
        let success: Bool?
    }

    enum CodingKeys: String, CodingKey {
        case type, tick, room, thought, plan, render
        case finalAction = "final_action"
        case currentGoal = "current_goal"
        case nextPlanStep = "next_plan_step"
        case prevOutcome = "prev_outcome"
        case newMilestones = "new_milestones"
        case gatesFired = "gates_fired"
    }
}

// MARK: - Streaming sprites-ready event

struct SpritesEvent: Codable {
    let type: String  // "sprites"
    let sprites: [String: String]  // objectId → base64 PNG
}

// MARK: - Decoded sprite cache

final class SpriteCache {
    static let shared = SpriteCache()
    private var images: [String: CGImage] = [:]

    func load(sprites: [String: String]) {
        images.removeAll()
        for (id, b64) in sprites {
            guard
                let data = Data(base64Encoded: b64),
                let provider = CGDataProvider(data: data as CFData),
                let img = CGImage(pngDataProviderSource: provider,
                                  decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
            else { continue }
            images[id] = img
        }
    }

    func image(for id: String) -> CGImage? { images[id] }
}
