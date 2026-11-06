import Foundation

/// Pure timing/pose candidate for alternating diagonal pairs. It does not
/// modify the R061 SpriteKit renderer or define approved gait values.
struct GaitContactScheduleR064 {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    struct Pose: Equatable {
        let phaseSeconds: Double
        let isStance: Bool
        let lowerAngleRadians: Double
        let wristAngleRadians: Double
        let wristOffset: Point
        let toeOffset: Point

        func toePosition(home: Point) -> Point {
            Point(x: home.x + wristOffset.x + toeOffset.x,
                  y: home.y + wristOffset.y + toeOffset.y)
        }
    }

    enum LegID: String, CaseIterable {
        case foreNear, hindFar, foreFar, hindNear

        var phaseOffsetSeconds: Double {
            switch self {
            case .foreNear, .hindFar: return 0
            case .foreFar, .hindNear: return 0.6
            }
        }
    }

    static let periodSeconds = 1.2
    static let stanceSeconds = 0.6
    static let swingSeconds = periodSeconds - stanceSeconds

    // Deliberately restrained test amplitudes; they are not approved art or
    // locomotion parameters. Coordinate y is positive upward in SpriteKit.
    static let stridePixels = 3.0
    static let liftPixels = 9.0
    static let lowerFlexRadians = 0.22
    static let wristFlexRadians = 0.08

    static func sample(at elapsedSeconds: Double, leg: LegID) -> Pose? {
        guard elapsedSeconds.isFinite else { return nil }
        let raw = (elapsedSeconds + leg.phaseOffsetSeconds)
            .truncatingRemainder(dividingBy: periodSeconds)
        let phase = raw < 0 ? raw + periodSeconds : raw

        if phase < stanceSeconds {
            return Pose(phaseSeconds: phase, isStance: true,
                        lowerAngleRadians: 0, wristAngleRadians: 0,
                        wristOffset: Point(x: 0, y: 0),
                        toeOffset: Point(x: 0, y: 0))
        }

        let u = (phase - stanceSeconds) / swingSeconds
        // Smooth zero-velocity endpoints prevent a transform jump at either
        // swing/stance transition. The toe starts and ends at its home point.
        let arc = sin(Double.pi * u)
        let excursion = 0.5 - 0.5 * cos(2 * Double.pi * u)
        let easedFlex = arc * arc
        return Pose(phaseSeconds: phase, isStance: false,
                    lowerAngleRadians: -lowerFlexRadians * easedFlex,
                    wristAngleRadians: -wristFlexRadians * easedFlex,
                    wristOffset: Point(x: 0, y: liftPixels * easedFlex),
                    toeOffset: Point(x: -stridePixels * excursion, y: 0))
    }
}
