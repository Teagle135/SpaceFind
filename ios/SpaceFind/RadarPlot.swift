import SwiftUI

struct RadarPlot: View {
    let crew: RadarPoint
    let target: RadarPoint

    private var separation: Double { hypot(target.x - crew.x, target.y - crew.y) }

    private var displayedExtent: Double {
        let farthest = [crew.x, crew.y, target.x, target.y].map(abs).max() ?? 0
        let roundedExtent = ceil(farthest / 5) * 5
        return max(5, max(farthest, roundedExtent.isFinite ? roundedExtent : farthest))
    }

    private var separationDescription: String {
        separation.isFinite ? "\(formatMeters(separation)) m" : "beyond the numeric range"
    }

    private func formatMeters(_ distance: Double) -> String {
        distance < 1_000
            ? distance.formatted(.number.precision(.fractionLength(1)))
            : distance.formatted(.number.notation(.scientific).precision(.significantDigits(3)))
    }

    private func positionDescription(_ point: RadarPoint) -> String {
        "\(formatMeters(abs(point.x))) m \(point.x < 0 ? "left" : "right"), " +
        "\(formatMeters(abs(point.y))) m \(point.y < 0 ? "back" : "forward")"
    }

    private var accessibilityDescription: String {
        "You: \(positionDescription(crew)). Photo spot: \(positionDescription(target)). " +
        "Estimated separation: \(separationDescription)."
    }

    var body: some View {
        VStack(spacing: 12) {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let half = max(0, side / 2 - 14)
                let extent = displayedExtent
                func project(_ point: RadarPoint) -> CGPoint {
                    CGPoint(x: centre.x + point.x / extent * half, y: centre.y - point.y / extent * half)
                }
                var rings = Path()
                for radius in [half / 2, half] {
                    rings.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                width: radius * 2, height: radius * 2))
                }
                context.stroke(rings, with: .color(CrewTheme.divider.opacity(0.55)), lineWidth: 1)

                var axes = Path()
                axes.move(to: CGPoint(x: centre.x, y: centre.y - half))
                axes.addLine(to: CGPoint(x: centre.x, y: centre.y + half))
                axes.move(to: CGPoint(x: centre.x - half, y: centre.y))
                axes.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
                context.stroke(axes, with: .color(CrewTheme.divider), lineWidth: 1)

                let photo = project(target)
                let person = project(crew)
                context.stroke(Path(ellipseIn: CGRect(x: photo.x - 10, y: photo.y - 10, width: 20, height: 20)),
                               with: .color(CrewTheme.accent), lineWidth: 4)
                context.fill(Path(ellipseIn: CGRect(x: person.x - 5, y: person.y - 5, width: 10, height: 10)),
                             with: .color(CrewTheme.ink))
            }
            .aspectRatio(1, contentMode: .fit)
            .background(CrewTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)

            HStack(spacing: 22) {
                Label("You", systemImage: "circle.fill").foregroundStyle(CrewTheme.ink)
                Label("Photo spot", systemImage: "circle").foregroundStyle(CrewTheme.accent)
            }
            .font(.subheadline)
            Text("Inner ring \(formatMeters(displayedExtent / 2)) m · outer ring \(formatMeters(displayedExtent)) m")
                .font(.caption.monospacedDigit())
                .foregroundStyle(CrewTheme.ink)
            Text("Estimated separation \(separationDescription)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(CrewTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
