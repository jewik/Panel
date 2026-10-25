//import AppKit
//#if OpenSwiftUI
//import OpenSwiftUI
//#else
//import SwiftUI
//#endif
//
//public extension View {
//    func moveToSky() -> some View {
//        modifier(SkyLightWindowModifier(destination: .lockScreen))
//    }
//
//    func addToPinnedSpace() -> some View {
//        modifier(SkyLightWindowModifier(destination: .pinned))
//    }
//}
//
//private struct SkyLightWindowModifier: ViewModifier {
//    let destination: SkyLightSpace.Destination
//
//    @State private var window: NSWindow?
//    @State private var movedWindowNumber: Int?
//
//    func body(content: Content) -> some View {
//        content
//            .background(WindowReadingView($window))
//            .onChange(of: window) {
//                moveWindowIfNeeded()
//            }
//    }
//
//    private func moveWindowIfNeeded() {
//        guard let window,
//              movedWindowNumber != window.windowNumber else {
//            return
//        }
//
//        SkyLightSpace.shared.add(window, to: destination)
//        movedWindowNumber = window.windowNumber
//    }
//}
