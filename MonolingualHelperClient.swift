//
//  MonolingualHelperClient.swift
//  Monolingual
//
//  Created by Ingmar Stein on 12.07.14.
//
//

import Foundation
import SMJobKit

class MonolingualHelperClient : SMJClient {
	override class var serviceIdentifier: String {
		return "net.sourceforge.MonolingualHelper"
	}
}
