

import Observation
import SwiftUI

enum ExpandedPreset {
    case home
    case fastfolder
    case airdrop
    case settings
}

enum PanelMode {
    case collapsed
    case expanded
}



@Observable
final class PanelState {
    
    var useGlassPanelSurface: Bool = false
    var isPanelPinned: Bool = false
    
    var panelMode: PanelMode = .collapsed
    var expandedPreset: ExpandedPreset = .home

}
