import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Render models

struct RenderWorld: Codable {
    let grid: GridInfo
    let rooms: [RenderRoom]
    let corridors: [Corridor]
    let party: Party             // kept for back-compat (agent_1 / first agent view)
    let parties: [Party]?

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
        let agentsHere: [String]?
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
        let agentId: String?
        let currentRoom: String
        let inventory: [String]
        let tick: Int
    }
}

// MARK: - Storyboard (clue board data)

/// A named suspect for the mystery's clue board. `is_killer` is stripped
/// server-side before this ever reaches the client.
struct Suspect: Codable, Identifiable {
    var id: String { name }

    let name: String
    let connectionToVictim: String?
    let apparentMotive: String?

    enum CodingKeys: String, CodingKey {
        case name
        case connectionToVictim = "connection_to_victim"
        case apparentMotive = "apparent_motive"
    }
}

struct StoryboardMystery: Codable {
    let proofObjectId: String?

    enum CodingKeys: String, CodingKey {
        case proofObjectId = "proof_object_id"
    }
}

/// Narrative layer for a generated world — only the fields the clue board needs.
struct Storyboard: Codable {
    let suspects: [Suspect]
    let mystery: StoryboardMystery?
}

// MARK: - Top-level API response

struct GenerateResponse: Codable {
    let render: RenderWorld
    let sprites: [String: String]?  // objectId → base64 PNG
    let solver: SolverLog?
    let storyboard: Storyboard?
    let narrationOpening: String?
    let narrationEnding: String?

    enum CodingKeys: String, CodingKey {
        case render, sprites, solver, storyboard
        case narrationOpening = "narration_opening"
        case narrationEnding = "narration_ending"
    }
}

// MARK: - /generate/solve response (live-solve a loaded world)

struct SolveResponse: Codable {
    let render: RenderWorld
    let solutionPath: [String]
    let solver: SolverLog?
    let narrationEnding: String?

    enum CodingKeys: String, CodingKey {
        case render, solver
        case solutionPath = "solution_path"
        case narrationEnding = "narration_ending"
    }
}

// MARK: - Saved run summary (GET /generate/runs)

struct SavedRunSummary: Codable, Identifiable {
    var id: String { filename }

    let filename: String
    let theme: String
    let createdAt: Date
    let numRooms: Int
    let numObjects: Int
    let solver: SolverLog?

    enum CodingKeys: String, CodingKey {
        case filename, theme, solver
        case createdAt = "created_at"
        case numRooms = "num_rooms"
        case numObjects = "num_objects"
    }
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
    let wrongDeduction: Bool

    enum CodingKeys: String, CodingKey {
        case won, ticks, optimal, reward, efficiency, wasted, history
        case wrongDeduction = "wrong_deduction"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        won = try container.decode(Bool.self, forKey: .won)
        ticks = try container.decode(Int.self, forKey: .ticks)
        optimal = try container.decode(Int.self, forKey: .optimal)
        reward = try container.decode(Double.self, forKey: .reward)
        efficiency = try container.decode(Double.self, forKey: .efficiency)
        wasted = try container.decode(Int.self, forKey: .wasted)
        history = try container.decode([String].self, forKey: .history)
        // Older saved runs predate this field — default to false rather than fail.
        wrongDeduction = try container.decodeIfPresent(Bool.self, forKey: .wrongDeduction) ?? false
    }
}

// MARK: - Streaming progress events

struct StreamEvent: Codable {
    let type: String
    let stage: String?
    let message: String?
    let current: Int?
    let total: Int?
    let detail: String?
    let text: String?  // narration events: opening/ending prose
}

// MARK: - Streaming solver tick events

struct SolverTickEvent: Codable, Identifiable {
    var id: String { "\(tick)-\(agentId ?? "agent_1")" }

    let type: String  // "tick"
    let tick: Int
    let agentId: String?
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
    let narration: String?

    struct PrevOutcome: Codable {
        let action: String?
        let note: String?
        let success: Bool?
    }

    enum CodingKeys: String, CodingKey {
        case type, tick, room, thought, plan, render, narration
        case agentId = "agent_id"
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

// MARK: - Agent colors

private let agentPalette: [Color] = [.green, .blue, .orange, .purple]

func agentColor(for agentId: String) -> Color {
    let idx = Int(agentId.split(separator: "_").last ?? "1") ?? 1
    return agentPalette[(idx - 1) % agentPalette.count]
}

// MARK: - Milestone tokens (clue board evidence log)

/// Milestone tokens look like "took:rusty_key" or "opened:supply_locker" —
/// mirrors `_humanize` in `src/escape_rooms/agents/cognition.py`.
func humanizeMilestone(_ token: String) -> String {
    let parts = token.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return token.replacingOccurrences(of: "_", with: " ") }
    let kind = parts[0]
    let rest = parts[1].replacingOccurrences(of: "_", with: " ")
    return "\(kind) \(rest)"
}
