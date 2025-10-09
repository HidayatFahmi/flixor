//
//  MyListView.swift
//  FlixorMac
//
//  Watchlist/My List screen
//

import SwiftUI

struct MyListView: View {
    var body: some View {
        VStack {
            Text("My List")
                .font(.largeTitle)
                .padding()

            Text("Watchlist will go here")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("My List")
    }
}

#Preview {
    MyListView()
}
