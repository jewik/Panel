import SwiftUI

struct SettingsUI: View {
    var body: some View {
        VStack(spacing: 0) {
            GeneralSettingsView()
            
            FastFolderSettingsView()
        }
        .frame(width: 600)
//        .background(
//            RoundedRectangle(cornerRadius: 10, style: .continuous)
//                .fill(.orange.opacity(0.2))
//        )
    }
}

#if DEBUG
#Preview {
    ZStack(alignment: .top) {
        PanelShape()
            .fill(.black)

        SettingsUI()
    }
    .frame(width: 620, height: 160, alignment: .top)
    .environment(
        makePreviewFastFolderStore([
            PreviewFastFolder(name: "Projects", color: .blue, tags: ["Work"]),
            PreviewFastFolder(name: "Screenshots", color: .orange, tags: ["Design"]),
            PreviewFastFolder(name: "Archive", color: .green, isAvailable: false),
        ])
    )
    .environment(PanelController(panelState: PanelState()))
}
#endif
