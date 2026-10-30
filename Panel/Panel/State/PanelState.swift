

import Observation
import SwiftUI

enum PanelPreset {
    case collapsed
    case home
    case fastfolder
    case airdrop
    case settings
}

@Observable
final class PanelState {
    
    var useGlassPanelSurface: Bool = false
    var isPanelPinned: Bool = false
    var isAutoPinSuppressed: Bool = false
    
    var preset: PanelPreset = .collapsed

}
