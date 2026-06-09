import SwiftUI

// MARK: - Constants

private let cellSize: CGFloat = 100
private let corridorThickness: CGFloat = 8
private let mapPadding: CGFloat = 24

// MARK: - Dungeon map

struct DungeonMapView: View {
    let world: RenderWorld

    private var mapWidth: CGFloat {
        let cols = CGFloat(world.grid.cols)
        return cols * cellSize + mapPadding * 2
    }
    private var mapHeight: CGFloat {
        let rows = CGFloat(world.grid.rows)
        return rows * cellSize + mapPadding * 2
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Background grid dots
                Canvas { ctx, size in
                    drawCorridors(ctx: ctx)
                }
                .frame(width: mapWidth, height: mapHeight)

                // Room tiles on top
                ForEach(world.rooms) { room in
                    let rx: CGFloat = mapPadding + CGFloat(room.col) * cellSize + cellSize / 2
                    let ry: CGFloat = mapPadding + CGFloat(room.row) * cellSize + cellSize / 2
                    RoomTileView(room: room)
                        .frame(width: cellSize - 8, height: cellSize - 8)
                        .position(x: rx, y: ry)
                }
            }
            .frame(width: mapWidth, height: mapHeight)
        }
    }

    // Draws corridor lines between connected rooms
    private func drawCorridors(ctx: GraphicsContext) {
        for corridor in world.corridors {
            guard
                let from = world.rooms.first(where: { $0.id == corridor.fromRoom }),
                let to   = world.rooms.first(where: { $0.id == corridor.toRoom })
            else { continue }

            let p1 = center(of: from)
            let p2 = center(of: to)

            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            ctx.stroke(path, with: .color(Color(white: 0.35)), lineWidth: corridorThickness)
        }
    }

    private func center(of room: RenderWorld.RenderRoom) -> CGPoint {
        let x: CGFloat = mapPadding + CGFloat(room.col) * cellSize + cellSize / 2
        let y: CGFloat = mapPadding + CGFloat(room.row) * cellSize + cellSize / 2
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Individual room tile

private struct RoomTileView: View {
    let room: RenderWorld.RenderRoom

    private var interactableCount: Int {
        room.objects.filter(\.interactable).count
    }

    private var solvedCount: Int {
        room.objects.filter { $0.interactable && $0.state == "unlocked" }.count
    }

    var body: some View {
        ZStack {
            // Tile background
            Rectangle()
                .fill(tileColor)
                .overlay(
                    Rectangle()
                        .strokeBorder(borderColor, lineWidth: room.isCurrentRoom ? 3 : 1)
                )

            VStack(spacing: 4) {
                // Room label
                Text(room.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // Object pip row
                HStack(spacing: 3) {
                    ForEach(room.objects.filter(\.interactable)) { obj in
                        ObjectPip(state: obj.state)
                    }
                }

                // Connection arrows
                HStack(spacing: 6) {
                    ForEach(room.connections, id: \.self) { dir in
                        Text(arrowFor(dir))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.7))
                    }
                }
            }
            .padding(6)
        }
    }

    private var tileColor: Color {
        if room.isCurrentRoom { return Color(red: 0.3, green: 0.55, blue: 0.35) }
        return Color(red: 0.15, green: 0.15, blue: 0.25)
    }

    private var borderColor: Color {
        room.isCurrentRoom ? .green : Color(white: 0.4)
    }

    private func arrowFor(_ direction: String) -> String {
        switch direction {
        case "north": return "↑"
        case "south": return "↓"
        case "east":  return "→"
        case "west":  return "←"
        default:      return "•"
        }
    }
}

// MARK: - Object state pip

private struct ObjectPip: View {
    let state: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(pipColor)
            .frame(width: 10, height: 10)
    }

    private var pipColor: Color {
        switch state {
        case "locked":   return .red
        case "unlocked": return .green
        default:         return Color(white: 0.55)
        }
    }
}

// MARK: - Legend

struct MapLegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: Color(red: 0.3, green: 0.55, blue: 0.35), label: "Current room")
            LegendItem(color: Color(red: 0.15, green: 0.15, blue: 0.25), label: "Other room")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 10, height: 10)
                Text("Locked").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 10, height: 10)
                Text("Solved").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 14, height: 14)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
        }
    }
}
