//
//  AudioManager.swift
//  escape-room
//
//  Created by Michael Eko on 11/06/26.
//

import AVFoundation
import Combine

/// Plays looping background music for the app's menus/screens.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var isMuted: Bool = false {
        didSet { player?.volume = isMuted ? 0 : 1 }
    }

    private var player: AVAudioPlayer?
    private var currentTrack: String?

    private init() {}

    /// Starts looping playback of `name` (without extension). Does nothing if
    /// that track is already playing.
    func playMusic(named name: String, fileExtension: String = "mp3") {
        guard currentTrack != name else { return }

        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.numberOfLoops = -1
            newPlayer.volume = isMuted ? 0 : 1
            newPlayer.prepareToPlay()
            newPlayer.play()

            player = newPlayer
            currentTrack = name
        } catch {
            print("AudioManager: failed to play \(name): \(error)")
        }
    }

    func stopMusic() {
        player?.stop()
        player = nil
        currentTrack = nil
    }

    func toggleMute() {
        isMuted.toggle()
    }
}
