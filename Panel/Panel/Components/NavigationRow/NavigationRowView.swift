
//
//  Untitled.swift
//  UITests
//
//  Created by Usanin Ivan on 24.07.2026.
//



import SwiftUI

struct NavigationRowView: View {
    
    @Environment(PanelController.self) private var controller
    
    let terminateApplication: @MainActor () -> Void
    
    var body: some View {
        HStack (alignment: .center, spacing: 4) {
            DotButton(
                color: .red,
                showUnsavedDot: true,
                action: {
                    terminateApplication()
                },
                innerContent: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
            )
            
            DotButton(
                color: .yellow,
                showInner: controller.expandedPresetIs(.home),
                action: {
                    controller.showExpandedPreset(.home)
                },
                innerContent: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                }
            )
            //
            DotButton(
                color: .green,
                showInner: controller.isPanelPinned(),
                action: {
                    controller.togglePinned()
                },
                innerContent: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                }
            )
            
            Divider()
                .background(.secondary)
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            
            DotButton(
                color: .cyan,
                showInner: controller.expandedPresetIs(.fastfolder),
                action: {
                    controller.showExpandedPreset(.fastfolder)
                },
                innerContent: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.cyan)
                }
            )
            DotButton(
                color: .indigo,
                showInner: controller.expandedPresetIs(.airdrop),
                action: {
                    controller.showExpandedPreset(.airdrop)
                },
                innerContent: {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.indigo)
                }
            )
            
            DotButton(
                color: .purple,
                showInner: controller.expandedPresetIs(.settings),
                action: {
                    controller.showExpandedPreset(.settings)
                },
                innerContent: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.purple)
                }
            )
        }
    }
}

#Preview {
    ZStack(alignment: .center) {
        Capsule()
            .fill(.black)
            
        
        NavigationRowView(
            terminateApplication: { NSApp.terminate(nil) }
        )
        
    }
    .frame(width: 160, height: 30)
//    .background(.red.opacity(0.4))
    .frame(width: 200, height: 100)
    .environment(AppContainer().controller)
}
