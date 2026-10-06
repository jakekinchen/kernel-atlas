import AppKit
import SceneKit
import SwiftUI
import Metal

private struct Mesh {
    var vertices:[SCNVector3]=[], normals:[SCNVector3]=[], colors:[Float]=[], indices:[Int32]=[]
    mutating func quad(_ points:[SCNVector3],_ normal:SCNVector3,_ color:NSColor) {
        let start=Int32(vertices.count); let c=color.usingColorSpace(.sRGB)!
        for p in points {vertices.append(p);normals.append(normal);colors += [pow(Float(c.redComponent),2.2),pow(Float(c.greenComponent),2.2),pow(Float(c.blueComponent),2.2),1]}
        indices += [start,start+1,start+2,start,start+2,start+3]
    }
    mutating func box(x:Float,z:Float,w:Float,d:Float,h:Float,color:NSColor) {
        let a=x-w/2,b=x+w/2,c=z-d/2,e=z+d/2
        quad([.init(a,h,c),.init(a,h,e),.init(b,h,e),.init(b,h,c)],.init(0,1,0),color)
        quad([.init(a,0,c),.init(a,h,c),.init(b,h,c),.init(b,0,c)],.init(0,0,-1),color.blended(withFraction:0.18,of:.black)!)
        quad([.init(b,0,e),.init(b,h,e),.init(a,h,e),.init(a,0,e)],.init(0,0,1),color.blended(withFraction:0.30,of:.black)!)
        quad([.init(a,0,e),.init(a,h,e),.init(a,h,c),.init(a,0,c)],.init(-1,0,0),color.blended(withFraction:0.22,of:.black)!)
        quad([.init(b,0,c),.init(b,h,c),.init(b,h,e),.init(b,0,e)],.init(1,0,0),color.blended(withFraction:0.08,of:.black)!)
        quad([.init(a,0,e),.init(a,0,c),.init(b,0,c),.init(b,0,e)],.init(0,-1,0),color)
    }
    func geometry()->SCNGeometry {
        let cd=colors.withUnsafeBufferPointer{Data(buffer:$0)}
        let cs=SCNGeometrySource(data:cd,semantic:.color,vectorCount:vertices.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
        let g=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),cs],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let m=SCNMaterial();m.diffuse.contents=NSColor.white;m.lightingModel = .lambert
        m.roughness.contents=0.8;m.isDoubleSided=false;g.materials=[m];return g
    }
}

final class AtlasScene {
    let scene=SCNScene(), camera=SCNNode(), world=SCNNode(), city=SCNNode()
    let links=SCNNode(), selection=SCNNode(), labels=SCNNode()
    let sourceTiles=SourceTileRenderer()
    weak var view:AtlasSCNView?
    weak var store:AtlasStore?
    var heights:[Int:Float]=[:]
    var triangleFiles:[Int]=[]
    var heading:CGFloat = -0.30, elevation:CGFloat = 0.78, scale:Double=76
    var target=SCNVector3(0,0,0)
    var lastSignature="", lastHome = -1, lastFocus = -1, lastZoom:Double=0
    var currentMode=AtlasMode.landscape
    var currentMetric=HeightMetric.branches
    var buildMilliseconds:Double=0
    var visibleLinkCount=0
    var deviceName:String {view?.device?.name ?? MTLCreateSystemDefaultDevice()?.name ?? "Metal unavailable"}
    init(store:AtlasStore) {
        self.store=store
        sourceTiles.atlas=self
        scene.background.contents=NSColor(hex:"0D1929")
        scene.rootNode.addChildNode(world);world.addChildNode(city);world.addChildNode(links);world.addChildNode(selection);world.addChildNode(labels)
        camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.zNear=0.1;camera.camera?.zFar=600
        camera.camera?.wantsHDR=false;camera.camera?.automaticallyAdjustsZRange=false
        scene.rootNode.addChildNode(camera)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient
        ambient.light?.color=NSColor(hex:"C9DAEF");ambient.light?.intensity=300;scene.rootNode.addChildNode(ambient)
        let sun=SCNNode();sun.light=SCNLight();sun.light?.type = .directional;sun.light?.intensity=650
        sun.light?.color=NSColor(hex:"E9F2FF");sun.eulerAngles=SCNVector3(-1.1,-0.45,-0.3)
        sun.light?.castsShadow=true;sun.light?.shadowMode = .deferred;sun.light?.shadowColor=NSColor(white:0,alpha:0.35)
        sun.light?.shadowRadius=3;sun.light?.shadowMapSize=CGSize(width:2048,height:2048);sun.light?.orthographicScale=105
        scene.rootNode.addChildNode(sun)
        let base=SCNBox(width:124,height:1.25,length:98,chamferRadius:0.8)
        let bm=SCNMaterial();bm.diffuse.contents=NSColor(hex:"20334A");bm.lightingModel = .lambert;base.materials=[bm]
        let bn=SCNNode(geometry:base);bn.position.y = -0.84;world.addChildNode(bn)
        let rim=SCNBox(width:125,height:0.18,length:99,chamferRadius:0.9)
        rim.firstMaterial?.diffuse.contents=NSColor(hex:"486079")
        let rn=SCNNode(geometry:rim);rn.position.y = -1.35;world.addChildNode(rn)
        rebuild();updateCamera(animated:false)
    }
    func height(_ f:CodeFile)->Float {
        guard currentMode == .landscape else {return 0.2}
        let value:Double
        switch currentMetric {
        case .branches:value=Double(f.branches)
        case .lines:value=Double(f.lines)/12
        case .functions:value=Double(f.functions)*2
        }
        return Float(0.45 + min(17,log2(1+value)*1.75))
    }
    func center(_ id:Int)->SCNVector3 {
        guard let f=store?.index.files[id] else{return .init()}
        return .init(Float(f.rect[0]+f.rect[2]/2-60), (heights[id] ?? 0)+0.28, Float(f.rect[1]+f.rect[3]/2-47))
    }
    func rebuild() {
        guard let store else{return};let start=CFAbsoluteTimeGetCurrent()
        var mesh=Mesh();heights=[:];triangleFiles=[]
        let hasSearch = !store.search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        var neighbors=Set<Int>()
        if store.connections,store.selectedFile != nil {
            for edge in store.relevantEdges(inbound:true)+store.relevantEdges(inbound:false) {
                neighbors.insert(store.index.symbols[edge.source].file);neighbors.insert(store.index.symbols[edge.target].file)
            }
        }
        for f in store.index.files {
            let r=f.rect,h=height(f);heights[f.id]=h
            let gap=min(0.22,min(r[2],r[3])*0.12)
            var color=store.nsColor(f.group)
            let isMuted=(store.group != nil && f.group != store.group) || (hasSearch && !store.matchingFiles.contains(f.id)) || (store.connections && store.selectedFile != nil && !neighbors.contains(f.id) && store.selectedFile != f.id)
            if isMuted {color=color.blended(withFraction:0.81,of:NSColor(hex:"17283B"))!}
            else {let shade=CGFloat((f.id*37)%17)/170; color=color.blended(withFraction:shade,of:.white)!}
            mesh.box(x:Float(r[0]+r[2]/2-60),z:Float(r[1]+r[3]/2-47),w:Float(max(0.008,r[2]-gap)),d:Float(max(0.008,r[3]-gap)),h:h,color:color)
            triangleFiles += Array(repeating:f.id,count:12)
        }
        city.geometry=mesh.geometry();city.name="city"
        updateSelection();buildMilliseconds=(CFAbsoluteTimeGetCurrent()-start)*1000
    }
    func updateSelection() {
        selection.childNodes.forEach{$0.removeFromParentNode()};links.childNodes.forEach{$0.removeFromParentNode()};visibleLinkCount=0
        guard let store, let id=store.selectedFile else{return}
        let f=store.index.files[id],p=center(id),r=f.rect
        let outline=SCNBox(width:max(0.02,r[2]-0.10),height:CGFloat(p.y+0.15),length:max(0.02,r[3]-0.10),chamferRadius:0)
        let m=SCNMaterial();m.diffuse.contents=NSColor.white;m.emission.contents=NSColor(hex:"DDF6FF");m.lightingModel = .constant;m.fillMode = .lines
        outline.materials=[m];let node=SCNNode(geometry:outline);node.position=SCNVector3(p.x,(p.y+0.15)/2,p.z);selection.addChildNode(node)
        // A restrained beacon identifies even a very small selected file.
        let beacon=SCNCylinder(radius:0.14,height:5);beacon.firstMaterial?.diffuse.contents=NSColor(hex:"F3F9FF");beacon.firstMaterial?.lightingModel = .constant
        let bn=SCNNode(geometry:beacon);bn.position=SCNVector3(p.x,p.y+2.8,p.z);selection.addChildNode(bn)
        guard store.connections else{return}
        var pairCounts:[Int:Int]=[:]
        for e in store.relevantEdges(inbound:true)+store.relevantEdges(inbound:false) {
            let a=store.index.symbols[e.source].file,b=store.index.symbols[e.target].file
            let other=a==id ? b : a
            if other != id {pairCounts[other,default:0]+=1}
        }
        for (other,_) in pairCounts.sorted(by:{$0.value == $1.value ? $0.key<$1.key : $0.value>$1.value}).prefix(28) {
            let q=center(other)
            var vertices:[SCNVector3]=[];var indices:[Int32]=[]
            let dist=hypot(q.x-p.x,q.z-p.z),arch=min(25,max(4,dist*0.28))
            for i in 0...36 {
                let t=CGFloat(i)/36
                vertices.append(.init(p.x+(q.x-p.x)*t,p.y+(q.y-p.y)*t+sin(t*CGFloat.pi)*arch,p.z+(q.z-p.z)*t))
                if i>0 {indices += [Int32(i-1),Int32(i)]}
            }
            let g=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[SCNGeometryElement(indices:indices,primitiveType:.line)])
            let lm=SCNMaterial();lm.diffuse.contents=store.nsColor(store.index.files[other].group);lm.emission.contents=store.nsColor(store.index.files[other].group);lm.lightingModel = .constant;g.materials=[lm]
            let ln=SCNNode(geometry:g);links.addChildNode(ln);visibleLinkCount+=1
        }
    }
    func apply() {
        guard let store else{return}
        let changedMode=currentMode != store.mode
        currentMode=store.mode;currentMetric=store.metric
        let sig="\(store.revision)|\(store.group ?? "")|\(store.search)|\(store.mode)|\(store.metric)|\(store.connections)"
        if sig != lastSignature {lastSignature=sig;rebuild()}
        labels.isHidden = !store.showLabels
        if changedMode {elevation=currentMode == .map ? .pi/2 : 0.78;heading=currentMode == .map ? 0 : -0.30;updateCamera(animated:true)}
        if lastHome != store.homeRevision {lastHome=store.homeRevision;home()}
        if lastFocus != store.focusRevision {lastFocus=store.focusRevision;if let id=store.selectedFile {focus(id)}}
        if lastZoom != store.zoomRequest {let delta=store.zoomRequest-lastZoom;lastZoom=store.zoomRequest;zoom(delta)}
        view?.needsDisplay=true;view?.labelOverlay.needsDisplay=true
    }
    func updateCamera(animated:Bool) {
        // Explicit Euler orientation avoids the up-vector singularity of look(at:)
        // in an exactly overhead view. Input-driven motion needs no background loop.
        camera.removeAllAnimations()
        SCNTransaction.begin();SCNTransaction.disableActions=true;SCNTransaction.animationDuration=0
        let distance:CGFloat=190
        camera.eulerAngles=SCNVector3(-elevation,heading,0)
        let px=target.x+sin(heading)*cos(elevation)*distance
        let py=target.y+sin(elevation)*distance
        let pz=target.z+cos(heading)*cos(elevation)*distance
        camera.position=SCNVector3(px,py,pz)
        camera.camera?.orthographicScale=scale
        SCNTransaction.commit();SCNTransaction.flush()
        view?.needsDisplay=true;view?.labelOverlay.needsDisplay=true
    }
    func home() {target = .init(0,2,0);scale=76;heading=currentMode == .map ? 0 : -0.30;elevation=currentMode == .map ? .pi/2 : 0.78;updateCamera(animated:true)}
    func focus(_ id:Int) {
        if currentMode == .map {sourceTiles.focus(file:id,line:store?.symbol?.line);return}
        let p=center(id);target = .init(p.x,p.y,p.z)
        if let f=store?.index.files[id] {scale=max(0.05,max(f.rect[2],f.rect[3])*0.9)}
        updateCamera(animated:false)
    }
    func planePoint(_ point:CGPoint,height:CGFloat)->SCNVector3? {
        guard let view else{return nil}
        let near=view.unprojectPoint(SCNVector3(point.x,point.y,0))
        let far=view.unprojectPoint(SCNVector3(point.x,point.y,1))
        let dy=far.y-near.y
        guard abs(dy)>0.00001 else{return nil}
        let t=(height-near.y)/dy
        return SCNVector3(near.x+(far.x-near.x)*t,height,near.z+(far.z-near.z)*t)
    }
    func zoom(_ amount:Double,around point:CGPoint? = nil) {
        let h:CGFloat=point.flatMap{pick($0)}.map{CGFloat(heights[$0] ?? 0)} ?? (currentMode == .map ? 0.2 : target.y)
        let before=point.flatMap{planePoint($0,height:h)}
        scale=min(170,max(0.002,scale*exp(max(-0.7,min(0.7,amount)))));updateCamera(animated:false)
        if let point,let before,let after=planePoint(point,height:h) {
            target.x+=before.x-after.x;target.z+=before.z-after.z;updateCamera(animated:false)
        }
    }
    func orbit(dx:CGFloat,dy:CGFloat) {guard currentMode == .landscape else {pan(dx:dx,dy:dy);return};heading-=dx*0.006;elevation=min(1.52,max(0.24,elevation+dy*0.006));updateCamera(animated:false)}
    func pan(dx:CGFloat,dy:CGFloat) {
        let s=CGFloat(scale)/max(1,view?.bounds.height ?? 800)*2
        let xx=dx*s,zz=dy*s/max(0.3,sin(elevation))
        target.x -= xx*cos(heading)+zz*sin(heading);target.z += xx*sin(heading)-zz*cos(heading)
        target.x=min(130,max(-130,target.x));target.z=min(110,max(-110,target.z));updateCamera(animated:false)
    }
    func pick(_ point:CGPoint)->Int? {
        guard let view else{return nil}
        for hit in view.hitTest(point,options:[.searchMode:SCNHitTestSearchMode.all.rawValue,.ignoreHiddenNodes:true]) where hit.node === city {
            if triangleFiles.indices.contains(hit.faceIndex) {return triangleFiles[hit.faceIndex]}
        }
        return nil
    }
    func renderImage() throws -> NSImage {
        guard let view else {throw NSError(domain:"KernelAtlas",code:2)}
        let image=view.snapshot()
        image.lockFocus()
        view.labelOverlay.draw(view.bounds)
        NSColor(hex:"102137",alpha:0.95).setFill()
        NSBezierPath(roundedRect:NSRect(x:12,y:image.size.height-51,width:254,height:39),xRadius:7,yRadius:7).fill()
        NSRect(x:0,y:0,width:image.size.width,height:38).fill()
        let titleAttributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18,weight:.medium),.foregroundColor:NSColor(hex:"DFEAF5")]
        ("Linux 1.0 / Kernel Atlas" as NSString).draw(at:NSPoint(x:22,y:image.size.height-40),withAttributes:titleAttributes)
        let caption="561 files · area: source bytes · height: \(currentMode == .map ? "flat" : currentMetric.rawValue.lowercased()+" (log scale)")"
        (caption as NSString).draw(at:NSPoint(x:22,y:18),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor(hex:"94A7BE")])
        image.unlockFocus()
        return image
    }
    func snapshot(to url:URL) throws {
        let image=try renderImage()
        guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else {throw NSError(domain:"KernelAtlas",code:2,userInfo:[NSLocalizedDescriptionKey:"The map could not be captured."])}
        try data.write(to:url)
    }
}

final class AtlasLabelOverlay:NSView {
    weak var atlas:AtlasScene?
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func draw(_ dirtyRect:NSRect) {
        guard let atlas,let store=atlas.store,let view=atlas.view else{return}
        let codeFiles=atlas.sourceTiles.draw(in:bounds)
        guard store.showLabels else{return}
        var occupied:[NSRect]=[]
        func label(_ title:String,point:SCNVector3,color:NSColor,major:Bool) {
            let p=view.projectPoint(point)
            guard p.z>0,p.z<1 else{return}
            let font=NSFont.systemFont(ofSize:major ? 11 : 10,weight:major ? .semibold : .medium)
            let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:NSColor(hex:"DFEAF5")]
            let size=(title as NSString).size(withAttributes:attrs)
            let rect=NSRect(x:p.x-size.width/2-8,y:p.y-10,width:size.width+16,height:21)
            guard bounds.insetBy(dx:7,dy:80).contains(rect),!occupied.contains(where:{$0.intersects(rect.insetBy(dx:-5,dy:-5))}) else{return}
            occupied.append(rect)
            NSColor(hex:"112237",alpha:0.91).setFill();NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5).fill()
            color.withAlphaComponent(0.65).setStroke();let outline=NSBezierPath(roundedRect:rect,xRadius:5,yRadius:5);outline.lineWidth=0.6;outline.stroke()
            (title as NSString).draw(at:NSPoint(x:rect.minX+8,y:rect.minY+4),withAttributes:attrs)
        }
        let directories=store.index.directories.filter{$0.depth==0 || (atlas.scale<50 && $0.depth==1)}.sorted{$0.depth != $1.depth ? $0.depth<$1.depth : $0.rect[2]*$0.rect[3]>$1.rect[2]*$1.rect[3]}
        for d in directories {
            if atlas.scale<12 && !codeFiles.isEmpty {continue}
            if let group=store.group,group != d.group {continue}
            let r=d.rect
            guard r[2]*r[3]>45 || atlas.scale<38 else{continue}
            let files=store.index.files.filter{$0.path.hasPrefix(d.path+"/")}
            let height=files.map{atlas.heights[$0.id] ?? 0}.max() ?? 1
            label(d.path,point:SCNVector3(Float(r[0]+r[2]/2-60),height+1,Float(r[1]+r[3]/2-47)),color:store.nsColor(d.group),major:true)
        }
        if atlas.scale<32 && (atlas.currentMode != .map || atlas.scale>=12 || !store.showCode) {
            for f in store.index.files.sorted(by:{$0.bytes>$1.bytes}) {
                if codeFiles.contains(f.id) {continue}
                let r=f.rect
                guard min(r[2],r[3])/atlas.scale*Double(bounds.height)>25 else {continue}
                if occupied.count>=42 {break}
                label(f.name,point:atlas.center(f.id),color:store.nsColor(f.group),major:false)
            }
        }
    }
}

final class AtlasSCNView:SCNView {
    let labelOverlay=AtlasLabelOverlay()
    weak var atlas:AtlasScene?
    private var start=NSPoint.zero, lastDrag=NSPoint.zero, dragged=false, tracking:NSTrackingArea?
    override var acceptsFirstResponder:Bool {true}
    override func updateTrackingAreas() {
        super.updateTrackingAreas();if let tracking {removeTrackingArea(tracking)}
        let t=NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil);addTrackingArea(t);tracking=t
    }
    override func mouseDown(with event:NSEvent) {window?.makeFirstResponder(self);start=event.locationInWindow;lastDrag=start;dragged=false}
    override func mouseDragged(with event:NSEvent) {
        let point=event.locationInWindow, dx=point.x-lastDrag.x, dy=lastDrag.y-point.y
        lastDrag=point
        if hypot(event.locationInWindow.x-start.x,event.locationInWindow.y-start.y)>3 {dragged=true}
        if dragged {if event.modifierFlags.contains(.shift) {atlas?.pan(dx:dx,dy:dy)}else{atlas?.orbit(dx:dx,dy:dy)}}
    }
    override func mouseUp(with event:NSEvent) {
        guard !dragged else{return}
        if let id=atlas?.pick(convert(event.locationInWindow,from:nil)) {atlas?.store?.select(file:id);if event.clickCount==2 {atlas?.focus(id)}}
    }
    override func rightMouseDown(with event:NSEvent) {window?.makeFirstResponder(self);lastDrag=event.locationInWindow}
    override func rightMouseDragged(with event:NSEvent) {
        let point=event.locationInWindow
        atlas?.pan(dx:point.x-lastDrag.x,dy:lastDrag.y-point.y);lastDrag=point
    }
    override func scrollWheel(with event:NSEvent) {
        if event.modifierFlags.contains(.shift) {atlas?.pan(dx:event.scrollingDeltaX,dy:event.scrollingDeltaY)}
        else {atlas?.zoom(Double(event.scrollingDeltaY)*0.008,around:convert(event.locationInWindow,from:nil))}
    }
    override func magnify(with event:NSEvent) {atlas?.zoom(-Double(event.magnification)*1.5,around:convert(event.locationInWindow,from:nil))}
    override func mouseMoved(with event:NSEvent) {let id=atlas?.pick(convert(event.locationInWindow,from:nil));if atlas?.store?.hoveredFile != id {atlas?.store?.hoveredFile=id}}
    override func mouseExited(with event:NSEvent) {atlas?.store?.hoveredFile=nil}
    override func keyDown(with event:NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "0":atlas?.store?.homeRevision+=1
        case "f":if let id=atlas?.store?.selectedFile {atlas?.focus(id)}
        case "2":atlas?.store?.mode = .map
        case "3":atlas?.store?.mode = .landscape
        case "+","=":atlas?.zoom(-0.15)
        case "-":atlas?.zoom(0.15)
        case "\u{1b}":atlas?.store?.reset()
        default:super.keyDown(with:event)
        }
    }
}

struct LandscapeView:NSViewRepresentable {
    @ObservedObject var store:AtlasStore
    func makeNSView(context:Context)->AtlasSCNView {
        let view=AtlasSCNView(frame:.zero,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        let atlas=AtlasScene(store:store);store.scene=atlas;atlas.view=view;view.atlas=atlas
        view.scene=atlas.scene;view.pointOfView=atlas.camera
        view.labelOverlay.atlas=atlas;view.labelOverlay.frame=view.bounds;view.labelOverlay.autoresizingMask=[.width,.height];view.addSubview(view.labelOverlay)
        view.antialiasingMode = .multisampling4X;view.preferredFramesPerSecond=120
        view.rendersContinuously=false;view.isPlaying=false;view.allowsCameraControl=false
        view.setAccessibilityLabel("Interactive Linux code landscape")
        view.setAccessibilityHelp("Click to inspect. Drag to orbit. Shift-drag to pan. Scroll or pinch to zoom. F focuses, 0 fits, 2 opens the map, 3 opens the landscape.")
        atlas.apply();return view
    }
    func updateNSView(_ view:AtlasSCNView,context:Context) {view.atlas?.apply()}
}
