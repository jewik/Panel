
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
                showInner: controller.checkPreset(.home),
                action: {
                    controller.showPreset(.home)
                },
                innerContent: {
                    Image(systemName:
                            controller.checkPreset(.home) ?
                          "house.fill":
                            "house"
                    )
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
                    Image(
                        systemName: controller.isPanelPinned() ?
                        "pin.fill":
                            "pin"
                    )
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
                showInner: controller.checkPreset(.fastfolder),
                action: {
                    controller.showPreset(.fastfolder)
                },
                innerContent: {
                    Image(
                        systemName: controller.checkPreset(.fastfolder) ?
                        "folder.fill":
                            "folder"
                    )
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.cyan)
                }
            )
            DotButton(
                color: .indigo,
                showInner: controller.checkPreset(.airdrop),
                action: {
                    controller.showPreset(.airdrop)
                },
                innerContent: {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.indigo)
                }
            )
            
            DotButton(
                color: .purple,
                showInner: controller.checkPreset(.settings),
                action: {
                    controller.showPreset(.settings)
                },
                innerContent: {
                    Image(systemName:
                            controller.checkPreset(.settings) ?
                          "gearshape.fill":
                            "gearshape"
                    )
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
