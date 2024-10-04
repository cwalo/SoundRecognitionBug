//
//  SoundRecognitionBugApp.swift
//  SoundRecognitionBug
//
//  Created by Mark Gill on 10/4/24.
//

import SwiftUI

@main
struct SoundRecognitionBugApp: App {
    let audioSystem = AudioSystem()
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    init() {
        audioSystem.start()
    }
}
