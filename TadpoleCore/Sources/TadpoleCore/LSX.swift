// Larian's .lsx files: XML with <region>s holding nested <node>s, each with
// typed <attribute>s. meta.lsx (a mod's description) and modsettings.lsx
// (which mods load, in order) are both .lsx.

import Foundation

public struct LSXNode: Sendable, Equatable {
    public var id: String
    public var attributes: [LSXAttribute] = []
    public var children: [LSXNode] = []

    public init(id: String, attributes: [LSXAttribute] = [], children: [LSXNode] = []) {
        self.id = id
        self.attributes = attributes
        self.children = children
    }

    public subscript(attribute name: String) -> String? {
        attributes.first { $0.id == name }?.value
    }

    /// Every node below this one (depth first) with this id.
    public func descendants(_ id: String) -> [LSXNode] {
        children.flatMap { ($0.id == id ? [$0] : []) + $0.descendants(id) }
    }
}

public struct LSXAttribute: Sendable, Equatable {
    public var id: String
    public var type: String
    public var value: String

    public init(id: String, type: String, value: String) {
        self.id = id
        self.type = type
        self.value = value
    }
}

public struct LSXDocument: Sendable, Equatable {
    /// <version major= minor= revision= build=/>, kept as found.
    public var version: [String: String]
    public var regions: [LSXNode]  // a region is a node named after its id

    public func region(_ id: String) -> LSXNode? { regions.first { $0.id == id } }

    public static func parse(_ data: Data) throws -> LSXDocument {
        let delegate = LSXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw LSXError.invalid(parser.parserError?.localizedDescription ?? "unreadable XML")
        }
        return LSXDocument(version: delegate.version, regions: delegate.regions)
    }
}

public enum LSXError: LocalizedError, Equatable {
    case invalid(String)
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let detail): "This .lsx file can't be read: \(detail)"
        case .missing(let what): "This .lsx file has no \(what)."
        }
    }
}

private final class LSXParserDelegate: NSObject, XMLParserDelegate {
    var version: [String: String] = [:]
    var regions: [LSXNode] = []
    private var stack: [LSXNode] = []  // the region, then open nodes

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "version":
            version = attributes
        case "region":
            stack = [LSXNode(id: attributes["id"] ?? "")]
        case "node":
            stack.append(LSXNode(id: attributes["id"] ?? ""))
        case "attribute":
            guard !stack.isEmpty else { return }
            // TranslatedString attributes carry a handle instead of a value.
            let value = attributes["value"] ?? attributes["handle"] ?? ""
            stack[stack.count - 1].attributes.append(LSXAttribute(id: attributes["id"] ?? "", type: attributes["type"] ?? "", value: value))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "node":
            guard stack.count > 1, let node = stack.popLast() else { return }
            stack[stack.count - 1].children.append(node)
        case "region":
            if let region = stack.first { regions.append(region) }
            stack = []
        default:
            break
        }
    }
}

extension String {
    /// Escaped for an XML attribute value.
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
