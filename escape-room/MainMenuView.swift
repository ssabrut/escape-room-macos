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

    @StateObject private var audio = AudioManager.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SkyBackground()

                VStack(spacing: 36) {
                    WoodSignTitle(title: "ESCAPE\nROOM")
                        .frame(maxWidth: min(geo.size.width * 0.85, 480))

                    HStack(spacing: 16) {
                        WoodButton(label: "NEW", systemImage: "leaf.fill", iconColor: .green, action: onNewGame)
                        WoodButton(label: "LOAD", systemImage: "scroll.fill", iconColor: .pink, action: onLoadGame)
                    }
                    .frame(maxWidth: min(geo.size.width * 0.85, 480))
                }
                .frame(width: geo.size.width, height: geo.size.height)

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
    static let plankLight = Color(red: 0.72, green: 0.47, blue: 0.24)
    static let plankDark = Color(red: 0.45, green: 0.27, blue: 0.12)
    static let frame = Color(red: 0.55, green: 0.33, blue: 0.16)
    static let frameDark = Color(red: 0.36, green: 0.20, blue: 0.09)
    static let parchment = Color(red: 0.91, green: 0.80, blue: 0.58)
    static let ink = Color(red: 0.55, green: 0.20, blue: 0.18)
    static let title = Color(red: 0.93, green: 0.82, blue: 0.58)
    static let leaf = Color(red: 0.40, green: 0.70, blue: 0.30)
}

// MARK: - Sky background

struct SkyBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.18, blue: 0.45),
                        Color(red: 0.16, green: 0.42, blue: 0.78),
                        Color(red: 0.45, green: 0.74, blue: 0.93)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Stars scattered in the upper portion of the sky
                ForEach(0..<24, id: \.self) { i in
                    let seed = CGFloat(i)
                    let x = (seed * 73.0).truncatingRemainder(dividingBy: geo.size.width)
                    let y = (seed * 41.0).truncatingRemainder(dividingBy: geo.size.height * 0.45)
                    Image(systemName: "sparkle")
                        .font(.system(size: i % 3 == 0 ? 10 : 6))
                        .foregroundColor(.white.opacity(i % 2 == 0 ? 0.85 : 0.5))
                        .position(x: x, y: y)
                }

                // Clouds
                CloudShape()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 160, height: 60)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.18)

                CloudShape()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 120, height: 46)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.30)
            }
        }
    }
}

private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: 0, y: h * 0.35, width: w * 0.45, height: h * 0.65))
        path.addEllipse(in: CGRect(x: w * 0.22, y: 0, width: w * 0.6, height: h * 0.85))
        path.addEllipse(in: CGRect(x: w * 0.5, y: h * 0.35, width: w * 0.5, height: h * 0.65))
        path.addRect(CGRect(x: w * 0.1, y: h * 0.45, width: w * 0.8, height: h * 0.55))
        return path
    }
}

// MARK: - Wood sign title

struct WoodSignTitle: View {
    let title: String
    var fontSize: CGFloat = 40
    var aspectRatio: CGFloat = 2.1

    var body: some View {
        ZStack {
            // Outer rope-tied frame
            RoundedRectangle(cornerRadius: 18)
                .fill(WoodTheme.frame)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(WoodTheme.frameDark, lineWidth: 6)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)

            // Wood plank rows
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(WoodTheme.plankLight)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(WoodTheme.plankDark, lineWidth: 2)
                        )
                        .frame(height: 38)
                }
            }
            .padding(14)

            // Title text carved into the wood
            Text(title)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(WoodTheme.title)
                .shadow(color: Color(red: 0.30, green: 0.15, blue: 0.05), radius: 0, x: 2, y: 2)
                .padding(.horizontal, 12)
                .minimumScaleFactor(0.5)
                .lineLimit(2)

            // Corner leaf decorations
            VStack {
                HStack {
                    leafIcon.rotationEffect(.degrees(-20))
                    Spacer()
                    leafIcon.rotationEffect(.degrees(70))
                }
                Spacer()
                HStack {
                    leafIcon.rotationEffect(.degrees(-100))
                    Spacer()
                    leafIcon.rotationEffect(.degrees(160))
                }
            }
            .padding(10)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private var leafIcon: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 18))
            .foregroundColor(WoodTheme.leaf)
    }
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
    MainMenuView(onNewGame: {}, onLoadGame: {})
}
