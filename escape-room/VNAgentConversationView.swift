//
//  VNAgentConversationView.swift
//  escape-room
//
//  Visual-novel style overlay for the solver's tick-by-tick narration:
//  a character portrait anchored to the bottom of the screen plus a
//  dialogue box, mirroring the escapee-app VN presentation.
//

import SwiftUI

// MARK: - Tick → dialogue line

private struct VNTickLine {
    let badge: String?
    let text: String
}

private extension SolverTickEvent {
    /// Combines this tick's outcome/thought/plan/action into a single
    /// dialogue line for the VN box.
    var vnLine: VNTickLine {
        var parts: [String] = []

        if let outcome = prevOutcome, let action = outcome.action {
            let success = outcome.success ?? true
            let mark = success ? "✓" : "✗"
            if let note = outcome.note, !note.isEmpty {
                parts.append("\(mark) \(action) — \(note)")
            } else {
                parts.append("\(mark) \(action)")
            }
        }

        if let thought, !thought.isEmpty {
            parts.append(thought)
        }

        if let plan, !plan.isEmpty {
            parts.append("Plan: \(plan)")
        }

        if let finalAction {
            parts.append("→ \(finalAction)")
        }

        let text = parts.joined(separator: "\n\n")
        return VNTickLine(badge: thought != nil ? "thought" : nil, text: text.isEmpty ? "…" : text)
    }
}

// MARK: - VN agent conversation overlay

struct VNAgentConversationView: View {
    let ticks: [SolverTickEvent]
    let world: RenderWorld
    var isLive: Bool = false

    @State private var pulse = false

    private var latestTick: SolverTickEvent? { ticks.last }

    var body: some View {
        ZStack {
            // Bottom scrim so the dialogue box reads over the dungeon map
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
            }
            .allowsHitTesting(false)

            // Character portrait, anchored to the bottom edge
            VStack {
                Spacer()
                VNAgentPortrait(isSpeaking: latestTick != nil)
            }

            // Dialogue box + status header
            VStack(spacing: 0) {
                VNStatusBar(tick: latestTick?.tick, room: latestTick?.room, agentId: latestTick?.agentId, isLive: isLive)
                    .padding(.top, 10)

                Spacer()

                if let latestTick {
                    VNDialogueBox(tick: latestTick)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                        .id(latestTick.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    VNDialogueBox(placeholder: isLive ? "Waiting for the agent to start…" : "No messages yet.")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: latestTick?.id)
    }
}

// MARK: - Status bar

private let solverMaxTicks = 40

private struct VNStatusBar: View {
    let tick: Int?
    let room: String?
    var agentId: String? = nil
    var isLive: Bool = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            if let agentId {
                Circle()
                    .fill(agentColor(for: agentId))
                    .frame(width: 8, height: 8)
            }

            if let room {
                Text(room.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            if isLive {
                Circle()
                    .fill(Color(red: 0.85, green: 0.25, blue: 0.20))
                    .frame(width: 7, height: 7)
                    .opacity(pulse ? 1.0 : 0.35)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }

                Text("LIVE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.40))
            }

            Spacer()

            if let tick {
                Text("TICK \(tick)/\(solverMaxTicks)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Character portrait

private struct VNAgentPortrait: View {
    var isSpeaking: Bool = true

    var body: some View {
        GeometryReader { geo in
            Image("alex_quinn")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .frame(height: 420)
        .opacity(isSpeaking ? 1.0 : 0.35)
        .scaleEffect(isSpeaking ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.2), value: isSpeaking)
        .allowsHitTesting(false)
    }
}

// MARK: - Dialogue box

private struct VNDialogueBox: View {
    var tick: SolverTickEvent? = nil
    var placeholder: String? = nil

    private var line: VNTickLine? { tick?.vnLine }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(tick?.agentId?.uppercased() ?? "THE AGENT")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(red: 0.55, green: 0.80, blue: 0.95))

                if let badge = line?.badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(Color.purple.opacity(0.9))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.06))

            ScrollView {
                Text(line?.text ?? placeholder ?? "…")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .frame(maxHeight: 160)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(Color.black.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
