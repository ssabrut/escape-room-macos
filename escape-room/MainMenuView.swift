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
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sky background

private struct SkyBackground: View {
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

private struct WoodSignTitle: View {
    let title: String

    var body: some View {
        ZStack {
            // Outer rope-tied frame
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.55, green: 0.33, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color(red: 0.36, green: 0.20, blue: 0.09), lineWidth: 6)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)

            // Wood plank rows
            VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.72, green: 0.47, blue: 0.24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color(red: 0.45, green: 0.27, blue: 0.12), lineWidth: 2)
                        )
                        .frame(height: 38)
                }
            }
            .padding(14)

            // Title text carved into the wood
            Text(title)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.93, green: 0.82, blue: 0.58))
                .shadow(color: Color(red: 0.30, green: 0.15, blue: 0.05), radius: 0, x: 2, y: 2)
                .padding(.horizontal, 12)

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
        .aspectRatio(2.1, contentMode: .fit)
    }

    private var leafIcon: some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 18))
            .foregroundColor(Color(red: 0.40, green: 0.70, blue: 0.30))
    }
}

// MARK: - Wood button

private struct WoodButton: View {
    let label: String
    let systemImage: String
    let iconColor: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.55, green: 0.20, blue: 0.18))
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.91, green: 0.80, blue: 0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(red: 0.55, green: 0.33, blue: 0.16), lineWidth: 5)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: isPressed ? 1 : 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
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
