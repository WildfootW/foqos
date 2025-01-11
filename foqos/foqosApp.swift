//
//  foqosApp.swift
//  foqos
//
//  Created by Ali Waseem on 2024-10-06.
//

import SwiftData
import SwiftUI

@main
struct foqosApp: App {
    @StateObject private var appBlocker = AppBlocker()
    @StateObject private var donationManager = TipManager()
    @StateObject private var nfcScanner = NFCScanner()
    @StateObject private var navigationManager = NavigationManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .onOpenURL() { url in
                    handleUniversalLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                        guard let url = userActivity.webpageURL else {
                                return
                        }
                    handleUniversalLink(url)
                    
                }
                .environmentObject(appBlocker)
                .environmentObject(donationManager)
                .environmentObject(nfcScanner)
                .environmentObject(navigationManager)
        }
        .modelContainer(
            for: [
                BlockedProfileSession.self,
                BlockedProfiles.self,
            ]
        )
    }
    
    
    private func handleUniversalLink(_ url: URL) {
        navigationManager.handleLink(url)
    }
}
