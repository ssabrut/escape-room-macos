import SwiftUI

// MARK: - Layout constants

private let roomTileCount: CGFloat = 50   // default widthTiles / heightTiles
private let pixelSize:     CGFloat = 16   // one "pixel block" in points
private let roomSize:      CGFloat = roomTileCount * pixelSize  // 160 pt per room cell
private let mapPadding:    CGFloat = 32
private let corridorWidth: CGFloat = 10

// MARK: - Dungeon map (scrollable overview)

struct DungeonMapView: View {
    let world: RenderWorld

    private var totalW: CGFloat {
        let cols = CGFloat(world.grid.cols)
        return cols * roomSize + mapPadding * 2
    }
    private var totalH: CGFloat {
        let rows = CGFloat(world.grid.rows)
        return rows * roomSize + mapPadding * 2
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in drawCorridors(ctx: ctx) }
                    .frame(width: totalW, height: totalH)

                ForEach(world.rooms) { room in
                    let cx: CGFloat = mapPadding + CGFloat(room.col) * roomSize + roomSize / 2
                    let cy: CGFloat = mapPadding + CGFloat(room.row) * roomSize + roomSize / 2
                    RoomCanvasView(room: room)
                        .frame(width: roomSize - 4, height: roomSize - 4)
                        .position(x: cx, y: cy)
                }
            }
            .frame(width: totalW, height: totalH)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.08))
    }

    private func drawCorridors(ctx: GraphicsContext) {
        for corridor in world.corridors {
            guard
                let from = world.rooms.first(where: { $0.id == corridor.fromRoom }),
                let to   = world.rooms.first(where: { $0.id == corridor.toRoom })
            else { continue }
            let p1 = roomCenter(from)
            let p2 = roomCenter(to)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            ctx.stroke(path, with: .color(Color(white: 0.28)), lineWidth: corridorWidth)
        }
    }

    private func roomCenter(_ room: RenderWorld.RenderRoom) -> CGPoint {
        let x: CGFloat = mapPadding + CGFloat(room.col) * roomSize + roomSize / 2
        let y: CGFloat = mapPadding + CGFloat(room.row) * roomSize + roomSize / 2
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Single room canvas

private struct RoomCanvasView: View {
    let room: RenderWorld.RenderRoom

    var body: some View {
        Canvas { ctx, size in
            let p = pixelSize
            let tilesW = CGFloat(room.widthTiles  ?? Int(roomTileCount))
            let tilesH = CGFloat(room.heightTiles ?? Int(roomTileCount))
            let scaleX = size.width  / tilesW
            let scaleY = size.height / tilesH

            drawFloor(ctx: ctx, size: size, p: p)
            drawWalls(ctx: ctx, size: size, p: p)
            drawDoors(ctx: ctx, size: size, scaleX: scaleX, scaleY: scaleY, p: p)
            drawObjects(ctx: ctx, scaleX: scaleX, scaleY: scaleY, p: p)
            if room.isCurrentRoom {
                drawPlayer(ctx: ctx, size: size, p: p)
            }
        }
        .drawingGroup()
        .overlay(alignment: .center) {
            if room.isCurrentRoom {
                Rectangle().strokeBorder(Color.green, lineWidth: 2)
            }
        }
    }

    // MARK: Floor — checkerboard

    private func drawFloor(ctx: GraphicsContext, size: CGSize, p: CGFloat) {
        let cols = Int(size.width  / p) + 1
        let rows = Int(size.height / p) + 1
        let light = Color(red: 0.42, green: 0.36, blue: 0.28)
        let dark  = Color(red: 0.36, green: 0.30, blue: 0.23)
        for r in 0..<rows {
            for c in 0..<cols {
                let color = (r + c) % 2 == 0 ? light : dark
                ctx.fill(Path(CGRect(x: CGFloat(c) * p, y: CGFloat(r) * p, width: p, height: p)),
                         with: .color(color))
            }
        }
    }

    // MARK: Walls — stone border

    private func drawWalls(ctx: GraphicsContext, size: CGSize, p: CGFloat) {
        let stone  = Color(red: 0.30, green: 0.28, blue: 0.26)
        let mortar = Color(red: 0.20, green: 0.18, blue: 0.16)
        let w = size.width
        let h = size.height

        // Fill perimeter with stone
        ctx.fill(Path(CGRect(x: 0,     y: 0,     width: w,  height: p * 2)), with: .color(stone))
        ctx.fill(Path(CGRect(x: 0,     y: h - p, width: w,  height: p)),     with: .color(stone))
        ctx.fill(Path(CGRect(x: 0,     y: 0,     width: p,  height: h)),     with: .color(stone))
        ctx.fill(Path(CGRect(x: w - p, y: 0,     width: p,  height: h)),     with: .color(stone))

        // Mortar lines on top wall
        for c in stride(from: 0.0, to: w, by: p * 2) {
            ctx.fill(Path(CGRect(x: c, y: p * 0.9, width: p * 0.1, height: p * 0.2)), with: .color(mortar))
        }
        // Shadow under top wall
        ctx.fill(Path(CGRect(x: p, y: p * 2, width: w - p * 2, height: p * 0.4)),
                 with: .color(.black.opacity(0.4)))
    }

    // MARK: Doors — cut gaps in walls, tinted by locked state

    private func drawDoors(ctx: GraphicsContext, size: CGSize,
                           scaleX: CGFloat, scaleY: CGFloat, p: CGFloat) {
        let doors = room.doors ?? []
        let floor = Color(red: 0.50, green: 0.43, blue: 0.34)
        let w = size.width
        let h = size.height
        let doorSpan = p * 2.5

        for door in doors {
            let locked = door.locked
            let doorColor = locked ? Color(red: 0.55, green: 0.18, blue: 0.12) : floor
            let tx = CGFloat(door.tileX) * scaleX
            let ty = CGFloat(door.tileY) * scaleY

            switch door.direction {
            case "north":
                ctx.fill(Path(CGRect(x: tx - doorSpan / 2, y: 0, width: doorSpan, height: p * 2)),
                         with: .color(doorColor))
            case "south":
                ctx.fill(Path(CGRect(x: tx - doorSpan / 2, y: h - p, width: doorSpan, height: p)),
                         with: .color(doorColor))
            case "west":
                ctx.fill(Path(CGRect(x: 0, y: ty - doorSpan / 2, width: p, height: doorSpan)),
                         with: .color(doorColor))
            case "east":
                ctx.fill(Path(CGRect(x: w - p, y: ty - doorSpan / 2, width: p, height: doorSpan)),
                         with: .color(doorColor))
            default: break
            }
        }
    }

    // MARK: Objects — all objects placed at tileX/tileY

    private func drawObjects(ctx: GraphicsContext, scaleX: CGFloat, scaleY: CGFloat, p: CGFloat) {
        for obj in room.objects {
            guard let tx = obj.tileX, let ty = obj.tileY else { continue }
            let cx = CGFloat(tx) * scaleX + scaleX / 2
            let cy = CGFloat(ty) * scaleY + scaleY / 2

            // Try cached sprite image first
            if let cgImage = SpriteCache.shared.image(for: obj.id) {
                let size = p * 3
                let rect = CGRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
                ctx.draw(Image(cgImage, scale: 1, label: Text(obj.id)),
                         in: rect)
                continue
            }

            let sprite = obj.sprite ?? "item"
            drawSprite(ctx: ctx, sprite: sprite, state: obj.state,
                       takeable: obj.takeable, cx: cx, cy: cy, p: p)
        }
    }

    private func drawSprite(ctx: GraphicsContext, sprite: String, state: String,
                            takeable: Bool, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        switch sprite {
        case "chest":
            drawChest(ctx: ctx, cx: cx, cy: cy, state: state, p: p)
        case "key":
            drawKey(ctx: ctx, cx: cx, cy: cy, p: p)
        case "item":
            drawItem(ctx: ctx, cx: cx, cy: cy, takeable: takeable, p: p)
        case "table":
            drawTable(ctx: ctx, cx: cx, cy: cy, p: p)
        case "bed":
            drawBed(ctx: ctx, cx: cx, cy: cy, p: p)
        case "bookshelf":
            drawBookshelf(ctx: ctx, cx: cx, cy: cy, p: p)
        case "mirror":
            drawMirror(ctx: ctx, cx: cx, cy: cy, p: p)
        case "chair":
            drawChair(ctx: ctx, cx: cx, cy: cy, p: p)
        case "painting":
            drawPainting(ctx: ctx, cx: cx, cy: cy, p: p)
        case "floor_detail":
            drawFloorDetail(ctx: ctx, cx: cx, cy: cy, p: p)
        case "wall_detail":
            drawWallDetail(ctx: ctx, cx: cx, cy: cy, p: p)
        case "artifact":
            drawArtifact(ctx: ctx, cx: cx, cy: cy, p: p)
        case "light":
            drawLight(ctx: ctx, cx: cx, cy: cy, p: p)
        default:
            drawItem(ctx: ctx, cx: cx, cy: cy, takeable: takeable, p: p)
        }
    }

    // MARK: Sprite primitives

    private func drawChest(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, state: String, p: CGFloat) {
        let body: Color
        let lid: Color
        switch state {
        case "locked":
            body = Color(red: 0.50, green: 0.18, blue: 0.12)
            lid  = Color(red: 0.65, green: 0.28, blue: 0.18)
        case "unlocked":
            body = Color(red: 0.18, green: 0.48, blue: 0.22)
            lid  = Color(red: 0.28, green: 0.62, blue: 0.32)
        default:
            body = Color(red: 0.38, green: 0.28, blue: 0.18)
            lid  = Color(red: 0.52, green: 0.40, blue: 0.26)
        }
        let bw = p * 3; let bh = p * 2
        let x = cx - bw / 2; let y = cy - bh / 2
        ctx.fill(Path(CGRect(x: x + 1, y: y + bh, width: bw, height: p * 0.4)),
                 with: .color(.black.opacity(0.3)))
        ctx.fill(Path(CGRect(x: x, y: y + p * 0.8, width: bw, height: bh - p * 0.8)),
                 with: .color(body))
        ctx.fill(Path(CGRect(x: x, y: y, width: bw, height: p * 0.8)),
                 with: .color(lid))
        ctx.fill(Path(CGRect(x: x + p * 0.4, y: y + p * 0.15, width: bw - p * 0.8, height: p * 0.2)),
                 with: .color(.white.opacity(0.22)))
        ctx.fill(Path(CGRect(x: cx - p * 0.3, y: y + p * 0.55, width: p * 0.6, height: p * 0.5)),
                 with: .color(Color(white: 0.85)))
    }

    private func drawKey(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        // Ring
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.8, y: cy - p * 0.8, width: p * 1.2, height: p * 1.2)),
                 with: .color(Color(red: 0.80, green: 0.68, blue: 0.22)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.55, y: cy - p * 0.55, width: p * 0.7, height: p * 0.7)),
                 with: .color(Color(red: 0.36, green: 0.30, blue: 0.23)))
        // Shaft
        ctx.fill(Path(CGRect(x: cx, y: cy - p * 0.15, width: p * 1.4, height: p * 0.3)),
                 with: .color(Color(red: 0.80, green: 0.68, blue: 0.22)))
        // Teeth
        ctx.fill(Path(CGRect(x: cx + p * 0.8, y: cy + p * 0.15, width: p * 0.25, height: p * 0.35)),
                 with: .color(Color(red: 0.80, green: 0.68, blue: 0.22)))
        ctx.fill(Path(CGRect(x: cx + p * 1.1, y: cy + p * 0.15, width: p * 0.25, height: p * 0.25)),
                 with: .color(Color(red: 0.80, green: 0.68, blue: 0.22)))
    }

    private func drawItem(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, takeable: Bool, p: CGFloat) {
        let color: Color = takeable
            ? Color(red: 0.70, green: 0.60, blue: 0.20)
            : Color(red: 0.40, green: 0.38, blue: 0.35)
        let s = p * 0.9
        ctx.fill(Path(CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)),
                 with: .color(color))
        if takeable {
            ctx.fill(Path(CGRect(x: cx - s / 2 + 1, y: cy - s / 2 + 1, width: s * 0.4, height: s * 0.4)),
                     with: .color(.white.opacity(0.3)))
        }
    }

    private func drawTable(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let wood = Color(red: 0.42, green: 0.28, blue: 0.18)
        let top  = Color(red: 0.52, green: 0.36, blue: 0.24)
        ctx.fill(Path(CGRect(x: cx - p * 1.5, y: cy - p * 0.9, width: p * 3, height: p * 1.8)),
                 with: .color(top))
        ctx.fill(Path(CGRect(x: cx - p * 1.5, y: cy - p * 0.9, width: p * 3, height: p * 0.25)),
                 with: .color(wood))
        ctx.fill(Path(CGRect(x: cx - p * 1.5, y: cy + p * 0.65, width: p * 3, height: p * 0.25)),
                 with: .color(wood))
        // Bloodstain hint
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.4, y: cy - p * 0.3, width: p * 0.8, height: p * 0.5)),
                 with: .color(Color(red: 0.45, green: 0.10, blue: 0.10).opacity(0.6)))
    }

    private func drawBed(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let frame  = Color(red: 0.32, green: 0.24, blue: 0.18)
        let pillow = Color(red: 0.55, green: 0.52, blue: 0.48)
        ctx.fill(Path(CGRect(x: cx - p * 1.2, y: cy - p, width: p * 2.4, height: p * 2)), with: .color(frame))
        ctx.fill(Path(CGRect(x: cx - p * 1.0, y: cy - p * 0.8, width: p * 2.0, height: p * 1.6)),
                 with: .color(Color(red: 0.48, green: 0.38, blue: 0.30)))
        ctx.fill(Path(CGRect(x: cx - p * 0.8, y: cy - p * 0.75, width: p * 1.0, height: p * 0.7)),
                 with: .color(pillow))
    }

    private func drawBookshelf(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let shelf = Color(red: 0.35, green: 0.25, blue: 0.15)
        ctx.fill(Path(CGRect(x: cx - p * 1.3, y: cy - p, width: p * 2.6, height: p * 2)), with: .color(shelf))
        let bookColors: [Color] = [
            Color(red: 0.6, green: 0.15, blue: 0.15),
            Color(red: 0.15, green: 0.35, blue: 0.55),
            Color(red: 0.55, green: 0.50, blue: 0.15),
            Color(red: 0.20, green: 0.45, blue: 0.20),
        ]
        for (i, c) in bookColors.enumerated() {
            let bx = cx - p * 1.1 + CGFloat(i) * p * 0.6
            ctx.fill(Path(CGRect(x: bx, y: cy - p * 0.85, width: p * 0.45, height: p * 1.5)),
                     with: .color(c))
        }
    }

    private func drawMirror(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        ctx.fill(Path(CGRect(x: cx - p * 0.9, y: cy - p * 1.1, width: p * 1.8, height: p * 2.2)),
                 with: .color(Color(red: 0.28, green: 0.22, blue: 0.18)))
        ctx.fill(Path(CGRect(x: cx - p * 0.7, y: cy - p * 0.9, width: p * 1.4, height: p * 1.8)),
                 with: .color(Color(red: 0.55, green: 0.65, blue: 0.70).opacity(0.6)))
        ctx.fill(Path(CGRect(x: cx - p * 0.5, y: cy - p * 0.7, width: p * 0.4, height: p * 0.4)),
                 with: .color(.white.opacity(0.4)))
    }

    private func drawChair(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let wood = Color(red: 0.38, green: 0.26, blue: 0.16)
        let seat = Color(red: 0.50, green: 0.22, blue: 0.18)
        ctx.fill(Path(CGRect(x: cx - p * 0.8, y: cy - p * 1.0, width: p * 1.6, height: p * 0.35)),
                 with: .color(wood))
        ctx.fill(Path(CGRect(x: cx - p * 0.7, y: cy - p * 0.65, width: p * 1.4, height: p * 1.1)),
                 with: .color(seat))
        ctx.fill(Path(CGRect(x: cx - p * 0.7, y: cy + p * 0.45, width: p * 0.25, height: p * 0.55)),
                 with: .color(wood))
        ctx.fill(Path(CGRect(x: cx + p * 0.45, y: cy + p * 0.45, width: p * 0.25, height: p * 0.55)),
                 with: .color(wood))
    }

    private func drawPainting(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        ctx.fill(Path(CGRect(x: cx - p * 1.0, y: cy - p * 0.75, width: p * 2.0, height: p * 1.5)),
                 with: .color(Color(red: 0.32, green: 0.24, blue: 0.16)))
        ctx.fill(Path(CGRect(x: cx - p * 0.8, y: cy - p * 0.55, width: p * 1.6, height: p * 1.1)),
                 with: .color(Color(red: 0.60, green: 0.48, blue: 0.30)))
        ctx.fill(Path(CGRect(x: cx - p * 0.3, y: cy - p * 0.50, width: p * 0.6, height: p * 0.75)),
                 with: .color(Color(red: 0.78, green: 0.68, blue: 0.55)))
    }

    private func drawFloorDetail(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let stain = Color(red: 0.30, green: 0.08, blue: 0.08).opacity(0.65)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.6, y: cy - p * 0.35, width: p * 1.2, height: p * 0.7)),
                 with: .color(stain))
        ctx.fill(Path(ellipseIn: CGRect(x: cx + p * 0.1, y: cy + p * 0.2, width: p * 0.5, height: p * 0.3)),
                 with: .color(stain))
    }

    private func drawWallDetail(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        let scratch = Color(white: 0.55).opacity(0.5)
        for i in 0..<3 {
            let dy = CGFloat(i) * p * 0.4 - p * 0.4
            var path = Path()
            path.move(to: CGPoint(x: cx - p * 0.6, y: cy + dy))
            path.addLine(to: CGPoint(x: cx + p * 0.5, y: cy + dy + p * 0.2))
            ctx.stroke(path, with: .color(scratch), lineWidth: 1)
        }
    }

    private func drawArtifact(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        ctx.fill(Path(CGRect(x: cx - p * 0.5, y: cy - p * 0.65, width: p, height: p * 1.3)),
                 with: .color(Color(red: 0.55, green: 0.50, blue: 0.38)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.4, y: cy - p * 0.75, width: p * 0.8, height: p * 0.55)),
                 with: .color(Color(red: 0.65, green: 0.60, blue: 0.45)))
    }

    private func drawLight(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, p: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.5, y: cy - p * 0.5, width: p, height: p)),
                 with: .color(Color(red: 0.90, green: 0.82, blue: 0.40).opacity(0.3)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - p * 0.3, y: cy - p * 0.3, width: p * 0.6, height: p * 0.6)),
                 with: .color(Color(red: 0.95, green: 0.90, blue: 0.60)))
    }

    // MARK: Player

    private func drawPlayer(ctx: GraphicsContext, size: CGSize, p: CGFloat) {
        let px = size.width / 2 - p * 0.75
        let py = size.height * 0.62
        ctx.fill(Path(CGRect(x: px + p * 0.1, y: py + p * 2.2, width: p * 1.1, height: p * 0.25)),
                 with: .color(.black.opacity(0.35)))
        ctx.fill(Path(CGRect(x: px, y: py + p * 0.8, width: p * 1.5, height: p * 1.4)),
                 with: .color(.green))
        ctx.fill(Path(CGRect(x: px + p * 0.2, y: py, width: p * 1.1, height: p * 0.8)),
                 with: .color(Color(red: 0.88, green: 0.72, blue: 0.58)))
    }
}

// MARK: - Legend

struct MapLegendView: View {
    var body: some View {
        HStack(spacing: 20) {
            LegendItem(color: Color(red: 0.50, green: 0.18, blue: 0.12), label: "Locked")
            LegendItem(color: Color(red: 0.18, green: 0.48, blue: 0.22), label: "Unlocked")
            LegendItem(color: .green, label: "You", isCircle: true)
        }
        .padding(.horizontal)
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    var isCircle: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if isCircle {
                Circle().fill(color).frame(width: 10, height: 10)
            } else {
                Rectangle().fill(color).frame(width: 10, height: 10)
            }
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(WoodTheme.frameDark.opacity(0.75))
        }
    }
}
