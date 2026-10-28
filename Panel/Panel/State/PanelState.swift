

import Observation
import SwiftUI

enum PanelPreset {
    case collapsed
    case home
    case fastfolder
    case airdrop
    case settings
}

//enum PanelMode {
//    case collapsed
//    case expanded
//}



@Observable
final class PanelState {
    
    var useGlassPanelSurface: Bool = false
    var isPanelPinned: Bool = false
    var isAutoPinSuppressed: Bool = false
    
//    var panelMode: PanelMode = .collapsed
    var preset: PanelPreset = .collapsed

}
