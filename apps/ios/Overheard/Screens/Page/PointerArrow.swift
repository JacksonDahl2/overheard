import SwiftUI

/// A loose, hand-drawn arrow from a label to its bird: a gently bowed line with a small open head.
struct PointerArrow: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // The shaft bows a little to one side, as a quick pen stroke does.
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let length = hypot(end.x - start.x, end.y - start.y)
        let normal = CGPoint(x: -(end.y - start.y) / max(length, 1), y: (end.x - start.x) / max(length, 1))
        let bow = CGPoint(x: mid.x + normal.x * length * 0.18, y: mid.y + normal.y * length * 0.18)

        p.move(to: start)
        p.addQuadCurve(to: end, control: bow)

        // The head: two short strokes back from the tip, along the curve's last direction.
        let angle = atan2(end.y - bow.y, end.x - bow.x)
        for spread in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x + cos(angle + spread) * 7, y: end.y + sin(angle + spread) * 7))
        }

        return p
    }
}
