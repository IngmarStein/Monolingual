//
//  ProgressView.swift
//  ProgressView
//
//  Created by Ingmar Stein on 26.09.21.
//  Copyright © 2021 Ingmar Stein. All rights reserved.
//

import SwiftUI

struct ProgressView: View {
	let task: HelperTask
	@Environment(\.dismiss) var dismiss

	/// The space a removal freed, in the style the Finder uses.
	private var spaceSaved: String {
		ByteCountFormatter.string(fromByteCount: task.byteCount, countStyle: .file)
	}

	/// Reports how the removal ended. Acknowledging the alert clears the outcome, which is
	/// also what takes this sheet down.
	private func alert(_ outcome: HelperTask.Outcome) -> Binding<Bool> {
		Binding(get: { task.outcome == outcome },
		        set: { isPresented in
			if !isPresented {
				task.outcome = nil
			}
		})
	}

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
		.alert("You cancelled the removal. Some files were erased, some were not.", isPresented: alert(.cancelled)) {
			Button("OK", role: .cancel) { dismiss() }
		} message: {
			Text("Space saved: \(spaceSaved)")
		}
		.alert("Files removed.", isPresented: alert(.completed)) {
			Button("OK", role: .cancel) { dismiss() }
		} message: {
			Text("Space saved: \(spaceSaved)")
		}
	}
}

struct ProgressView_Previews: PreviewProvider {
	static var previews: some View {
		ProgressView(task: HelperTask())
	}
}
