import Foundation

// MARK: - Render models (decoded from /render in the API response)

struct RenderWorld: Codable {
    let grid: GridInfo
    let rooms: [RenderRoom]
    let corridors: [Corridor]
    let party: Party

    struct GridInfo: Codable {
        let cols: Int
        let rows: Int
    }

    struct RenderRoom: Codable, Identifiable {
        let id: String
        let label: String
        let col: Int
        let row: Int
        let isCurrentRoom: Bool
        let connections: [String]
        let objects: [RoomObject]
    }

    struct RoomObject: Codable, Identifiable {
        let id: String
        let state: String
        let interacted: Bool
        let takeable: Bool
        let interactable: Bool
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
}
