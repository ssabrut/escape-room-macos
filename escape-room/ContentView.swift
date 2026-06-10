//
//  ContentView.swift
//  escape-room
//
//  Created by Michael Eko on 09/06/26.
//

import SwiftUI
import Combine

// MARK: - ViewModel

@MainActor
final class EscapeRoomViewModel: ObservableObject {
    init() {}

    @Published var world: RenderWorld?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var progressMessage: String?
    @Published var startedAt: Date?
    @Published var spriteETA: TimeInterval?

    private var spriteStageStart: Date?

    private static let apiKey = "84beec4c-8d7d-44fa-be4d-15ff630b8fa8"
    private let baseURL = URL(string: "http://127.0.0.1:8000")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config)
    }()

    func generate(theme: String = "Haunted House", hardMode: Bool = true, numRooms: Int = 3) async {
        isLoading = true
        errorMessage = nil
        progressMessage = "Starting up…"
        startedAt = Date()
        spriteETA = nil
        spriteStageStart = nil

        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        let body: [String: Any] = ["theme": theme, "hard_mode": hardMode, "num_rooms": numRooms]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, _) = try await session.bytes(for: request)
            var sawDone = false

            for try await line in bytes.lines {
                guard let lineData = line.data(using: .utf8) else { continue }
                guard let event = try? JSONDecoder().decode(StreamEvent.self, from: lineData) else { continue }

                switch event.type {
                case "progress":
                    progressMessage = event.message
                    updateSpriteETA(for: event)
                case "done":
                    let response = try JSONDecoder().decode(GenerateResponse.self, from: lineData)
                    if let sprites = response.sprites { SpriteCache.shared.load(sprites: sprites) }
                    world = response.render
                    sawDone = true
                case "error":
                    errorMessage = event.detail ?? "Unknown error"
                default:
                    break
                }
            }

            if !sawDone && errorMessage == nil {
                errorMessage = "Connection closed before world was generated."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        progressMessage = nil
        startedAt = nil
        spriteETA = nil
        isLoading = false
    }

    /// Estimates remaining time during the "sprites" stage from the average
    /// time-per-sprite observed so far.
    private func updateSpriteETA(for event: StreamEvent) {
        guard event.stage == "sprites",
              let current = event.current,
              let total = event.total,
              total > 0
        else {
            spriteETA = nil
            return
        }

        let now = Date()
        if current == 0 {
            spriteStageStart = now
            spriteETA = nil
            return
        }

        guard let stageStart = spriteStageStart, current < total else {
            spriteETA = nil
            return
        }

        let elapsed = now.timeIntervalSince(stageStart)
        let perSprite = elapsed / Double(current)
        spriteETA = perSprite * Double(total - current)
    }

    func loadFromJSON(_ jsonString: String) {
        errorMessage = nil
        guard let data = jsonString.data(using: .utf8) else {
            errorMessage = "Invalid text encoding."
            return
        }
        do {
            let response = try JSONDecoder().decode(GenerateResponse.self, from: data)
            if let sprites = response.sprites { SpriteCache.shared.load(sprites: sprites) }
            world = response.render
        } catch {
            errorMessage = "JSON parse error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Theme list

private let themes = [
    "Haunted House",
    "Murder Mystery",
    "Prison Break",
    "Pirate Adventure",
    "Bank Robbery",
    "Cosmic Crisis",
    "Treasure Hunt",
    "Zombie Apocalypse",
    "Secret Agents and Spies",
    "Horror",
]

// MARK: - Start mode

private enum StartMode {
    case generate, loadJSON
}

// MARK: - App screen

private enum AppScreen {
    case mainMenu, start
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var vm = EscapeRoomViewModel()
    @State private var selectedTheme = themes[0]
    @State private var numRooms = 3
    @State private var hardMode = true
    @State private var startMode: StartMode = .generate
    @State private var screen: AppScreen = .mainMenu

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    LoadingView(liveMessage: vm.progressMessage, startedAt: vm.startedAt, eta: vm.spriteETA)
                } else if let world = vm.world {
                    GameView(world: world)
                } else if let error = vm.errorMessage {
                    ZStack {
                        SkyBackground()

                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color(red: 0.55, green: 0.18, blue: 0.12))

                            Text(error)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(WoodTheme.frameDark)
                                .multilineTextAlignment(.center)

                            Button {
                                vm.errorMessage = nil
                            } label: {
                                Text("BACK")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundColor(WoodTheme.title)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(WoodTheme.frame)
                                            .overlay(Capsule().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(WoodTheme.parchment)
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WoodTheme.frame, lineWidth: 4))
                        )
                        .padding(.horizontal, 32)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
                    }
                    .ignoresSafeArea()
                } else if screen == .mainMenu {
                    MainMenuView(
                        onNewGame: {
                            startMode = .generate
                            screen = .start
                        },
                        onLoadGame: {
                            startMode = .loadJSON
                            screen = .start
                        }
                    )
                } else {
                    StartView(
                        startMode: $startMode,
                        selectedTheme: $selectedTheme,
                        numRooms: $numRooms,
                        hardMode: $hardMode,
                        onGenerate: {
                            Task { await vm.generate(theme: selectedTheme, hardMode: hardMode, numRooms: numRooms) }
                        },
                        onLoadJSON: { json in
                            vm.loadFromJSON(json)
                        },
                        onBack: {
                            screen = .mainMenu
                        }
                    )
                }
            }
            .navigationTitle("Escape Room")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(WoodTheme.frame, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .background(WoodTheme.frameDark.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Loading view

private let loadingMessages = [
    "Sketching the rooms…",
    "Hiding the keys…",
    "Locking the chests…",
    "Placing the clues…",
    "Summoning the agents…",
    "Polishing the puzzles…",
]

private struct LoadingView: View {
    var liveMessage: String?
    var startedAt: Date?
    var eta: TimeInterval?

    @State private var spin = false
    @State private var pulse = false
    @State private var dotCount = 0
    @State private var messageIndex = 0
    @State private var elapsed: TimeInterval = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let messageTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    private var displayMessage: String {
        if let liveMessage, !liveMessage.isEmpty {
            return liveMessage
        }
        return loadingMessages[messageIndex] + String(repeating: ".", count: dotCount)
    }

    private var timingLine: String? {
        guard startedAt != nil else { return nil }
        var line = "Elapsed: \(formatDuration(elapsed))"
        if let eta, eta > 1 {
            line += "  ·  ~\(formatDuration(eta)) remaining"
        }
        return line
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            SkyBackground()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(WoodTheme.frame, lineWidth: 6)
                        .frame(width: 96, height: 96)
                        .opacity(0.5)

                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(WoodTheme.title, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 32))
                        .foregroundColor(WoodTheme.leaf)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                VStack(spacing: 10) {
                    Text("GENERATING WORLD")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(WoodTheme.title)
                        .shadow(color: Color(red: 0.30, green: 0.15, blue: 0.05), radius: 0, x: 1, y: 1)

                    Text(displayMessage)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(WoodTheme.parchment)
                        .frame(height: 18)
                        .transition(.opacity)
                        .id(displayMessage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let timingLine {
                        Text(timingLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(WoodTheme.parchment.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(minWidth: 260)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(WoodTheme.frame)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WoodTheme.frameDark, lineWidth: 4))
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            spin = true
            pulse = true
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
            if let startedAt {
                elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        .onReceive(messageTimer) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                messageIndex = (messageIndex + 1) % loadingMessages.count
            }
        }
    }
}

// MARK: - Game view (map / agent conversation / objective grid)

private struct GameView: View {
    let world: RenderWorld

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height

            VStack(spacing: 1) {
                if isWide {
                    HStack(spacing: 1) {
                        DungeonMapView(world: world)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        AgentConversationView()
                            .frame(width: min(geo.size.width * 0.32, 360))
                    }
                } else {
                    VStack(spacing: 1) {
                        DungeonMapView(world: world)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        AgentConversationView()
                            .frame(height: min(geo.size.height * 0.32, 280))
                    }
                }

                ObjectiveBarView(world: world)
            }
            .background(WoodTheme.frameDark)
        }
    }
}

// MARK: - Agent conversation panel

private struct AgentConversationView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AGENT CONVERSATION")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(WoodTheme.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(WoodTheme.frame)

            VStack {
                Spacer()
                Text("No messages yet.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(WoodTheme.frameDark.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .background(WoodTheme.parchment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Objective bar

private struct ObjectiveBarView: View {
    let world: RenderWorld

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("OBJECTIVE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(WoodTheme.frameDark)

                Text("Explore the rooms and find a way out.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(red: 0.18, green: 0.42, blue: 0.20))

                Spacer()
            }

            Divider().background(WoodTheme.frame.opacity(0.4))

            MapLegendView()

            PartyStatusView(party: world.party)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(WoodTheme.parchment)
        .overlay(Rectangle().frame(height: 3).foregroundColor(WoodTheme.frame), alignment: .top)
    }
}

// MARK: - Start screen

private struct StartView: View {
    @Binding var startMode: StartMode
    @Binding var selectedTheme: String
    @Binding var numRooms: Int
    @Binding var hardMode: Bool
    let onGenerate: () -> Void
    let onLoadJSON: (String) -> Void
    let onBack: () -> Void

    @State private var jsonText = ""

    var body: some View {
        ZStack {
            SkyBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Button(action: onBack) {
                            Label("BACK", systemImage: "chevron.left")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(WoodTheme.title)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(WoodTheme.frame)
                                        .overlay(Capsule().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                                )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    WoodSignTitle(title: "ESCAPE ROOM", fontSize: 26, aspectRatio: 4.0)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 24)

                    // Mode toggle
                    HStack(spacing: 0) {
                        ModeTab(title: "GENERATE", selected: startMode == .generate) {
                            startMode = .generate
                        }
                        ModeTab(title: "LOAD JSON", selected: startMode == .loadJSON) {
                            startMode = .loadJSON
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frame, lineWidth: 3))
                    .padding(.horizontal, 24)

                    if startMode == .generate {
                        // Theme list
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHOOSE THEME")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(WoodTheme.frameDark)

                            VStack(spacing: 0) {
                                ForEach(themes, id: \.self) { theme in
                                    Button {
                                        selectedTheme = theme
                                    } label: {
                                        HStack {
                                            Text(theme)
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundColor(selectedTheme == theme ? WoodTheme.parchment : WoodTheme.frameDark)
                                            Spacer()
                                            if selectedTheme == theme {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(WoodTheme.parchment)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(selectedTheme == theme ? WoodTheme.frame : WoodTheme.parchment)
                                    }
                                    .buttonStyle(.plain)

                                    if theme != themes.last {
                                        Divider().background(WoodTheme.frame.opacity(0.4))
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frame, lineWidth: 3))
                        }
                        .padding(.horizontal, 24)

                        // World settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WORLD SETTINGS")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(WoodTheme.frameDark)

                            VStack(spacing: 0) {
                                Stepper(value: $numRooms, in: 1...10) {
                                    HStack {
                                        Text("Rooms")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundColor(WoodTheme.frameDark)
                                        Spacer()
                                        Text("\(numRooms)")
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(WoodTheme.frameDark)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(WoodTheme.parchment)

                                Divider().background(WoodTheme.frame.opacity(0.4))

                                HStack {
                                    Text("Hard Mode")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(WoodTheme.frameDark)
                                    Spacer()
                                    Toggle("", isOn: $hardMode)
                                        .labelsHidden()
                                        .tint(WoodTheme.frame)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(WoodTheme.parchment)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frame, lineWidth: 3))
                        }
                        .padding(.horizontal, 24)

                        WoodButton(label: "GENERATE WORLD", systemImage: "wand.and.stars", iconColor: WoodTheme.leaf, action: onGenerate)
                            .padding(.horizontal, 24)

                    } else {
                        // JSON paste area
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASTE WORLD JSON")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(WoodTheme.frameDark)

                            TextEditor(text: $jsonText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(WoodTheme.frameDark)
                                .scrollContentBackground(.hidden)
                                .background(WoodTheme.parchment)
                                .frame(minHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frame, lineWidth: 3))

                            Text("Paste the full API response JSON (must contain a \"render\" key).")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(WoodTheme.frameDark.opacity(0.8))
                        }
                        .padding(.horizontal, 24)

                        HStack(spacing: 12) {
                            Button {
                                jsonText = ""
                            } label: {
                                Text("CLEAR")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundColor(WoodTheme.title)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(WoodTheme.frame)
                                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                                    )
                            }
                            .buttonStyle(.plain)

                            WoodButton(label: "LOAD WORLD", systemImage: "scroll.fill", iconColor: .pink, action: { onLoadJSON(jsonText) }, isEnabled: !jsonText.isEmpty)
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 32)
                }
            }
        }
    }
}

// MARK: - Mode toggle tab

private struct ModeTab: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(selected ? WoodTheme.parchment : WoodTheme.frameDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? WoodTheme.frame : WoodTheme.parchment)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Party status bar

private struct PartyStatusView: View {
    let party: RenderWorld.Party

    var body: some View {
        HStack {
            Label(party.currentRoom, systemImage: "location.fill")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(red: 0.18, green: 0.42, blue: 0.20))

            Spacer()

            if party.inventory.isEmpty {
                Text("No items")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(WoodTheme.frameDark.opacity(0.6))
            } else {
                Label("\(party.inventory.count) item(s)", systemImage: "bag")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.10))
            }

            Spacer()

            Text("Tick \(party.tick)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(WoodTheme.frameDark.opacity(0.6))
        }
    }
}

#Preview {
    ContentView()
}
