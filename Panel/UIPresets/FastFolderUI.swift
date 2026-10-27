//
//  FastFolder.swift
//  Panel
//
//  Created by Usanin Ivan on 27.10.2026.
//


import SwiftUI

struct FastFolderUI: View {
    var body: some View {
        ZStack(alignment: .center) {
            RoundedRectangle(cornerRadius: 30)
                .fill(.blue.opacity(0.5))

            Text("FastFolder")
        }
        .padding(10)
        .frame(width: 400, height: 100)
    }
}
