

import Observation
import SwiftUI

enum PanelPreset: CustomStringConvertible {
    case collapsed
    case home
    case share
    case fastfolder
    case airdrop
    case player
    case settings
    
    var description: String {
            switch self {
            case .collapsed: return "Collapsed"
            case .home: return "Home"
            case .share: return "Share"
            case .fastfolder: return "Fast Folder"
            case .airdrop: return "AirDrop"
            case .player: return "Player"
            case .settings: return "Settings"
            }
        }
}

@Observable
final class PanelState {
    
    var useGlassPanelSurface: Bool = true
    var isPanelPinned: Bool = false
    var isAutoPinSuppressed: Bool = false
    
    var preset: PanelPreset = .collapsed

}
