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

    private static let apiKey = "84beec4c-8d7d-44fa-be4d-15ff630b8fa8"
    private let baseURL = URL(string: "http://127.0.0.1:8000")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    func generate(theme: String = "Haunted House", hardMode: Bool = true, numRooms: Int = 3) async {
        isLoading = true
        errorMessage = nil

        var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiKey, forHTTPHeaderField: "X-API-Key")
        let body: [String: Any] = ["theme": theme, "hard_mode": hardMode, "num_rooms": numRooms]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)
            let response = try JSONDecoder().decode(GenerateResponse.self, from: data)
            world = response.render
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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

// MARK: - Root view

struct ContentView: View {
    @StateObject private var vm = EscapeRoomViewModel()
    @State private var selectedTheme = themes[0]

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Generating world…")
                        .font(.system(size: 14, design: .monospaced))
                } else if let world = vm.world {
                    VStack(spacing: 0) {
                        DungeonMapView(world: world)
                            .background(Color(white: 0.08))

                        Divider()

                        MapLegendView()
                            .padding(.vertical, 8)
                            .background(Color(white: 0.1))

                        PartyStatusView(party: world.party)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 13, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") { Task { await vm.generate(theme: selectedTheme, hardMode: true, numRooms: 3) } }
                    }
                } else {
                    ThemePickerView(selectedTheme: $selectedTheme) {
                        Task { await vm.generate(theme: selectedTheme, hardMode: true, numRooms: 3) }
                    }
                }
            }
            .navigationTitle("Escape Room")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.08), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .background(Color(white: 0.08).ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Theme picker

private struct ThemePickerView: View {
    @Binding var selectedTheme: String
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("ESCAPE ROOM")
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 8) {
                Text("CHOOSE THEME")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))

                VStack(spacing: 0) {
                    ForEach(themes, id: \.self) { theme in
                        Button {
                            selectedTheme = theme
                        } label: {
                            HStack {
                                Text(theme)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(selectedTheme == theme ? .black : .green)
                                Spacer()
                                if selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.black)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selectedTheme == theme ? Color.green : Color(white: 0.12))
                        }
                        .buttonStyle(.plain)

                        if theme != themes.last {
                            Divider().background(Color(white: 0.2))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(white: 0.25), lineWidth: 1))
            }
            .padding(.horizontal, 24)

            Button(action: onGenerate) {
                Text("GENERATE WORLD")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Party status bar

private struct PartyStatusView: View {
    let party: RenderWorld.Party

    var body: some View {
        HStack {
            Label(party.currentRoom, systemImage: "location.fill")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.green)

            Spacer()

            if party.inventory.isEmpty {
                Text("No items")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Label("\(party.inventory.count) item(s)", systemImage: "bag")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.yellow)
            }

            Spacer()

            Text("Tick \(party.tick)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
