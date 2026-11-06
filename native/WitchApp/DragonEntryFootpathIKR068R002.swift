import Foundation

/// Off-live measured-root adaptation of the R068 entry IK. Source coordinates
/// are canonical 455x157 top-left pixels; contact progress is normalized from
/// the pinned R068 capture and scaled to the actual entry travel supplied per run.
struct DragonEntryFootpathIKR068R002 {
    struct Point: Equatable {
        var x: Double
        var y: Double
        static func +(lhs: Point, rhs: Point) -> Point { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
        static func -(lhs: Point, rhs: Point) -> Point { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    }
    struct ReferenceSample: Equatable { let elapsed: Double; let normalizedTravel: Double }
    struct LegPose {
        let hip, knee, ankle, toe: Point
        let upperDeltaRadians, lowerDeltaRadians: Double
        let stance: Bool
        let liftSourcePixels: Double
        let reachResidual: Double
    }
    struct Pose {
        let elapsed: Double
        let currentRootOffsetSourceX: Double
        let scaledReferenceOffsetSourceX: Double
        let actualEntryTravelSourceX: Double
        let bodyDropSourceY: Double
        let legs: [String: LegPose]
    }
    struct MeasuredTravelPose {
        let actionElapsed: Double
        let phaseElapsed: Double
        let normalizedTravel: Double
        let pose: Pose
    }
    enum CandidateError: Error, Equatable {
        case invalidTime
        case invalidTravel
        case coordinateConversionFailed
        case missingCoverage
        case unreachable(String, Double)
        case excessiveBodyDrop(Double)
    }
    private struct Leg {
        let hip, knee, ankle, toe: Point
        let pair: String
    }
    private struct Segment {
        let start, end: Double
        let swing: Bool
        let fromContact, toContact: Double
    }

    static let duration = 0.6
    static let sourceWidth = 455.0
    static let sourceHeight = 157.0
    static let sourceSHA256 = "66cb4bc19239fb91808e163a0bceb88cf2016bc52dbfcb3dd45045f28af83065"
    static let referenceTraceSHA256 = "077ab2b0fa579181078f4e7145f345d087238c4bbcfe70ac516a66b3785e1f11"
    static let referenceProfile: [ReferenceSample] = [
        .init(elapsed: 0.0, normalizedTravel: 0.0),
        .init(elapsed: 0.1, normalizedTravel: 0.093981993249),
        .init(elapsed: 0.2, normalizedTravel: 0.301781708984),
        .init(elapsed: 0.3, normalizedTravel: 0.522763983875),
        .init(elapsed: 0.4, normalizedTravel: 0.729486101141),
        .init(elapsed: 0.5, normalizedTravel: 0.893803659765),
        .init(elapsed: 0.6, normalizedTravel: 1.0)
    ]
    static let legGeometry: [String: (hip: Point, knee: Point, ankle: Point, toe: Point, pair: String)] = [
        "fore_far": (.init(x:52,y:85),.init(x:37,y:116),.init(x:28,y:136),.init(x:5,y:147),"A"),
        "fore_near": (.init(x:111,y:79),.init(x:112,y:111),.init(x:119,y:138),.init(x:90,y:150),"B"),
        "hind_far": (.init(x:190,y:88),.init(x:174,y:111),.init(x:177,y:130),.init(x:153,y:139),"B"),
        "hind_near": (.init(x:247,y:91),.init(x:241,y:114),.init(x:241,y:138),.init(x:216,y:150),"A")
    ]
    static let liftSourcePixels = 9.0

    init() throws {
        guard Self.referenceProfile.count >= 2,
              Self.referenceProfile.first?.elapsed == 0,
              Self.referenceProfile.first?.normalizedTravel == 0,
              Self.referenceProfile.last?.elapsed == Self.duration,
              Self.referenceProfile.last?.normalizedTravel == 1,
              Self.referenceProfile.allSatisfy({ $0.elapsed.isFinite && $0.normalizedTravel.isFinite && (0...1).contains($0.normalizedTravel) }),
              zip(Self.referenceProfile, Self.referenceProfile.dropFirst()).allSatisfy({ pair in
                  pair.0.elapsed < pair.1.elapsed && pair.0.normalizedTravel <= pair.1.normalizedTravel
              }),
              Self.legGeometry.count == 4 else { throw CandidateError.invalidTravel }
    }

    func referenceProgress(at elapsed: Double) throws -> Double {
        guard elapsed.isFinite, elapsed >= 0, elapsed <= Self.duration else { throw CandidateError.invalidTime }
        if elapsed == Self.duration { return 1 }
        for (a,b) in zip(Self.referenceProfile, Self.referenceProfile.dropFirst()) where elapsed <= b.elapsed {
            let f = (elapsed - a.elapsed) / (b.elapsed - a.elapsed)
            return a.normalizedTravel + (b.normalizedTravel - a.normalizedTravel) * f
        }
        throw CandidateError.missingCoverage
    }

    /// Inverts the pinned reference curve so stance/swing phase follows the
    /// measured arrival displacement, rather than assuming the engine's
    /// authored timing curve exactly matches SpriteKit's ease-out samples.
    func referenceElapsed(forNormalizedProgress progress: Double) throws -> Double {
        guard progress.isFinite, progress >= 0, progress <= 1 else {
            throw CandidateError.invalidTravel
        }
        if progress == 1 { return Self.duration }
        for (a, b) in zip(Self.referenceProfile, Self.referenceProfile.dropFirst())
            where progress <= b.normalizedTravel {
            let span = b.normalizedTravel - a.normalizedTravel
            guard span > 0 else { throw CandidateError.missingCoverage }
            let fraction = (progress - a.normalizedTravel) / span
            return a.elapsed + (b.elapsed - a.elapsed) * fraction
        }
        throw CandidateError.missingCoverage
    }

    /// Candidate API for actual arrival rendering: retain the real SKAction
    /// clock as a lifetime check, but derive contact phase from measured root
    /// travel. This avoids asking IK to reconcile two incompatible progress
    /// curves while preserving the fixed 0.6s entry duration.
    func poseFollowingMeasuredTravel(actionElapsed: Double,
                                     currentRootOffsetSourceX: Double,
                                     actualEntryTravelSourceX: Double) throws -> MeasuredTravelPose {
        guard actionElapsed.isFinite, actionElapsed >= 0, actionElapsed <= Self.duration,
              currentRootOffsetSourceX.isFinite, actualEntryTravelSourceX.isFinite,
              actualEntryTravelSourceX < -1e-4 else {
            throw CandidateError.invalidTravel
        }
        let normalized = currentRootOffsetSourceX / actualEntryTravelSourceX
        guard normalized.isFinite, normalized >= -0.02, normalized <= 1.02 else {
            throw CandidateError.invalidTravel
        }
        let bounded = min(1, max(0, normalized))
        let phaseElapsed = try referenceElapsed(forNormalizedProgress: bounded)
        let pose = try pose(at: phaseElapsed,
                            currentRootOffsetSourceX: currentRootOffsetSourceX,
                            actualEntryTravelSourceX: actualEntryTravelSourceX)
        return MeasuredTravelPose(actionElapsed: actionElapsed, phaseElapsed: phaseElapsed,
                                  normalizedTravel: bounded, pose: pose)
    }

    private func scaledReferenceOffset(at elapsed: Double, travel: Double) throws -> Double {
        try referenceProgress(at: elapsed) * travel
    }

    private func contact(pair: String, elapsed: Double, travel: Double) throws -> (worldOffset: Double, lift: Double, stance: Bool) {
        let segments: [Segment]
        if pair == "A" {
            segments = [
                .init(start:0,end:0.1,swing:false,fromContact:0,toContact:0),
                .init(start:0.1,end:0.2,swing:true,fromContact:0,toContact:try scaledReferenceOffset(at:0.2,travel:travel)),
                .init(start:0.2,end:0.3,swing:false,fromContact:try scaledReferenceOffset(at:0.2,travel:travel),toContact:try scaledReferenceOffset(at:0.2,travel:travel)),
                .init(start:0.3,end:0.4,swing:true,fromContact:try scaledReferenceOffset(at:0.2,travel:travel),toContact:try scaledReferenceOffset(at:0.4,travel:travel)),
                .init(start:0.4,end:0.5,swing:false,fromContact:try scaledReferenceOffset(at:0.4,travel:travel),toContact:try scaledReferenceOffset(at:0.4,travel:travel)),
                .init(start:0.5,end:0.6,swing:true,fromContact:try scaledReferenceOffset(at:0.4,travel:travel),toContact:travel)
            ]
        } else {
            segments = [
                .init(start:0,end:0.1,swing:true,fromContact:0,toContact:try scaledReferenceOffset(at:0.1,travel:travel)),
                .init(start:0.1,end:0.2,swing:false,fromContact:try scaledReferenceOffset(at:0.1,travel:travel),toContact:try scaledReferenceOffset(at:0.1,travel:travel)),
                .init(start:0.2,end:0.3,swing:true,fromContact:try scaledReferenceOffset(at:0.1,travel:travel),toContact:try scaledReferenceOffset(at:0.3,travel:travel)),
                .init(start:0.3,end:0.4,swing:false,fromContact:try scaledReferenceOffset(at:0.3,travel:travel),toContact:try scaledReferenceOffset(at:0.3,travel:travel)),
                .init(start:0.4,end:0.5,swing:true,fromContact:try scaledReferenceOffset(at:0.3,travel:travel),toContact:travel),
                .init(start:0.5,end:0.6,swing:false,fromContact:travel,toContact:travel)
            ]
        }
        for s in segments where elapsed >= s.start - 1e-10 && elapsed <= s.end + 1e-10 {
            let u = min(1, max(0, (elapsed-s.start)/(s.end-s.start)))
            guard s.swing else { return (s.fromContact,0,true) }
            let eased = u*u*(3-2*u)
            let arch = 16*u*u*(1-u)*(1-u)
            return (s.fromContact+(s.toContact-s.fromContact)*eased,Self.liftSourcePixels*arch,false)
        }
        throw CandidateError.missingCoverage
    }

    private func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x-b.x,a.y-b.y) }
    private func neededDrop(hip: Point, ankle: Point, maxReach: Double) -> Double {
        let dx=ankle.x-hip.x, dy=ankle.y-hip.y
        if abs(dx) >= maxReach { return .infinity }
        return max(0,dy-sqrt(max(0,maxReach*maxReach-dx*dx)))
    }
    private func solve(_ leg: Leg, localToeX: Double, lift: Double, bodyDrop: Double, stance: Bool) throws -> LegPose {
        let l1=distance(leg.hip,leg.knee), l2=distance(leg.knee,leg.ankle)
        let ankle=Point(x:localToeX+(leg.ankle.x-leg.toe.x),y:leg.toe.y-lift+(leg.ankle.y-leg.toe.y))
        let hip=Point(x:leg.hip.x,y:leg.hip.y+bodyDrop)
        let dx=ankle.x-hip.x,dy=ankle.y-hip.y,d=hypot(dx,dy),maxReach=l1+l2,minReach=abs(l1-l2)
        let residual=max(d-maxReach,minReach-d,0)
        guard residual <= 1e-7 else { throw CandidateError.unreachable("two_link",residual) }
        let safeD=max(d,1e-12),c=min(1,max(-1,(l1*l1+safeD*safeD-l2*l2)/(2*l1*safeD)))
        let theta=atan2(dy,dx),a=acos(c)
        let candidates=[1.0,-1.0].map { sign -> Point in
            let angle=theta+sign*a
            return Point(x:hip.x+l1*cos(angle),y:hip.y+l1*sin(angle))
        }
        let knee=candidates[0]
        func wrap(_ x: Double) -> Double { (x+Double.pi).truncatingRemainder(dividingBy:2*Double.pi)-Double.pi }
        let upper0=atan2(leg.knee.y-leg.hip.y,leg.knee.x-leg.hip.x)
        let upper=atan2(knee.y-hip.y,knee.x-hip.x)
        let lower0=atan2(leg.ankle.y-leg.knee.y,leg.ankle.x-leg.knee.x)
        let lower=atan2(ankle.y-knee.y,ankle.x-knee.x)
        return .init(hip:hip,knee:knee,ankle:ankle,toe:Point(x:localToeX,y:leg.toe.y-lift),
                     upperDeltaRadians:wrap(upper-upper0),lowerDeltaRadians:wrap(lower-lower0),
                     stance:stance,liftSourcePixels:lift,reachResidual:residual)
    }

    /// `currentRootOffsetSourceX` is measured from the actual scene/root start
    /// after SKActions. `actualEntryTravelSourceX` is measured start→home in the
    /// same projected source basis; both are signed and normally negative here.
    func pose(at elapsed: Double, currentRootOffsetSourceX: Double,
              actualEntryTravelSourceX: Double) throws -> Pose {
        guard elapsed.isFinite, elapsed >= 0, elapsed <= Self.duration else { throw CandidateError.invalidTime }
        guard currentRootOffsetSourceX.isFinite, actualEntryTravelSourceX.isFinite,
              actualEntryTravelSourceX < -1e-4,
              currentRootOffsetSourceX <= 1e-4,
              currentRootOffsetSourceX >= actualEntryTravelSourceX - max(2,abs(actualEntryTravelSourceX)*0.05) else {
            throw CandidateError.invalidTravel
        }
        let referenceOffset=try scaledReferenceOffset(at:elapsed,travel:actualEntryTravelSourceX)
        var targets:[String:(localToeX:Double,lift:Double,stance:Bool,ankle:Point,drop:Double)]=[:]
        for (name,g) in Self.legGeometry {
            let leg=Leg(hip:g.hip,knee:g.knee,ankle:g.ankle,toe:g.toe,pair:g.pair)
            let foot=try contact(pair:g.pair,elapsed:elapsed,travel:actualEntryTravelSourceX)
            let worldTarget=g.toe.x+foot.worldOffset
            let localToe=worldTarget-currentRootOffsetSourceX
            let ankle=Point(x:localToe+(g.ankle.x-g.toe.x),y:g.toe.y-foot.lift+(g.ankle.y-g.toe.y))
            let reach=distance(g.hip,g.knee)+distance(g.knee,g.ankle)
            targets[name]=(localToe,foot.lift,foot.stance,ankle,neededDrop(hip:g.hip,ankle:ankle,maxReach:reach))
            _ = leg
        }
        let drop=targets.values.map{$0.drop}.max() ?? 0
        guard drop.isFinite,drop <= 3 else { throw CandidateError.excessiveBodyDrop(drop) }
        var solved:[String:LegPose]=[:]
        for (name,g) in Self.legGeometry {
            let t=targets[name]!
            let leg=Leg(hip:g.hip,knee:g.knee,ankle:g.ankle,toe:g.toe,pair:g.pair)
            solved[name]=try solve(leg,localToeX:t.localToeX,lift:t.lift,bodyDrop:drop,stance:t.stance)
        }
        return Pose(elapsed:elapsed,currentRootOffsetSourceX:currentRootOffsetSourceX,
                    scaledReferenceOffsetSourceX:referenceOffset,actualEntryTravelSourceX:actualEntryTravelSourceX,
                    bodyDropSourceY:drop,legs:solved)
    }
}
