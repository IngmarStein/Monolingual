//
//  Set.swift
//  Monolingual
//
//  Created by Ingmar Stein on 16.07.14.
//
// See https://github.com/robrix/Set/blob/master/Set/Set.swift

import Foundation

/// A set of unique elements.
struct Set<Element : Hashable> {
	var _dictionary : [Element : Void]

	init() {
		_dictionary = [Element : Void]()
	}
	
	init<S : Sequence where S.GeneratorType.Element == Element>(_ sequence: S) {
		_dictionary = [Element : Void]()
		extend(sequence)
	}
	
	init(array: [Element]) {
		_dictionary = [Element : Void](minimumCapacity: array.count)
		for value in array {
			insert(value)
		}
	}
	
	var count: Int { return _dictionary.count }

	func contains(element : Element) -> Bool {
		return _dictionary.indexForKey(element) != nil
	}
	
	mutating func insert(element : Element) {
		_dictionary[element] = ()
	}
	
	mutating func remove(element : Element) {
		_dictionary.removeValueForKey(element)
	}
}

/// Sequence conformance.
extension Set : Sequence {
	typealias GeneratorType = MapSequenceGenerator<Dictionary<Element, Void>.GeneratorType, Element>
	
	func generate() -> GeneratorType {
		return _dictionary.keys.generate()
	}
}

/// Collection conformance.
///
/// Does not actually conform to Collection because that crashes the compiler.
extension Set {//: Swift.Collection {
	typealias IndexType = DictionaryIndex<Element, Void>
	var startIndex: IndexType { return _dictionary.startIndex }
	var endIndex: IndexType { return _dictionary.endIndex }

	subscript(v: ()) -> Element {
		get { return _dictionary[_dictionary.startIndex].0 }
		set { insert(newValue) }
	}
	
	subscript(index: IndexType) -> Element {
		return _dictionary[index].0
	}
}

/// ExtensibleCollection conformance.
///
/// Does not actually conform to ExtensibleCollection because that crashes the compiler.
extension Set {//: Swift.ExtensibleCollection {
	/// In theory, reserve capacity for \c n elements. However, Dictionary does not implement reserveCapacity(), so we just silently ignore it.
	func reserveCapacity(n: IndexType.DistanceType) {}
	
	/// Inserts each element of \c sequence into the receiver.
	mutating func extend<S : Sequence where S.GeneratorType.Element == Element>(sequence: S) {
		// Note that this should just be for each in sequence; this is working around a compiler crasher.
		for each in [Element](sequence) {
			insert(each)
		}
	}
}

/// Creates and returns the union of \c set and \c sequence.
func + <S : Sequence> (set: Set<S.GeneratorType.Element>, sequence: S) -> Set<S.GeneratorType.Element> {
	var union = Set(set)
	union += sequence
	return union
}


/// Extends /c set with the elements of /c sequence.
@assignment func += <S : Sequence> (inout set: Set<S.GeneratorType.Element>, sequence: S) {
	set.extend(sequence)
}


/// ArrayLiteralConvertible conformance.
extension Set : ArrayLiteralConvertible {
	static func convertFromArrayLiteral(elements: Element...) -> Set<Element> {
		return Set(elements)
	}
}


/// Equatable conformance.
func == <Element : Hashable> (a: Set<Element>, b: Set<Element>) -> Bool {
	return a._dictionary == b._dictionary
}


/// Set is reducible.
extension Set {
	func reduce<Into>(initial: Into, combine: (Into, Element) -> Into) -> Into {
		return Swift.reduce(self, initial, combine)
	}
}


/// Printable conformance.
extension Set : Printable {
	var description: String {
	if self.count == 0 { return "{}" }
		
		let joined = join(", ", map(self) { toString($0) })
		return "{ \(joined) }"
	}
}


/// Hashable conformance.
///
/// This hash function has not been proven in this usage, but is based on Bob Jenkins’ one-at-a-time hash.
extension Set : Hashable {
	var hashValue: Int {
	var h = reduce(0) { into, each in
		var h = into + each.hashValue
		h += (h << 10)
		h ^= (h >> 6)
		return h
		}
		h += (h << 3)
		h ^= (h >> 11)
		h += (h << 15)
		return h
	}
}
