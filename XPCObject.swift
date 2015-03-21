//
//  XPCObject.swift
//  Monolingual
//
//  Created by Ingmar Stein on 21.07.14.
//
//

import Foundation

public enum XPCObject : Printable, DebugPrintable {
	case XPCBool(xpc_object_t)
	case XPCInt64(xpc_object_t)
	case XPCUInt64(xpc_object_t)
	case XPCString(xpc_object_t)
	case XPCDouble(xpc_object_t)
	case XPCData(xpc_object_t)
	case XPCArray(xpc_object_t)
	case XPCDictionary(xpc_object_t)
	case _Invalid

	init(_ object : xpc_object_t) {
		let type = xpc_get_type(object)
		switch type {
		case xpc_type_bool:
			self = .XPCBool(object)
		case xpc_type_int64:
			self = .XPCInt64(object)
		case xpc_type_uint64:
			self = .XPCUInt64(object)
		case xpc_type_string:
			self = .XPCString(object)
		case xpc_type_double:
			self = .XPCDouble(object)
		case xpc_type_data:
			self = .XPCData(object)
		case xpc_type_array:
			self = .XPCArray(object)
		case xpc_type_dictionary:
			self = .XPCDictionary(object)
		default:
			assert(false, "invalid XPC object type")
			self = ._Invalid
		}
	}

	init(_ value : Bool) {
		self = .XPCBool(xpc_bool_create(value))
	}
	
	init(_ value : Int64) {
		self = .XPCInt64(xpc_int64_create(value))
	}
	
	init(_ value : UInt64) {
		self = .XPCUInt64(xpc_uint64_create(value))
	}
	
	init(_ value : String) {
		let nsstring : NSString = value
		self = .XPCString(xpc_string_create(nsstring.UTF8String))
	}
	
	init(_ value : Double) {
		self = .XPCDouble(xpc_double_create(value))
	}
	
	init(_ value : NSData) {
		self = .XPCData(xpc_data_create(value.bytes, value.length))
	}

	init(_ array: [XPCObject]) {
		let xpc_array = xpc_array_create(nil, 0)
		for value in array {
			xpc_array_set_value(xpc_array, kXPC_ARRAY_APPEND, value.object)
		}
		self = .XPCArray(xpc_array)
	}

	init(_ dictionary: [String:XPCObject]) {
		let xpc_dictionary = xpc_dictionary_create(nil, nil, 0)
		for (key, value) in dictionary {
			key.withCString { xpc_dictionary_set_value(xpc_dictionary, $0, value.object) }
		}
		self = .XPCDictionary(xpc_dictionary)
	}
	
	var object : xpc_object_t! {
	switch self {
	case XPCBool(let value):
		return value
	case XPCInt64(let value):
		return value
	case XPCUInt64(let value):
		return value
	case XPCString(let value):
		return value
	case XPCDouble(let value):
		return value
	case XPCData(let value):
		return value
	case .XPCArray(let value):
		return value
	case .XPCDictionary(let value):
		return value
	default:
		return nil
	}
	}

	public var description : String {
	switch (self) {
	case XPCBool(let value):
		return xpc_bool_get_value(value).description
	case XPCInt64(let value):
		return xpc_int64_get_value(value).description
	case XPCUInt64(let value):
		return xpc_uint64_get_value(value).description
	case XPCString(let value):
		return String.fromCString(xpc_string_get_string_ptr(value))!
	case XPCDouble(let value):
		return xpc_double_get_value(value).description
	case XPCData(let value):
		return value.description
	case XPCArray(let value):
		return value.description
	case XPCDictionary(let value):
		return value.description
	default:
		return ""
	}
	}

	public var debugDescription : String {
		return description
	}
}

extension XPCObject : ArrayLiteralConvertible {
	public init(arrayLiteral elements: XPCObject...) {
		self.init(elements)
	}
}

extension XPCObject : DictionaryLiteralConvertible {
	public init(dictionaryLiteral elements: (String, XPCObject)...) {
		var dict = [String:XPCObject]()
		for (k, v) in elements {
			dict[k] = v
		}
		
		self.init(dict)
	}
}
/*
extension Bool {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension Int64 {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension UInt64 {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension String {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension Double {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension NSData {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension Array {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}

extension Dictionary {
	func __conversion() -> XPCObject {
		return XPCObject(self)
	}
}
*/