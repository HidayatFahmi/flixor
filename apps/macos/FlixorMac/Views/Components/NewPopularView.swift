//
//  NewPopularView.swift
//  FlixorMac
//
//  New & Popular screen
//

import SwiftUI

struct NewPopularView: View {
    var body: some View {
        VStack {
            Text("New & Popular")
                .font(.largeTitle)
                .padding()

            Text("New and popular content will go here")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("New & Popular")
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    NewPopularView()
}
#endif
