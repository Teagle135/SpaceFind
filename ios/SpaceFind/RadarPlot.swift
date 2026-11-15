import SwiftUI

struct RadarPlot: View {
    let crew: RadarPoint
    let target: RadarPoint

    private var separation: Double { hypot(target.x - crew.x, target.y - crew.y) }

    var body: some View {
        VStack(spacing: 12) {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let half = max(0, side / 2 - 14)
                let farthest = [crew.x, crew.y, target.x, target.y].map(abs).max() ?? 0
                let extent = max(5, ceil(farthest / 5) * 5)
                func project(_ point: RadarPoint) -> CGPoint {
                    CGPoint(x: centre.x + point.x / extent * half, y: centre.y - point.y / extent * half)
                }
                var axes = Path()
                axes.move(to: CGPoint(x: centre.x, y: centre.y - half))
                axes.addLine(to: CGPoint(x: centre.x, y: centre.y + half))
                axes.move(to: CGPoint(x: centre.x - half, y: centre.y))
                axes.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
                context.stroke(axes, with: .color(.secondary.opacity(0.3)), lineWidth: 1)

                let photo = project(target)
                let person = project(crew)
                context.stroke(Path(ellipseIn: CGRect(x: photo.x - 10, y: photo.y - 10, width: 20, height: 20)),
                               with: .color(.orange), lineWidth: 4)
                context.fill(Path(ellipseIn: CGRect(x: person.x - 5, y: person.y - 5, width: 10, height: 10)),
                             with: .color(.blue))
            }
            .aspectRatio(1, contentMode: .fit)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)

            HStack(spacing: 22) {
                Label("You", systemImage: "circle.fill").foregroundStyle(.blue)
                Label("Photo spot", systemImage: "circle").foregroundStyle(.orange)
            }
            .font(.subheadline)
            Text("Estimated separation \(separation.formatted(.number.precision(.fractionLength(1)))) m")
                .font(.headline.monospacedDigit())
        }
    }
}
