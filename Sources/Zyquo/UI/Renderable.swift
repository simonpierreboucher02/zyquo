import Foundation

public protocol Renderable: Sendable {
    func render(in region: Region, theme: Theme) -> CellBuffer
    func sizeThatFits(_ available: Size) -> Size
    var isAnimated: Bool { get }
}

extension Renderable {
    public var isAnimated: Bool { false }
    public func sizeThatFits(_ available: Size) -> Size { available }
}
