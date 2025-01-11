import SwiftUI

class NavigationManager: ObservableObject {
    @Published var profileId: String? = nil
    
    func handleLink(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        guard let path = components?.path else { return }
        
        let parts = path.split(separator: "/")
        if let basePath = parts[safe: 0], let profileId = parts[safe: 1] {
            switch String(basePath) {
            case "profile":
                self.profileId = String(profileId)
            default:
                break
            }
        }
    }
    
    func clearProfileId() {
        profileId = nil
    }
}
