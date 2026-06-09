import Foundation

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
}
