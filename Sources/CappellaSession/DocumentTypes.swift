import UniformTypeIdentifiers

public extension UTType {
    static let cappellaProject = UTType(exportedAs: "org.cappella-rewrite.project", conformingTo: .json)
    static let detx = UTType(importedAs: "org.cappella-rewrite.detx", conformingTo: .xml)
}
