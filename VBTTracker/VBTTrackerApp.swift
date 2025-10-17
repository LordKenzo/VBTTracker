//
//  VBTTrackerApp.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini
//

import SwiftUI

@main
struct VBTTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()  // ⭐ UPDATED: Use HomeView instead of SensorConnectionView
        }
    }
}
