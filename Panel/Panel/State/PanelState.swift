

import Observation
import SwiftUI

enum PanelPreset {
    case collapsed
    case home
    case share
    case fastfolder
    case airdrop
    case player
    case settings
}

@Observable
final class PanelState {
    
    var useGlassPanelSurface: Bool = false
    var isPanelPinned: Bool = false
    var isAutoPinSuppressed: Bool = false
    
    var preset: PanelPreset = .collapsed

}
