//
//  MainMenuView.swift
//  escape-room
//
//  Created by Michael Eko on 10/06/26.
//

import SwiftUI

// MARK: - Main menu

struct MainMenuView: View {
    let onNewGame: () -> Void
    let onLoadGame: () -> Void
    let onSettings: () -> Void
    let onCredits: () -> Void
    let onExit: () -> Void

    @StateObject private var audio = AudioManager.shared
    @State private var hoveredItem: CaseMenuItem? = .newGame

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height

            ZStack {
                CaseDeskBackground()

                CaseFileBoard(
                    isWide: isWide,
                    hoveredItem: $hoveredItem,
                    onNewGame: onNewGame,
                    onLoadGame: onLoadGame,
                    onSettings: onSettings,
                    onCredits: onCredits,
                    onExit: onExit
                )
                .frame(
                    width: min(geo.size.width * 0.92, 1100),
                    height: min(geo.size.height * 0.88, 620)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        MuteButton(isMuted: audio.isMuted, action: audio.toggleMute)
                            .padding(.top, 16)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            audio.playMusic(named: "main_theme")
        }
        .onDisappear {
            audio.stopMusic()
        }
    }
}

// MARK: - Case menu items

enum CaseMenuItem {
    case newGame, loadCase, settings, credits, exit

    var title: String {
        switch self {
        case .newGame: return "NEW GAME"
        case .loadCase: return "LOAD CASE"
        case .settings: return "SETTINGS"
        case .credits: return "CREDITS"
        case .exit: return "EXIT GAME"
        }
    }
}

// MARK: - Desk background

/// Dark wood desk surface behind the open case file.
struct CaseDeskBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.11, blue: 0.05),
                Color(red: 0.12, green: 0.06, blue: 0.03)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Case file board

private struct CaseFileBoard: View {
    let isWide: Bool
    @Binding var hoveredItem: CaseMenuItem?
    let onNewGame: () -> Void
    let onLoadGame: () -> Void
    let onSettings: () -> Void
    let onCredits: () -> Void
    let onExit: () -> Void

    private let folderColor = Color(red: 0.78, green: 0.64, blue: 0.42)
    private let folderShadow = Color(red: 0.55, green: 0.42, blue: 0.25)

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 6) {
                    EvidenceBoardPage()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    CaseMenuPage(
                        hoveredItem: $hoveredItem,
                        onNewGame: onNewGame,
                        onLoadGame: onLoadGame,
                        onSettings: onSettings,
                        onCredits: onCredits,
                        onExit: onExit
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    EvidenceBoardPage()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    CaseMenuPage(
                        hoveredItem: $hoveredItem,
                        onNewGame: onNewGame,
                        onLoadGame: onLoadGame,
                        onSettings: onSettings,
                        onCredits: onCredits,
                        onExit: onExit
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(folderColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(folderShadow, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)
    }
}

// MARK: - Left page: evidence board

private let evidencePortraits: [(name: String, asset: String)] = [
    ("Theo Nakamura", "theo_nakamura"),
    ("Riley Sato", "riley_sato"),
    ("Mara Vance", "mara_vance"),
    ("Alex Quinn", "alex_quinn"),
]

private let evidenceNotes = [
    "Missing since Oct 12",
    "Last seen at dock",
    "Case: Red Car",
    "Clue #3",
]

private struct EvidenceBoardPage: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.93, green: 0.89, blue: 0.78))
                .overlay(NotebookLinesOverlay())

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                // Polaroid photos in a 2x2 grid with slight rotation.
                PolaroidPhoto(name: evidencePortraits[0].name, asset: evidencePortraits[0].asset, pinColor: Color(red: 0.78, green: 0.16, blue: 0.14))
                    .frame(width: w * 0.34, height: w * 0.34 * 1.18)
                    .rotationEffect(.degrees(-4))
                    .position(x: w * 0.27, y: h * 0.27)

                PolaroidPhoto(name: evidencePortraits[1].name, asset: evidencePortraits[1].asset, pinColor: Color(red: 0.20, green: 0.55, blue: 0.25))
                    .frame(width: w * 0.34, height: w * 0.34 * 1.18)
                    .rotationEffect(.degrees(3))
                    .position(x: w * 0.73, y: h * 0.24)

                PolaroidPhoto(name: evidencePortraits[2].name, asset: evidencePortraits[2].asset, pinColor: Color(red: 0.20, green: 0.55, blue: 0.25))
                    .frame(width: w * 0.34, height: w * 0.34 * 1.18)
                    .rotationEffect(.degrees(2))
                    .position(x: w * 0.25, y: h * 0.70)

                PolaroidPhoto(name: evidencePortraits[3].name, asset: evidencePortraits[3].asset, pinColor: Color(red: 0.78, green: 0.16, blue: 0.14))
                    .frame(width: w * 0.34, height: w * 0.34 * 1.18)
                    .rotationEffect(.degrees(-3))
                    .position(x: w * 0.74, y: h * 0.72)

                // Sticky notes scattered between the photos.
                StickyNote(text: evidenceNotes[0], color: Color(red: 0.74, green: 0.78, blue: 0.80))
                    .frame(width: w * 0.20, height: w * 0.16)
                    .rotationEffect(.degrees(4))
                    .position(x: w * 0.58, y: h * 0.10)

                StickyNote(text: evidenceNotes[1], color: Color(red: 0.78, green: 0.78, blue: 0.72))
                    .frame(width: w * 0.20, height: w * 0.16)
                    .rotationEffect(.degrees(-3))
                    .position(x: w * 0.50, y: h * 0.40)

                StickyNote(text: evidenceNotes[2], color: Color(red: 0.96, green: 0.85, blue: 0.55))
                    .frame(width: w * 0.22, height: w * 0.16)
                    .rotationEffect(.degrees(-2))
                    .position(x: w * 0.48, y: h * 0.62)

                StickyNote(text: evidenceNotes[3], color: Color(red: 0.80, green: 0.80, blue: 0.78))
                    .frame(width: w * 0.20, height: w * 0.16)
                    .rotationEffect(.degrees(3))
                    .position(x: w * 0.50, y: h * 0.90)

                // Red string connecting clues, drawn beneath the pins.
                EvidenceStringOverlay()
            }
            .padding(18)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Faint horizontal ruled lines, mimicking lined notebook paper.
struct NotebookLinesOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let spacing: CGFloat = 26
                var y: CGFloat = spacing
                while y < geo.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(Color(red: 0.55, green: 0.45, blue: 0.30).opacity(0.12), lineWidth: 1)
        }
    }
}

/// Faint red strings linking evidence pins, for the classic detective-board look.
private struct EvidenceStringOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                path.move(to: CGPoint(x: w * 0.27, y: h * 0.27))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.40))
                path.addLine(to: CGPoint(x: w * 0.73, y: h * 0.24))
                path.move(to: CGPoint(x: w * 0.25, y: h * 0.70))
                path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.40))
                path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.72))
            }
            .stroke(Color(red: 0.70, green: 0.12, blue: 0.10).opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Polaroid photo

private struct PolaroidPhoto: View {
    let name: String
    let asset: String
    let pinColor: Color

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.85)

                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(6)

            Spacer(minLength: 4)
        }
        .padding(6)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
        .overlay(
            Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, x: 1, y: 3)
        .overlay(alignment: .top) {
            Circle()
                .fill(pinColor)
                .frame(width: 12, height: 12)
                .overlay(Circle().fill(Color.white.opacity(0.35)).frame(width: 4, height: 4).offset(x: -2, y: -2))
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
                .offset(y: -6)
        }
        .accessibilityLabel(name)
    }
}

// MARK: - Sticky note

private struct StickyNote: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
            .shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 3)
            .overlay(alignment: .top) {
                Circle()
                    .fill(Color(red: 0.20, green: 0.55, blue: 0.25))
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .offset(y: -4)
            }
    }
}

// MARK: - Right page: menu

private struct CaseMenuPage: View {
    @Binding var hoveredItem: CaseMenuItem?
    let onNewGame: () -> Void
    let onLoadGame: () -> Void
    let onSettings: () -> Void
    let onCredits: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.96, green: 0.93, blue: 0.84))

            VStack(spacing: 0) {
                // Confidential stamp + folded corner
                HStack {
                    Text("CONFIDENTIAL")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.4), lineWidth: 1.5)
                        )
                        .rotationEffect(.degrees(-3))

                    Spacer()
                }
                .padding(.top, 22)
                .padding(.horizontal, 22)

                // Project Obituary title stamp
                ProjectTitleStamp()
                    .padding(.top, 14)
                    .padding(.horizontal, 28)

                Spacer(minLength: 18)

                // Menu list
                VStack(spacing: 14) {
                    CaseMenuRow(item: .newGame, hoveredItem: $hoveredItem, action: onNewGame)
                    CaseMenuRow(item: .loadCase, hoveredItem: $hoveredItem, action: onLoadGame)
                    CaseMenuRow(item: .settings, hoveredItem: $hoveredItem, action: onSettings)
                    CaseMenuRow(item: .credits, hoveredItem: $hoveredItem, action: onCredits)
                    CaseMenuRow(item: .exit, hoveredItem: $hoveredItem, action: onExit)
                }
                .padding(.horizontal, 36)

                Spacer(minLength: 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            FoldedCorner()
                .padding(.top, 0)
                .padding(.trailing, 0)
        }
    }
}

/// The red rotated "PROJECT: OBITUARY" stamp.
private struct ProjectTitleStamp: View {
    var body: some View {
        Text("PROJECT:\nOBITUARY")
            .font(.system(size: 36, weight: .black, design: .rounded))
            .multilineTextAlignment(.leading)
            .foregroundColor(Color(red: 0.74, green: 0.14, blue: 0.12))
            .lineSpacing(2)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(red: 0.74, green: 0.14, blue: 0.12), lineWidth: 4)
            )
            .rotationEffect(.degrees(-3))
            .opacity(0.92)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small folded paper corner in the top-right of the right page.
private struct FoldedCorner: View {
    var body: some View {
        Path { path in
            let size: CGFloat = 36
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size, y: 0))
            path.addLine(to: CGPoint(x: size, y: size))
            path.closeSubpath()
        }
        .fill(Color(red: 0.85, green: 0.81, blue: 0.70))
        .frame(width: 36, height: 36)
        .shadow(color: .black.opacity(0.15), radius: 2, x: -1, y: 1)
    }
}

// MARK: - Menu row

private struct CaseMenuRow: View {
    let item: CaseMenuItem
    @Binding var hoveredItem: CaseMenuItem?
    let action: () -> Void

    private var isHighlighted: Bool { hoveredItem == item }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
                    .opacity(isHighlighted ? 1 : 0)

                Text("[\(item.title)]")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted ? Color(red: 0.99, green: 0.97, blue: 0.88) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItem = hovering ? item : (hoveredItem == item ? nil : hoveredItem)
        }
    }
}

// MARK: - Mute button

private struct MuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(WoodTheme.title)
                .padding(10)
                .background(
                    Circle()
                        .fill(WoodTheme.frame)
                        .overlay(Circle().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme palette

enum WoodTheme {
    static let frame = Color(red: 0.55, green: 0.33, blue: 0.16)
    static let frameDark = Color(red: 0.36, green: 0.20, blue: 0.09)
    static let parchment = Color(red: 0.91, green: 0.80, blue: 0.58)
    static let ink = Color(red: 0.55, green: 0.20, blue: 0.18)
    static let title = Color(red: 0.93, green: 0.82, blue: 0.58)
    static let leaf = Color(red: 0.40, green: 0.70, blue: 0.30)
}

// MARK: - Wood button

struct WoodButton: View {
    let label: String
    let systemImage: String
    let iconColor: Color
    let action: () -> Void
    var isEnabled: Bool = true

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(WoodTheme.ink)
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(WoodTheme.parchment)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WoodTheme.frame, lineWidth: 5)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: isPressed ? 1 : 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    MainMenuView(onNewGame: {}, onLoadGame: {}, onSettings: {}, onCredits: {}, onExit: {})
}
