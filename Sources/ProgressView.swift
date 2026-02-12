//
//  ProgressView.swift
//  ProgressView
//
//  Created by Ingmar Stein on 26.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct ProgressView: View {
	@State private var showingCancelledAlert = false
	@State private var showingCompletedAlert = false
	let task: HelperTask
	@Environment(\.dismiss) var dismiss

	private let byteCountFormatter: Formatter = {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .file
		return formatter
	}()

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(task.text)
				.font(.headline)
			Text(task.file)
				.font(.subheadline)
			HStack {
				SwiftUI.ProgressView()
					.progressViewStyle(.linear)
				Button("Cancel") {
					task.cancel()
				}
			}
		}
		.padding()
		.alert("You cancelled the removal. Some files were erased, some were not.", isPresented: $showingCancelledAlert) {
			// alertStyle = .informational
			Button("OK", role: .cancel) { dismiss() }
		} message: {
			Text("Space saved: \(byteCountFormatter.string(for: task.byteCount)!)")
		}
		.alert("Files removed.", isPresented: $showingCompletedAlert) {
			// alertStyle = .informational
			Button("OK", role: .cancel) { dismiss() }
		} message: {
			Text("Space saved: \(byteCountFormatter.string(for: task.byteCount)!)")
		}
	}
}

struct ProgressView_Previews: PreviewProvider {
	static var previews: some View {
		ProgressView(task: HelperTask())
	}
}
