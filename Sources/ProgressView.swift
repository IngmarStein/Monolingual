//
//  ProgressView.swift
//  ProgressView
//
//  Created by Ingmar Stein on 26.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct ProgressView: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Application")
				.font(.headline)
			Text("File")
				.font(.subheadline)
			HStack {
				SwiftUI.ProgressView()
					.progressViewStyle(.linear)
				Button("Cancel") {
					// TODO:
				}
			}
		}
		.padding()
	}
}

struct ProgressView_Previews: PreviewProvider {
	static var previews: some View {
		ProgressView()
	}
}
