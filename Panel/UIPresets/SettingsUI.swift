import SwiftUI

struct SettingsUI: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(.blue.opacity(0.5))
            .frame(width: 600, height: 150)
    }
}

#Preview {
    ZStack(alignment: .top) {
        PanelShape()
            .fill(.black)
        
        SettingsUI()
    }
    .frame(width: 300, height: 150)
}
