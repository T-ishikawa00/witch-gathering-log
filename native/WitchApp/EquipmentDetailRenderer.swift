import SpriteKit
import UIKit

/// Candidate small-part layers keep the original body texture untouched. These
/// markers never grant ownership; GameModel supplies only validated equipped IDs.
@MainActor enum EquipmentDetailRenderer {
    private enum SemanticLookup {
        case notApplicable
        case noExactFrame
        case unknownLandmark
        case candidate(Registration)
    }
    struct Registration {
        let point:CGPoint
        let height:CGFloat
        let angle:CGFloat
        let clipToBody:Bool
        let visible:Bool
        let foregroundOcclusion:[OcclusionEllipse]
        let source:String
        let behindBody:Bool
        /// Optional local source-art window for a lining visible only at a hem.
        /// Coordinates are normalized to the body canvas with a top-left origin.
        let visibilityRegion:CGRect?

        init(point:CGPoint,height:CGFloat,angle:CGFloat,clipToBody:Bool,visible:Bool,foregroundOcclusion:[OcclusionEllipse]=[],source:String="legacy_fallback",behindBody:Bool=false,visibilityRegion:CGRect?=nil) {
            self.point=point
            self.height=height
            self.angle=angle
            self.clipToBody=clipToBody
            self.visible=visible
            self.foregroundOcclusion=foregroundOcclusion
            self.source=source
            self.behindBody=behindBody
            self.visibilityRegion=visibilityRegion
        }
    }
    struct OcclusionEllipse {
        /// Normalized coordinates use a top-left origin, matching source art.
        let center:CGPoint
        let radii:CGSize
    }
    static func registration(actor:String,gear:String,state:String,hand:CGPoint?,canvasAspect:CGFloat=1,body:SKSpriteNode?=nil)->Registration? {
        if ["EQ_BODY_01","EQ_BODY_02"].contains(gear),let body,
           let entry=ArtLibrary.index["DETAIL_"+gear],entry["bodyUnderlayFrameCandidate"] != nil {
            return underlayRegistration(actor:actor,gear:gear,body:body)
        }
        if actor=="AIRA",gear=="EQ_BODY_03",let body,let frame=frameRegistration(actor:actor,gear:gear,body:body) {
            return frame
        }
        if let body {
            switch semanticFrameRegistration(actor:actor,gear:gear,state:state,body:body) {
            case .candidate(let registration): return registration
            case .unknownLandmark: return nil
            case .notApplicable,.noExactFrame: break
            }
        }
        // The current static ERNA/LUNA sprites use square canvases; authored
        // 320x256 human clips place the body center around x≈130px (0.41).
        // NOIR's wider cat remains centered at x≈160px.
        let centerX:CGFloat = actor=="NOIR" || canvasAspect < 1.1 ? 0.50:0.41
        let defaultHands:[String:[String:CGPoint]]=[
            "ERNA":["idle":.init(x:0.60,y:0.40),"anticipate":.init(x:0.62,y:0.51),"execute":.init(x:0.75,y:0.48),"recover":.init(x:0.55,y:0.38),"hit":.init(x:0.52,y:0.40),"resolve":.init(x:0.63,y:0.55)],
            "LUNA":["idle":.init(x:0.61,y:0.40),"anticipate":.init(x:0.58,y:0.53),"execute":.init(x:0.69,y:0.51),"recover":.init(x:0.59,y:0.41),"hit":.init(x:0.59,y:0.42),"resolve":.init(x:0.65,y:0.53)],
            // Source pose measurements use the 320x256 authored canvas with
            // foot anchor [160,244]; points below track AIRA's visible glove
            // or handle grip instead of interpolating from the actor center.
            "AIRA":["idle":.init(x:0.37,y:0.34),"anticipate":.init(x:0.45,y:0.35),"execute":.init(x:0.50,y:0.34),"recover":.init(x:0.44,y:0.34),"hit":.init(x:0.38,y:0.34),"resolve":.init(x:0.40,y:0.33)]
        ]
        let palm=hand ?? defaultHands[actor]?[state] ?? defaultHands[actor]?["idle"] ?? CGPoint(x:0.5,y:0.4)
        if gear.hasPrefix("EQ_BODY_") {
            var point=CGPoint(x:centerX,y:gear.hasSuffix("03") ? 0.42:gear.hasSuffix("02") ? 0.25:0.29)
            if actor=="AIRA",gear=="EQ_BODY_03" {
                // Source-frame contact review caught two bad extremes: y≈0.39
                // sat on the forearm, while y≈0.55 crossed the face in runtime.
                // Keep the fur tab below the neckline at the upper chest.
                switch state {
                case "anticipate": point = .init(x:0.50,y:0.47)
                case "execute": point = .init(x:0.49,y:0.48)
                case "recover": point = .init(x:0.50,y:0.47)
                case "hit": point = .init(x:0.49,y:0.47)
                case "resolve": point = .init(x:0.52,y:0.48)
                default: point = .init(x:0.50,y:0.48)
                }
            }
            return .init(point:point,height:0.15,angle:0,clipToBody:true,visible:true)
        }
        if gear.hasPrefix("EQ_HAND_") {return .init(point:palm,height:0.10,angle:-0.15,clipToBody:true,visible:true)}
        if gear.hasPrefix("EQ_FEET_") {return .init(point:.init(x:centerX,y:0.11),height:0.13,angle:0,clipToBody:true,visible:true)}
        if gear.hasPrefix("EQ_AMU_") {
            var point=CGPoint(x:centerX,y:actor=="NOIR" ? 0.35:0.39)
            if actor=="AIRA",gear=="EQ_AMU_03" {
                // The 256px source places the sternum below the neckline around
                // x≈116–126/y≈132–140. Earlier y≈0.37–0.38 values landed on the
                // forearm in the simulator rather than on the chest.
                switch state {
                case "anticipate": point = .init(x:0.48,y:0.46)
                case "execute": point = .init(x:0.45,y:0.48)
                case "recover": point = .init(x:0.46,y:0.46)
                case "hit": point = .init(x:0.46,y:0.47)
                case "resolve": point = .init(x:0.49,y:0.48)
                default: point = .init(x:0.46,y:0.48)
                }
            }
            return .init(point:point,height:actor=="NOIR" ? 0.16:0.11,angle:0,clipToBody:false,visible:true)
        }
        if gear.hasPrefix("EQ_RING_") {return .init(point:.init(x:palm.x+0.014,y:palm.y-0.012),height:0.055,angle:0.2,clipToBody:true,visible:true)}
        if ["EQ_S_02","EQ_S_03"].contains(gear),actor=="AIRA" {
            // AIRA's authored body poses include the hammer. Register the
            // surface detail to the hammer head in each authored pose; these
            // are candidate pivots measured against the 256px source frames
            // and remain subject to simulator review.
            let p:CGPoint
            switch state {
            case "anticipate": p = .init(x:0.12,y:0.78)
            case "execute": p = .init(x:0.78,y:0.24)
            case "recover", "hit": p = .init(x:0.72,y:0.24)
            case "resolve": p = .init(x:0.15,y:0.18)
            default: p = .init(x:0.68,y:0.27)
            }
            let angle:CGFloat = state == "anticipate" ? -0.55 : state == "resolve" ? 0.35 : -0.2
            return .init(point:p,height:0.14,angle:angle,clipToBody:true,visible:true)
        }
        if ["EQ_F_01","EQ_F_02","EQ_F_03"].contains(gear),actor=="NOIR" {
            return .init(point:.init(x:0.69,y:gear=="EQ_F_01" ? 0.18:0.095),height:gear=="EQ_F_01" ? 0.20:0.38,angle:0,clipToBody:false,visible:gear=="EQ_F_01" || ["anticipate","execute","recover"].contains(state))
        }
        return nil
    }
    private static func underlayRegistration(actor:String,gear:String,body:SKSpriteNode)->Registration? {
        guard let sample=ActorBodyFrame.current(on:body),
              let candidate=ArtLibrary.index["DETAIL_"+gear]?["bodyUnderlayFrameCandidate"] as? [String:Any],
              let rows=candidate["rows"] as? [[String:Any]],
              let row=rows.first(where:{($0["actorID"] as? String)==actor && ($0["bodyAssetID"] as? String)==sample.assetID && ($0["frameIndex"] as? Int)==sample.frameIndex}),
              let canvas=row["canvas_px"] as? [Double],canvas.count==2,canvas[0]>0,canvas[1]>0,
              abs(canvas[0]-sample.canvasSize.width)<1,abs(canvas[1]-sample.canvasSize.height)<1,
              let point=row["placement_px_top_left"] as? [Double],point.count==2 else{return nil}
        var region:CGRect?
        if let rect=row["visibilityRegion_px_top_left"] as? [Double] {
            guard rect.count==4,rect.allSatisfy({$0.isFinite}),rect[2]>0,rect[3]>0,
                  rect[0]>=0,rect[1]>=0,rect[0]+rect[2]<=canvas[0],rect[1]+rect[3]<=canvas[1] else {return nil}
            region=CGRect(x:rect[0]/canvas[0],y:rect[1]/canvas[1],width:rect[2]/canvas[0],height:rect[3]/canvas[1])
        }
        return .init(point:CGPoint(x:point[0]/canvas[0],y:1-point[1]/canvas[1]),height:CGFloat(row["height"] as? Double ?? 0.07),angle:CGFloat((row["angle_degrees"] as? Double ?? 0) * .pi/180),clipToBody:false,visible:row["visible"] as? Bool ?? false,source:row["visible"] as? Bool == false ? "exact_hem_underlay_occluded_candidate":"exact_hem_underlay_candidate",behindBody:true,visibilityRegion:region)
    }
    private static func frameRegistration(actor:String,gear:String,body:SKSpriteNode)->Registration? {
        guard let sample=ActorBodyFrame.current(on:body),
              let entry=ArtLibrary.index["DETAIL_"+gear],
              let candidate=entry["frameRegistrationCandidate"] as? [String:Any],
              let rows=candidate["rows"] as? [[String:Any]],
              let row=rows.first(where:{($0["actorID"] as? String)==actor && ($0["bodyAssetID"] as? String)==sample.assetID && ($0["frameIndex"] as? Int)==sample.frameIndex}),
              let canvas=row["canvas_px"] as? [Double],canvas.count==2,canvas[0]>0,canvas[1]>0,
              let anchor=row["anchor_px_top_left"] as? [Double],anchor.count==2 else{return nil}
        let w=CGFloat(canvas[0]),h=CGFloat(canvas[1])
        guard abs(sample.canvasSize.width-w)<1,abs(sample.canvasSize.height-h)<1 else{return nil}
        let shapes=(row["foreground_occlusion_px"] as? [[String:Any]] ?? []).compactMap { shape -> OcclusionEllipse? in
            guard shape["shape"] as? String == "ellipse",
                  let center=shape["center_px"] as? [Double],center.count==2,
                  let radii=shape["radius_px"] as? [Double],radii.count==2 else{return nil}
            return .init(center:CGPoint(x:center[0]/canvas[0],y:center[1]/canvas[1]),radii:CGSize(width:radii[0]/canvas[0],height:radii[1]/canvas[1]))
        }
        return .init(point:CGPoint(x:anchor[0]/canvas[0],y:1-anchor[1]/canvas[1]),height:CGFloat((row["detail_scale"] as? Double) ?? 0.15),angle:CGFloat((row["angle_degrees"] as? Double ?? 0) * .pi / 180),clipToBody:true,visible:true,foregroundOcclusion:shapes,source:"exact_aira_frame_row")
    }
    /// Uses only a row keyed to the currently rendered authored texture. Rows
    /// without a required semantic landmark remain unresolved. Explicit source
    /// occlusion hides a part; only absence of an exact frame can use the older
    /// state-pivot candidate as an explicitly unverified fallback.
    private static func semanticFrameRegistration(actor:String,gear:String,state:String,body:SKSpriteNode)->SemanticLookup {
        guard let semantic=semanticLandmarkName(actor:actor,gear:gear) else{return .notApplicable}
        guard let sample=ActorBodyFrame.current(on:body),
              let actorEntry=ArtLibrary.index[actor],
              let candidate=actorEntry["semanticFrameLandmarksCandidate"] as? [String:Any],
              let rows=candidate["rows"] as? [[String:Any]] else{return .noExactFrame}
        guard let row=rows.first(where:{
            ($0["actorID"] as? String)==actor &&
            ($0["bodyAssetID"] as? String)==sample.assetID &&
            ($0["frameIndex"] as? Int)==sample.frameIndex
        }),
              let canvas=row["canvas_px"] as? [Double],canvas.count==2,canvas[0]>0,canvas[1]>0,
              abs(sample.canvasSize.width-canvas[0])<1,abs(sample.canvasSize.height-canvas[1])<1 else{return .noExactFrame}
        if (row["landmarkVisibility"] as? [String:String])?[semantic] == "occluded" {
            return .candidate(.init(point:.zero,height:0.01,angle:0,clipToBody:false,visible:false,source:"semantic_occluded_row"))
        }
        guard let landmarks=row["landmarks_px_top_left"] as? [String:Any],
              let raw=landmarks[semantic],let point=landmarkPoint(raw) else{return .unknownLandmark}
        let offset=semanticOffset(actor:actor,gear:gear)
        let gearOverrides=row["gear_overrides_candidate"] as? [String:[String:Any]] ?? [:]
        let family=gear.components(separatedBy:"_").dropLast().joined(separator:"_")+"_*"
        let gearOverride=gearOverrides[gear] ?? gearOverrides[family]
        let overrideOffset=(gearOverride?["offset_px"] as? [Double]).flatMap{$0.count==2 ? CGPoint(x:$0[0],y:$0[1]):nil} ?? .zero
        let normalized=CGPoint(x:(point.x+offset.x+overrideOffset.x)/canvas[0],y:1-(point.y+offset.y+overrideOffset.y)/canvas[1])
        let foregroundRows=(row["foreground_candidate_by_gear"] as? [String:[[String:Any]]])?[gear]
            ?? (gear.hasPrefix("EQ_AMU_") ? (row["foreground_candidate_by_gear"] as? [String:[[String:Any]]])?["EQ_AMU_*"] : nil)
            ?? (row["foreground_candidate"] as? [[String:Any]] ?? [])
        let foreground=foregroundRows.compactMap { shape -> OcclusionEllipse? in
            guard shape["shape"] as? String=="ellipse",
                  let center=shape["center_px"] as? [Double],center.count==2,
                  let radii=shape["radius_px"] as? [Double],radii.count==2 else{return nil}
            return .init(center:CGPoint(x:center[0]/canvas[0],y:center[1]/canvas[1]),radii:CGSize(width:radii[0]/canvas[0],height:radii[1]/canvas[1]))
        }
        let height:CGFloat
        switch gear {
        case "EQ_HAND_01","EQ_HAND_02","EQ_HAND_03": height=0.10
        case "EQ_FEET_01","EQ_FEET_02","EQ_FEET_03": height=0.13
        case "EQ_AMU_01","EQ_AMU_02","EQ_AMU_03": height=CGFloat(gearOverride?["height"] as? Double ?? (actor=="NOIR" ? 0.16:0.11))
        case "EQ_RING_01","EQ_RING_02","EQ_RING_03": height=0.055
        case "EQ_F_01": height=0.20
        case "EQ_F_03": height=0.38
        // The R002 furnace crystal occupies only a small fraction of its
        // transparent 256px canvas. Give this one hammer-head inlay a modest
        // local size increase so it remains identifiable at field scale.
        // This is a visual-fit candidate; it does not alter the source PNG.
        case "EQ_S_02": height=0.18
        default: height=0.15
        }
        let finalHeight=CGFloat(gearOverride?["height"] as? Double ?? Double(height))
        let defaultAngle:CGFloat = gear.hasPrefix("EQ_RING_") ? 0.2 : gear.hasPrefix("EQ_HAND_") ? -0.15:0
        let angle=(gearOverride?["angle_degrees"] as? Double).map{CGFloat($0 * .pi/180)} ?? defaultAngle
        let visible = gear != "EQ_F_02" && (gear != "EQ_F_03" || ["anticipate","execute","recover"].contains(state))
        let clipToBody=gear != "EQ_F_01" && gear != "EQ_F_03"
        return .candidate(.init(point:normalized,height:finalHeight,angle:angle,clipToBody:clipToBody,visible:visible,foregroundOcclusion:foreground,source:"semantic_exact_row"))
    }
    private static func semanticLandmarkName(actor:String,gear:String)->String? {
        if gear=="EQ_BODY_01" || gear=="EQ_BODY_02" {return "waist"}
        if gear=="EQ_BODY_03" {return "neck"}
        if gear.hasPrefix("EQ_AMU_") {return actor=="NOIR" ? "chest":"chest"}
        if gear.hasPrefix("EQ_RING_") {
            if actor=="ERNA" || actor=="LUNA" {return "freePalm"}
            if actor=="AIRA" {return "workingHand"}
        }
        if gear.hasPrefix("EQ_HAND_") || gear.hasPrefix("EQ_RING_") {
            if actor=="LUNA" || actor=="ERNA" {return "freeHand"}
            if actor=="AIRA" {return "workingHand"}
        }
        if gear.hasPrefix("EQ_FEET_") {return "visibleRightAnkle"}
        if ["EQ_S_02","EQ_S_03"].contains(gear),actor=="AIRA" {return "hammerHead"}
        if gear=="EQ_F_01" || gear=="EQ_F_03",actor=="NOIR" {return "catalystEffectOrigin"}
        return nil
    }
    private static func semanticOffset(actor:String,gear:String)->CGPoint {
        // BODY_HEM_INSERT is a lower-hem tab, not a shoulder/collar piece.
        if gear=="EQ_BODY_01" {return CGPoint(x:0,y:4)}
        if gear=="EQ_BODY_02" {return CGPoint(x:0,y:2)}
        return .zero
    }
    private static func landmarkPoint(_ raw:Any)->CGPoint? {
        if let xy=raw as? [Double],xy.count==2 {return CGPoint(x:xy[0],y:xy[1])}
        if let point=raw as? [String:Any],let x=point["x"] as? Double,let y=point["y"] as? Double {return CGPoint(x:x,y:y)}
        return nil
    }
    static func update(actor:String,state:String,on body:SKSpriteNode,equipment:[String:String],hand:CGPoint?=nil)->[String:Bool] {
        let actorID=GameModel.spriteIDs.first{$0.value==actor}?.key ?? ""
        let selected=equipment.filter{$0.key.hasPrefix("DETAIL|"+actorID+"|")}
        let wanted=Set(selected.values.map{"gear_detail:"+$0})
        for child in body.children where child.name?.hasPrefix("gear_detail:")==true || child.name?.hasPrefix("gear_foreground:")==true {
            guard let name=child.name else { child.removeFromParent(); continue }
            let gear=name.replacingOccurrences(of:"gear_detail:",with:"").replacingOccurrences(of:"gear_foreground:",with:"")
            if !wanted.contains("gear_detail:"+gear) { child.removeFromParent() }
        }
        var result:[String:Bool]=[:]
        let qaOnly=ProcessInfo.processInfo.arguments.contains("--qa-isolated")
        let registrationAudit=NSMutableDictionary()
        for gear in selected.values.sorted() {
            let spec=registration(actor:actor,gear:gear,state:state,hand:hand,canvasAspect:body.size.width/max(1,body.size.height),body:body)
            guard let spec else{
                body.childNode(withName:"gear_detail:"+gear)?.removeFromParent()
                body.childNode(withName:"gear_foreground:"+gear)?.removeFromParent()
                result[gear]=false
                if qaOnly {registrationAudit[gear]=["status":"no_registration","registrationSource":"unresolved","visible":false,"state":state] as NSDictionary}
                continue
            }
            let sample=ActorBodyFrame.current(on:body)
            let image=ArtLibrary.image("DETAIL_"+gear)
            if qaOnly {
                registrationAudit[gear]=[
                    "status":image == nil ? "missing_detail_image":"registered",
                    "registrationSource":spec.source,
                    "normalizedPoint":[Double(spec.point.x),Double(spec.point.y)],
                    "normalizedSize":[Double(spec.height),Double(spec.height)],
                    "normalizedHeight":Double(spec.height),
                    "angleRadians":Double(spec.angle),
                    "visible":spec.visible && image != nil,
                    "behindBody":spec.behindBody,
                    "normalizedVisibilityRegion":spec.visibilityRegion.map{[Double($0.minX),Double($0.minY),Double($0.width),Double($0.height)]} ?? [],
                    "state":state,
                    "bodyAssetID":sample?.assetID ?? "",
                    "bodyFrameIndex":sample?.frameIndex ?? -1,
                    "bodyCanvasWidth":sample?.canvasSize.width ?? 0,
                    "bodyCanvasHeight":sample?.canvasSize.height ?? 0
                ] as NSDictionary
            }
            guard let image else {
                body.childNode(withName:"gear_detail:"+gear)?.removeFromParent()
                body.childNode(withName:"gear_foreground:"+gear)?.removeFromParent()
                result[gear]=false;continue
            }
            let key="gear_detail:"+gear
            let holder:SKCropNode
            if let existing=body.childNode(withName:key) as? SKCropNode {holder=existing}else{
                holder=SKCropNode();holder.name=key;holder.zPosition=3
                let part=SKSpriteNode(texture:SKTexture(image:image));part.name="part";holder.addChild(part);body.addChild(holder)
            }
            guard let part=holder.childNode(withName:"part") as? SKSpriteNode else{result[gear]=false;continue}
            holder.zPosition=spec.behindBody ? -1:3
            part.size=CGSize(width:body.size.height*spec.height,height:body.size.height*spec.height)
            part.position=CGPoint(x:(spec.point.x-body.anchorPoint.x)*body.size.width,y:(spec.point.y-body.anchorPoint.y)*body.size.height)
            part.zRotation=spec.angle;holder.isHidden = !spec.visible
            if let region=spec.visibilityRegion {
                let mask=(holder.maskNode as? SKSpriteNode) ?? SKSpriteNode()
                mask.texture=nil;mask.color = .white;mask.colorBlendFactor=1
                mask.anchorPoint=CGPoint(x:0.5,y:0.5)
                mask.size=CGSize(width:region.width*body.size.width,height:region.height*body.size.height)
                mask.position=CGPoint(x:(region.midX-body.anchorPoint.x)*body.size.width,y:(1-region.midY-body.anchorPoint.y)*body.size.height)
                holder.maskNode=mask
            } else if spec.clipToBody {
                let mask=(holder.maskNode as? SKSpriteNode) ?? SKSpriteNode()
                mask.texture=body.texture;mask.size=body.size;mask.anchorPoint=body.anchorPoint
                mask.position = .zero;mask.colorBlendFactor=0
                holder.maskNode=mask
            } else {holder.maskNode=nil}
            let foregroundKey="gear_foreground:"+gear
            if spec.foregroundOcclusion.isEmpty {
                body.childNode(withName:foregroundKey)?.removeFromParent()
            } else {
                let front=(body.childNode(withName:foregroundKey) as? SKCropNode) ?? SKCropNode()
                front.name=foregroundKey;front.zPosition=4
                if front.parent == nil {body.addChild(front)}
                let copy=(front.children.first as? SKSpriteNode) ?? SKSpriteNode()
                copy.name="body_foreground_copy";copy.texture=body.texture;copy.size=body.size;copy.anchorPoint=body.anchorPoint
                if copy.parent == nil {front.addChild(copy)}
                let mask=front.maskNode ?? SKNode()
                let shapes=mask.children.compactMap{$0 as? SKShapeNode}
                if shapes.count>spec.foregroundOcclusion.count {
                    for shape in shapes.dropFirst(spec.foregroundOcclusion.count) { shape.removeFromParent() }
                }
                for (index,ellipse) in spec.foregroundOcclusion.enumerated() {
                    let reusable=index<shapes.count ? shapes[index] : SKShapeNode()
                    let size=CGSize(width:body.size.width*ellipse.radii.width*2,height:body.size.height*ellipse.radii.height*2)
                    reusable.path=CGPath(ellipseIn:CGRect(x:-size.width/2,y:-size.height/2,width:size.width,height:size.height),transform:nil)
                    reusable.fillColor = .white;reusable.strokeColor = .clear
                    let p=CGPoint(x:ellipse.center.x,y:1-ellipse.center.y)
                    reusable.position=CGPoint(x:(p.x-body.anchorPoint.x)*body.size.width,y:(p.y-body.anchorPoint.y)*body.size.height)
                    if reusable.parent == nil {mask.addChild(reusable)}
                }
                front.maskNode=mask
            }
            result[gear]=true
        }
        if qaOnly, ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix(EquipmentMultiConsumerRequestR084.flagPrefix) || $0.hasPrefix(EquipmentMultiConsumerRequestR084.showcaseFlagPrefix) }) {
            for gear in selected.values {
                if var row = registrationAudit[gear] as? [String: Any] {
                    row.merge(EquipmentMultiConsumerResourceProofR084.proof(assetID: "DETAIL_" + gear)) { _, new in new }
                    registrationAudit[gear] = row as NSDictionary
                }
            }
        }
        if qaOnly {
            if body.userData == nil {body.userData=NSMutableDictionary()}
            body.userData?["equipmentDetailRegistrationQA"]=registrationAudit
        }
        return result
    }
}
