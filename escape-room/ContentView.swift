//
//  ContentView.swift
//  escape-room
//
//  Created by Michael Eko on 09/06/26.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

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
    @Published var solverTicks: [SolverTickEvent] = []
    @Published var solverResult: SolverLog?
    @Published var narrationOpening: String?
    @Published var narrationEnding: String?
    @Published var storyboard: Storyboard?

    @Published var savedRuns: [SavedRunSummary] = []
    @Published var isLoadingRuns = false
    @Published var runsErrorMessage: String?

    /// True once a live solve has been started for the current world (via
    /// `beginSolving`), so the UI knows to stop showing the "Begin" prompt.
    @Published var hasStartedSolving = false

    private var spriteStageStart: Date?
    private var pendingWorldDict: Any?
    private var pendingStoryboardDict: Any?

    private static let apiKey = "84beec4c-8d7d-44fa-be4d-15ff630b8fa8"
    private let baseURL = URL(string: "http://127.0.0.1:8000")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    private static let runDateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }()

    /// Clears the active case so the UI falls back to the main menu.
    func returnToMenu() {
        world = nil
        isLoading = false
        errorMessage = nil
        progressMessage = nil
        startedAt = nil
        spriteETA = nil
        solverTicks = []
        solverResult = nil
        narrationOpening = nil
        narrationEnding = nil
        storyboard = nil
        hasStartedSolving = false
        pendingWorldDict = nil
        pendingStoryboardDict = nil
    }

    func generate(theme: String = "Haunted House", hardMode: Bool = true, numRooms: Int = 3, numAgents: Int = 1) async {
        isLoading = true
        errorMessage = nil
        progressMessage = "Starting up…"
        startedAt = Date()
        spriteETA = nil
        spriteStageStart = nil
        solverTicks = []
        solverResult = nil
        narrationOpening = nil
        narrationEnding = nil
        storyboard = nil
        hasStartedSolving = false
        pendingWorldDict = nil
        pendingStoryboardDict = nil

        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        let body: [String: Any] = ["theme": theme, "hard_mode": hardMode, "num_rooms": numRooms, "num_agents": numAgents, "solve": false]
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
                case "sprites":
                    if let spritesEvent = try? JSONDecoder().decode(SpritesEvent.self, from: lineData) {
                        SpriteCache.shared.load(sprites: spritesEvent.sprites)
                    }
                case "tick":
                    if let tickEvent = try? JSONDecoder().decode(SolverTickEvent.self, from: lineData) {
                        solverTicks.append(tickEvent)
                        if let render = tickEvent.render {
                            world = render
                        }
                    }
                case "narration":
                    if event.stage == "opening" {
                        narrationOpening = event.text
                    } else if event.stage == "ending" {
                        narrationEnding = event.text
                    }
                case "done":
                    let response = try JSONDecoder().decode(GenerateResponse.self, from: lineData)
                    if let sprites = response.sprites { SpriteCache.shared.load(sprites: sprites) }
                    world = response.render
                    solverResult = response.solver
                    storyboard = response.storyboard
                    if let opening = response.narrationOpening { narrationOpening = opening }
                    if let ending = response.narrationEnding { narrationEnding = ending }

                    if let lineObject = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                        pendingWorldDict = lineObject["world"]
                        pendingStoryboardDict = lineObject["storyboard"]
                    }
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

    /// Fetches the list of previously generated worlds from `/generate/runs`.
    func fetchSavedRuns() async {
        isLoadingRuns = true
        runsErrorMessage = nil

        var request = URLRequest(url: baseURL.appendingPathComponent("generate/runs"))
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await session.data(for: request)
            savedRuns = try Self.runDateDecoder.decode([SavedRunSummary].self, from: data)
        } catch {
            runsErrorMessage = error.localizedDescription
        }

        isLoadingRuns = false
    }

    /// Loads a previously generated world by filename. The live solve is
    /// deferred until the player taps "Begin" (see `beginSolving`), so the
    /// narrator overlay has a chance to show first — same as `generate()`.
    func loadSavedRun(filename: String, numAgents: Int = 1) async {
        errorMessage = nil
        solverTicks = []
        solverResult = nil
        narrationOpening = nil
        narrationEnding = nil
        storyboard = nil
        hasStartedSolving = false
        pendingWorldDict = nil
        pendingStoryboardDict = nil

        var request = URLRequest(url: baseURL.appendingPathComponent("generate/runs/\(filename)"))
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(GenerateResponse.self, from: data)
            if let sprites = response.sprites { SpriteCache.shared.load(sprites: sprites) }
            world = response.render
            narrationOpening = response.narrationOpening
            storyboard = response.storyboard

            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            pendingWorldDict = raw?["world"]
            pendingStoryboardDict = raw?["storyboard"]
        } catch {
            errorMessage = "Failed to load run: \(error.localizedDescription)"
        }
    }

    /// Starts the live solve for the world produced by the last `generate()`
    /// call. Used by the "Begin" prompt so generation and solving are two
    /// distinct steps from the player's perspective.
    func beginSolving(numAgents: Int = 1) async {
        guard let worldDict = pendingWorldDict, JSONSerialization.isValidJSONObject(worldDict) else {
            return
        }
        hasStartedSolving = true
        await solveLoadedWorld(worldDict, storyboard: pendingStoryboardDict, numAgents: numAgents)
    }

    /// Streams the solver's live ticks for an already-built world (loaded
    /// from JSON), reusing the same NDJSON event shapes as `/generate`.
    private func solveLoadedWorld(_ worldDict: Any, storyboard: Any? = nil, numAgents: Int = 1) async {
        isLoading = true
        progressMessage = "Starting up…"
        startedAt = Date()

        var request = URLRequest(url: baseURL.appendingPathComponent("generate/solve"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        var body: [String: Any] = ["world": worldDict, "num_agents": numAgents]
        if let storyboard, JSONSerialization.isValidJSONObject(storyboard) {
            body["storyboard"] = storyboard
        }
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
                case "tick":
                    if let tickEvent = try? JSONDecoder().decode(SolverTickEvent.self, from: lineData) {
                        solverTicks.append(tickEvent)
                        if let render = tickEvent.render {
                            world = render
                        }
                    }
                case "narration":
                    if event.stage == "ending" {
                        narrationEnding = event.text
                    }
                case "done":
                    let response = try JSONDecoder().decode(SolveResponse.self, from: lineData)
                    world = response.render
                    solverResult = response.solver
                    if let ending = response.narrationEnding { narrationEnding = ending }
                    sawDone = true
                case "error":
                    errorMessage = event.detail ?? "Unknown error"
                default:
                    break
                }
            }

            if !sawDone && errorMessage == nil {
                errorMessage = "Connection closed before the solver finished."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        progressMessage = nil
        startedAt = nil
        isLoading = false
    }
}

// MARK: - Theme

/// The app currently focuses on a single case file: a murder mystery.
private let gameTheme = "Murder Mystery"

// MARK: - Start mode

private enum StartMode {
    case generate, loadJSON
}

// MARK: - App screen

private enum AppScreen {
    case mainMenu, start, settings, credits
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var vm = EscapeRoomViewModel()
    @State private var numRooms = 3
    @State private var hardMode = true
    @State private var numAgents = 1
    @State private var startMode: StartMode = .generate
    @State private var screen: AppScreen = .mainMenu

    var body: some View {
        NavigationStack {
            Group {
                if let world = vm.world {
                    GameView(
                        world: world,
                        ticks: vm.solverTicks,
                        isLive: vm.isLoading,
                        liveMessage: vm.progressMessage,
                        result: vm.solverResult,
                        narrationOpening: vm.narrationOpening,
                        narrationEnding: vm.narrationEnding,
                        hasStartedSolving: vm.hasStartedSolving,
                        storyboard: vm.storyboard,
                        onBegin: {
                            Task { await vm.beginSolving(numAgents: numAgents) }
                        },
                        onExit: {
                            vm.returnToMenu()
                            screen = .mainMenu
                        }
                    )
                        .overlay(alignment: .top) {
                            if let error = vm.errorMessage {
                                ErrorBanner(message: error) {
                                    vm.errorMessage = nil
                                }
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: vm.errorMessage)
                } else if vm.isLoading {
                    LoadingView(liveMessage: vm.progressMessage, startedAt: vm.startedAt, eta: vm.spriteETA)
                } else if let error = vm.errorMessage {
                    ZStack {
                        CaseDeskBackground()

                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(Color(red: 0.74, green: 0.14, blue: 0.12))

                            Text(error)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
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
                                .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.42), lineWidth: 4))
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
                        },
                        onSettings: {
                            screen = .settings
                        },
                        onCredits: {
                            screen = .credits
                        },
                        onExit: {
                            #if os(macOS)
                            NSApplication.shared.terminate(nil)
                            #endif
                        }
                    )
                } else if screen == .settings {
                    SettingsView(onBack: { screen = .mainMenu })
                } else if screen == .credits {
                    CreditsView(onBack: { screen = .mainMenu })
                } else {
                    StartView(
                        startMode: $startMode,
                        numRooms: $numRooms,
                        hardMode: $hardMode,
                        numAgents: $numAgents,
                        savedRuns: vm.savedRuns,
                        isLoadingRuns: vm.isLoadingRuns,
                        runsErrorMessage: vm.runsErrorMessage,
                        onGenerate: {
                            Task { await vm.generate(theme: gameTheme, hardMode: hardMode, numRooms: numRooms, numAgents: numAgents) }
                        },
                        onRefreshRuns: {
                            Task { await vm.fetchSavedRuns() }
                        },
                        onLoadRun: { filename in
                            Task { await vm.loadSavedRun(filename: filename, numAgents: numAgents) }
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

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)

    var body: some View {
        ZStack {
            CaseDeskBackground()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(WoodTheme.frame, lineWidth: 6)
                        .frame(width: 96, height: 96)
                        .opacity(0.5)

                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color(red: 0.74, green: 0.14, blue: 0.12), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 96, height: 96)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(inkColor)
                        .scaleEffect(pulse ? 1.15 : 0.9)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                VStack(spacing: 10) {
                    Text("BUILDING CASE FILE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.74, green: 0.14, blue: 0.12))

                    Text(displayMessage)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(inkColor)
                        .frame(height: 18)
                        .transition(.opacity)
                        .id(displayMessage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let timingLine {
                        Text(timingLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(inkColor.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(minWidth: 260)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.42), lineWidth: 4))
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
    let ticks: [SolverTickEvent]
    var isLive: Bool = false
    var liveMessage: String? = nil
    var result: SolverLog? = nil
    var narrationOpening: String? = nil
    var narrationEnding: String? = nil
    var hasStartedSolving: Bool = true
    var storyboard: Storyboard? = nil
    var onBegin: () -> Void = {}
    var onExit: () -> Void = {}

    @State private var showResult = false
    @State private var showBegin = true

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height

            ZStack {
                VStack(spacing: 1) {
                    if isLive, let liveMessage, !liveMessage.isEmpty {
                        ProgressBanner(message: liveMessage)
                    }

                    if isWide {
                        HStack(spacing: 1) {
                            DungeonMapView(world: world)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            AgentConversationView(ticks: ticks, isLive: isLive, storyboard: storyboard)
                                .frame(width: min(geo.size.width * 0.32, 360))
                        }
                    } else {
                        VStack(spacing: 1) {
                            DungeonMapView(world: world)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                            AgentConversationView(ticks: ticks, isLive: isLive, storyboard: storyboard)
                                .frame(height: min(geo.size.height * 0.32, 280))
                        }
                    }

                    ObjectiveBarView(world: world)
                }
                .background(WoodTheme.frameDark)

                if showBegin, !hasStartedSolving {
                    NarrationBanner(text: narrationOpening ?? "The case file is ready. Begin when you are.") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showBegin = false
                        }
                        onBegin()
                    }
                }

                if showResult, let result {
                    GameOverPopupView(result: result, narration: narrationEnding) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showResult = false
                        }
                    }
                }

                VStack {
                    HStack {
                        BackToMenuButton(action: onExit)
                            .padding(.leading, 12)
                            .padding(.top, 12)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onChange(of: result?.won) { _, won in
            guard won != nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                showResult = true
            }
        }
    }
}

// MARK: - Back to main menu button (shown over the dungeon map)

private struct BackToMenuButton: View {
    let action: () -> Void

    @State private var showConfirm = false

    var body: some View {
        Button {
            showConfirm = true
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(WoodTheme.title)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(WoodTheme.frame)
                        .overlay(Circle().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                )
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        .confirmationDialog(
            "Leave this case and return to the main menu?",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Back to Main Menu", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Progress banner (live solver status, shown above the map)

private struct ProgressBanner: View {
    let message: String

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("🔔")
                .font(.system(size: 13))

            Text("Progress!")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(WoodTheme.leaf)

            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(inkColor.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .transition(.opacity)
                .id(message)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WoodTheme.leaf.opacity(0.12))
        .overlay(Rectangle().frame(height: 1).foregroundColor(WoodTheme.leaf.opacity(0.25)), alignment: .bottom)
    }
}

// MARK: - Narration banner (opening story beat)

private struct NarrationBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
                Text("THE CASE BEGINS")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.74, green: 0.14, blue: 0.12).opacity(0.7))

                VStack(spacing: 4) {
                    Text("NARRATOR")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18).opacity(0.4))

                    Text(text)
                        .font(.system(size: 15, design: .serif).italic())
                        .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
                        .multilineTextAlignment(.center)
                }

                Button(action: onDismiss) {
                    Text("BEGIN")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(WoodTheme.title)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(WoodTheme.frame)
                                .overlay(Capsule().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.42), lineWidth: 4))
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            .transition(.scale.combined(with: .opacity))
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Game over popup

private struct GameOverPopupView: View {
    let result: SolverLog
    var narration: String? = nil
    let onDismiss: () -> Void

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let stampColor = Color(red: 0.74, green: 0.14, blue: 0.12)

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 14) {
                Text(result.won ? "CASE CLOSED" : (result.wrongDeduction ? "WRONG SUSPECT" : "CASE COLD"))
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(stampColor.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(stampColor.opacity(0.6), lineWidth: 1.5)
                    )
                    .rotationEffect(.degrees(-3))

                Image(systemName: result.won ? "door.left.hand.open" : (result.wrongDeduction ? "person.fill.xmark" : "lock.fill"))
                    .font(.system(size: 40))
                    .foregroundColor(result.won ? Color(red: 0.18, green: 0.48, blue: 0.22) : stampColor)

                Text(result.won ? "AGENT ESCAPED!" : (result.wrongDeduction ? "WRONG ACCUSATION!" : "AGENT TRAPPED"))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(stampColor)

                Text(result.won
                     ? "The agent found a way out in \(result.ticks) ticks."
                     : (result.wrongDeduction
                        ? "The agent accused the wrong suspect and the real culprit got away."
                        : "The agent got stuck after \(result.ticks) ticks."))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(inkColor)
                    .multilineTextAlignment(.center)

                if let narration, !narration.isEmpty {
                    VStack(spacing: 4) {
                        Text("NARRATOR")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .tracking(1.5)
                            .foregroundColor(inkColor.opacity(0.4))

                        Text(narration)
                            .font(.system(size: 13, design: .serif).italic())
                            .foregroundColor(inkColor)
                            .multilineTextAlignment(.center)
                    }
                }

                HStack(spacing: 18) {
                    statColumn(title: "OPTIMAL", value: "\(result.optimal)")
                    statColumn(title: "WASTED", value: "\(result.wasted)")
                    statColumn(title: "EFFICIENCY", value: String(format: "%.0f%%", result.efficiency * 100))
                }
                .padding(.top, 4)

                Button(action: onDismiss) {
                    Text("CONTINUE")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(WoodTheme.title)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(WoodTheme.frame)
                                .overlay(Capsule().strokeBorder(WoodTheme.frameDark, lineWidth: 3))
                        )
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.42), lineWidth: 4))
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(inkColor)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(inkColor.opacity(0.6))
        }
    }
}

// MARK: - Error banner

/// Surfaces stream/decode errors that happen while a world is already on
/// screen (e.g. the solve stream drops mid-run) — without this they were
/// silently swallowed since `GameView` always wins over the error screen.
private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(red: 0.85, green: 0.25, blue: 0.20))

            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(WoodTheme.title)
                .lineLimit(3)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(WoodTheme.parchment.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(WoodTheme.frame)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WoodTheme.frameDark, lineWidth: 3))
        )
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Agent conversation panel

/// Mirrors `MAX_TICKS` in `src/escape_rooms/nodes/gameplay.py` — the solver
/// gives up after this many ticks, so it's the denominator for progress.
private let solverMaxTicks = 40

/// Tabs for the right-hand panel: the live solver log vs. the mystery clue board.
private enum CasePanelTab: String, CaseIterable {
    case caseNotes = "CASE NOTES"
    case clueBoard = "CLUE BOARD"
}

private struct AgentConversationView: View {
    let ticks: [SolverTickEvent]
    var isLive: Bool = false
    var storyboard: Storyboard? = nil

    @State private var pulse = false
    @State private var selectedTab: CasePanelTab = .caseNotes

    private let folderColor = Color(red: 0.78, green: 0.64, blue: 0.42)
    private let caseParchment = Color(red: 0.96, green: 0.93, blue: 0.84)
    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(CasePanelTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundColor(selectedTab == tab ? inkColor : inkColor.opacity(0.45))

                            if tab == .caseNotes, isLive {
                                Circle()
                                    .fill(Color(red: 0.74, green: 0.14, blue: 0.12))
                                    .frame(width: 7, height: 7)
                                    .opacity(pulse ? 1.0 : 0.35)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                                    .onAppear { pulse = true }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? caseParchment : folderColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTab == .caseNotes {
                if isLive, let lastTick = ticks.last?.tick {
                    HStack {
                        Spacer()
                        Text("TICK \(lastTick)/\(solverMaxTicks)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundColor(inkColor.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(caseParchment)
                }

                if ticks.isEmpty {
                    VStack {
                        Spacer()
                        Text(isLive ? "Waiting for the agent to start…" : "No messages yet.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(inkColor.opacity(0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .background(caseParchment.overlay(NotebookLinesOverlay()))
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(ticks) { tick in
                                    SolverTickBubble(tick: tick)
                                        .id(tick.id)
                                }
                            }
                            .padding(12)
                        }
                        .background(caseParchment.overlay(NotebookLinesOverlay()))
                        .onChange(of: ticks.count) { _, _ in
                            if let last = ticks.last {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            } else {
                ClueBoardView(storyboard: storyboard, ticks: ticks)
                    .background(caseParchment.overlay(NotebookLinesOverlay()))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Clue board (suspects + evidence log)

private struct ClueBoardView: View {
    let storyboard: Storyboard?
    let ticks: [SolverTickEvent]

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let amber = Color(red: 0.74, green: 0.55, blue: 0.16)

    /// All milestone tokens unlocked so far, in the order they were discovered.
    private var evidence: [String] {
        ticks.flatMap { $0.newMilestones ?? [] }
    }

    /// True once the proof object has been picked up or examined.
    private var proofFound: Bool {
        guard let proofObjectId = storyboard?.mystery?.proofObjectId, !proofObjectId.isEmpty else { return false }
        return evidence.contains { $0.hasSuffix(":\(proofObjectId)") }
    }

    private var suspects: [Suspect] {
        storyboard?.suspects ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Mystery status
                HStack(spacing: 7) {
                    Circle()
                        .fill(proofFound ? amber : inkColor.opacity(0.4))
                        .frame(width: 7, height: 7)

                    Text(proofFound ? "Proof found — make your accusation" : "Investigating…")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(proofFound ? amber : inkColor.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(proofFound ? amber.opacity(0.12) : inkColor.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(proofFound ? amber.opacity(0.3) : inkColor.opacity(0.12)))
                )

                // Suspects
                if !suspects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUSPECTS")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(inkColor)

                        VStack(spacing: 6) {
                            ForEach(suspects) { suspect in
                                SuspectCard(suspect: suspect)
                            }
                        }
                    }
                }

                // Evidence log
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("EVIDENCE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(inkColor)

                        if !evidence.isEmpty {
                            Text("\(evidence.count)")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundColor(Color(red: 0.96, green: 0.93, blue: 0.84))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(inkColor.opacity(0.6)))
                        }
                    }

                    if evidence.isEmpty {
                        Text("No evidence collected yet.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(inkColor.opacity(0.6))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(evidence.enumerated()), id: \.offset) { _, token in
                                let isProof = storyboard?.mystery?.proofObjectId.map { token.hasSuffix(":\($0)") } ?? false
                                EvidenceRow(text: humanizeMilestone(token), isProof: isProof)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SuspectCard: View {
    let suspect: Suspect

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let folderColor = Color(red: 0.78, green: 0.64, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(suspect.name)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(inkColor)

            if let connection = suspect.connectionToVictim, !connection.isEmpty {
                Text(connection)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(inkColor.opacity(0.7))
            }

            if let motive = suspect.apparentMotive, !motive.isEmpty {
                HStack(spacing: 4) {
                    Text("MOTIVE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.10))

                    Text(motive)
                        .font(.system(size: 11, design: .monospaced).italic())
                        .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.10))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(folderColor.opacity(0.18))
        )
    }
}

private struct EvidenceRow: View {
    let text: String
    var isProof: Bool = false

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let red = Color(red: 0.74, green: 0.14, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isProof {
                Text("KEY EVIDENCE")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(red)
            }

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(inkColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isProof ? red.opacity(0.08) : inkColor.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isProof ? red.opacity(0.3) : Color.clear))
        )
    }
}

// MARK: - Solver tick bubble

private struct SolverTickBubble: View {
    let tick: SolverTickEvent

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let folderColor = Color(red: 0.78, green: 0.64, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let agentId = tick.agentId {
                    Circle()
                        .fill(agentColor(for: agentId))
                        .frame(width: 8, height: 8)
                }

                Text("Tick \(tick.tick) · \(tick.room)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(inkColor.opacity(0.6))
            }

            if let narration = tick.narration, !narration.isEmpty {
                Text(narration)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundColor(Color(red: 0.45, green: 0.12, blue: 0.45))
            }

            if let outcome = tick.prevOutcome, let action = outcome.action {
                let success = outcome.success ?? true
                Text("↳ \(action) → \(outcome.note ?? "")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(success ? Color(red: 0.18, green: 0.42, blue: 0.20) : Color(red: 0.55, green: 0.18, blue: 0.12))
            }

            if let thought = tick.thought, !thought.isEmpty {
                Text(thought)
                    .font(.system(size: 12, design: .monospaced).italic())
                    .foregroundColor(inkColor)
            }

            if let plan = tick.plan, !plan.isEmpty {
                Text("Plan: \(plan)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(inkColor.opacity(0.75))
            }

            if let action = tick.finalAction {
                Text("→ \(action)")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.10))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(folderColor.opacity(0.18))
        )
    }
}

// MARK: - Objective bar

private struct ObjectiveBarView: View {
    let world: RenderWorld

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let folderColor = Color(red: 0.78, green: 0.64, blue: 0.42)
    private let caseParchment = Color(red: 0.96, green: 0.93, blue: 0.84)

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("OBJECTIVE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(inkColor)

                Text("Explore the rooms and find a way out.")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(red: 0.18, green: 0.42, blue: 0.20))

                Spacer()
            }

            Divider().background(folderColor.opacity(0.4))

            let parties = world.parties ?? [world.party]

            MapLegendView(agentIds: parties.enumerated().map { $0.element.agentId ?? "agent_\($0.offset + 1)" })

            PartyStatusView(parties: parties)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(caseParchment)
        .overlay(Rectangle().frame(height: 3).foregroundColor(folderColor), alignment: .top)
    }
}

// MARK: - Settings screen

private struct SettingsView: View {
    let onBack: () -> Void

    @StateObject private var audio = AudioManager.shared

    var body: some View {
        ZStack {
            CaseDeskBackground()

            VStack(spacing: 20) {
                CaseFileHeader(title: "SETTINGS", onBack: onBack)

                CaseFilePanel {
                    HStack {
                        Text("Music")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !audio.isMuted },
                            set: { audio.isMuted = !$0 }
                        ))
                        .labelsHidden()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: 480)

                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Credits screen

private struct CreditsView: View {
    let onBack: () -> Void

    private let credits: [(role: String, name: String)] = [
        ("Design & Development", "Michael Eko"),
        ("World Generation", "escape_rooms engine"),
        ("Music & Sound", "AudioManager"),
    ]

    var body: some View {
        ZStack {
            CaseDeskBackground()

            VStack(spacing: 20) {
                CaseFileHeader(title: "CREDITS", onBack: onBack)

                CaseFilePanel {
                    VStack(spacing: 0) {
                        ForEach(credits.indices, id: \.self) { i in
                            HStack {
                                Text(credits[i].role)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18).opacity(0.7))
                                Spacer()
                                Text(credits[i].name)
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            if i != credits.count - 1 {
                                Divider().background(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.3))
                            }
                        }
                    }
                }
                .frame(maxWidth: 480)

                Spacer()
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Case file header / panel (shared by settings & credits)

private struct CaseFileHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
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

            Text(title)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(Color(red: 0.74, green: 0.14, blue: 0.12))

            Spacer()

            // Balances the back button so the title stays centered.
            Color.clear.frame(width: 80, height: 1)
        }
    }
}

private struct CaseFilePanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(red: 0.96, green: 0.93, blue: 0.84))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 0.78, green: 0.64, blue: 0.42), lineWidth: 3))
    }
}

// MARK: - Start screen

private struct StartView: View {
    @Binding var startMode: StartMode
    @Binding var numRooms: Int
    @Binding var hardMode: Bool
    @Binding var numAgents: Int
    let savedRuns: [SavedRunSummary]
    let isLoadingRuns: Bool
    let runsErrorMessage: String?
    let onGenerate: () -> Void
    let onRefreshRuns: () -> Void
    let onLoadRun: (String) -> Void
    let onBack: () -> Void

    private let inkColor = Color(red: 0.25, green: 0.22, blue: 0.18)
    private let panelColor = Color(red: 0.96, green: 0.93, blue: 0.84)

    var body: some View {
        ZStack {
            CaseDeskBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    CaseFileHeader(title: "NEW CASE", onBack: onBack)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

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
                        // World settings
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WORLD SETTINGS")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(inkColor)

                            CaseFilePanel {
                                VStack(spacing: 0) {
                                    Stepper(value: $numRooms, in: 1...10) {
                                        HStack {
                                            Text("Rooms")
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundColor(inkColor)
                                            Spacer()
                                            Text("\(numRooms)")
                                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                                .foregroundColor(inkColor)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)

                                    Divider().background(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.3))

                                    HStack {
                                        Text("Hard Mode")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundColor(inkColor)
                                        Spacer()
                                        Toggle("", isOn: $hardMode)
                                            .labelsHidden()
                                            .tint(WoodTheme.frame)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)

                                    Divider().background(Color(red: 0.55, green: 0.50, blue: 0.42).opacity(0.3))

                                    Stepper(value: $numAgents, in: 1...4) {
                                        HStack {
                                            Text("Agents")
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundColor(inkColor)
                                            Spacer()
                                            Text("\(numAgents)")
                                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                                .foregroundColor(inkColor)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        WoodButton(label: "OPEN CASE FILE", systemImage: "folder.fill", iconColor: WoodTheme.leaf, action: onGenerate)
                            .padding(.horizontal, 24)

                    } else {
                        // Agent count (applies to the live solve of the loaded world)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WORLD SETTINGS")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(inkColor)

                            CaseFilePanel {
                                Stepper(value: $numAgents, in: 1...4) {
                                    HStack {
                                        Text("Agents")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundColor(inkColor)
                                        Spacer()
                                        Text("\(numAgents)")
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(inkColor)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Saved worlds grid
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("SAVED CASE FILES")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(inkColor)

                                Spacer()

                                Button(action: onRefreshRuns) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundColor(inkColor)
                                }
                                .buttonStyle(.plain)
                            }

                            if isLoadingRuns {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .padding(.vertical, 24)
                                    Spacer()
                                }
                            } else if let runsErrorMessage {
                                Text(runsErrorMessage)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color(red: 0.55, green: 0.18, blue: 0.12))
                                    .padding(.vertical, 12)
                            } else if savedRuns.isEmpty {
                                Text("No saved worlds found.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(inkColor.opacity(0.6))
                                    .padding(.vertical, 12)
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    ForEach(savedRuns) { run in
                                        SavedRunCard(run: run) {
                                            onLoadRun(run.filename)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .onAppear {
                            if savedRuns.isEmpty {
                                onRefreshRuns()
                            }
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
        }
    }
}

// MARK: - Saved run card

private let savedRunDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, HH:mm"
    return formatter
}()

private struct SavedRunCard: View {
    let run: SavedRunSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(run.theme)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(WoodTheme.frameDark)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(savedRunDateFormatter.string(from: run.createdAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(WoodTheme.frameDark.opacity(0.6))

                Divider().background(WoodTheme.frame.opacity(0.4))

                Label("\(run.numRooms) room\(run.numRooms == 1 ? "" : "s")", systemImage: "square.grid.2x2")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(WoodTheme.frameDark.opacity(0.8))

                Label("\(run.numObjects) object\(run.numObjects == 1 ? "" : "s")", systemImage: "shippingbox")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(WoodTheme.frameDark.opacity(0.8))

                if let solver = run.solver {
                    Label(
                        solver.won ? "Won · \(Int(solver.efficiency * 100))%" : (solver.wrongDeduction ? "Wrong suspect" : "Lost"),
                        systemImage: solver.won ? "checkmark.seal.fill" : (solver.wrongDeduction ? "person.fill.xmark" : "xmark.seal.fill")
                    )
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(solver.won ? Color(red: 0.18, green: 0.48, blue: 0.22) : Color(red: 0.55, green: 0.18, blue: 0.12))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WoodTheme.parchment)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WoodTheme.frame, lineWidth: 3))
        }
        .buttonStyle(.plain)
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
    let parties: [RenderWorld.Party]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(parties.indices, id: \.self) { i in
                let party = parties[i]
                HStack {
                    Label(party.currentRoom, systemImage: "location.fill")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(agentColor(for: party.agentId ?? "agent_1"))

                    Spacer()

                    if party.inventory.isEmpty {
                        Text("No items")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18).opacity(0.6))
                    } else {
                        Label("\(party.inventory.count) item(s)", systemImage: "bag")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(red: 0.62, green: 0.45, blue: 0.10))
                    }

                    Spacer()

                    if i == 0 {
                        Text("Tick \(party.tick)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(red: 0.25, green: 0.22, blue: 0.18).opacity(0.6))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
