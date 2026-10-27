

import SwiftUI
import UniformTypeIdentifiers
import os

struct AirDropView : View {
    
    @Environment(AirDropService.self) private var airDropService
    
    @State private var isDragging: Bool = false
    
    private var bgOpacity: Double {
        isDragging ? 0.3 : 0.2
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 30)
                .fill(Color.indigo.opacity(bgOpacity))
                .stroke(Color.indigo.opacity(bgOpacity), lineWidth: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack (spacing: 6){
                Image(systemName: "airplayaudio").font(.system(size: 20))
                Text("AirDrop")
                    .font(.system(size: 20))
            }
        }
        .padding(10)
        .frame(width: 400, height: 100, alignment: .bottom)
//        .background(Color.pink.opacity(0.1))
        
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $isDragging
        ) {
            providers in
            Log.ui.info("AirDrop received content to share")
            return airDropService.share(providers)
        }
    }
}

#Preview {
    AirDropView()
        .environment(AppContainer().airDropService)
        .background(Color.pink.opacity(0.1))
}
