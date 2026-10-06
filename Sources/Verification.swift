import AppKit
import SceneKit
import Metal

enum Verification {
    static func run(store:AtlasStore,window:NSWindow,output:URL) {
        do {
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            guard let atlas=store.scene,let view=atlas.view else {throw NSError(domain:"Verify",code:1)}
            let t=CFAbsoluteTimeGetCurrent();var checks:[String:Bool]=[:]
            checks["corpus_under_20_decimal_MB"]=store.index.totalBytes<20_000_000
            checks["metal_renderer"]=view.renderingAPI == .metal
            checks["idle_on_demand"] = !view.rendersContinuously && !view.isPlaying
            checks["batched_city_mesh"]=atlas.city.geometry?.elements.count == 1
            checks["all_files_have_geometry"]=atlas.triangleFiles.count == store.index.files.count*12
            checks["journey_symbols_exist"]=journeys.flatMap(\.stops).allSatisfy {stop in store.index.symbols.contains{store.index.files[$0.file].path==stop.file && $0.name==stop.symbol}}
            store.search="schedule";checks["symbol_search"]=store.hits.contains{$0.title=="schedule()"};store.search=""
            try atlas.snapshot(to:output.appendingPathComponent("landscape.png"))
            if let f=store.index.files.first(where:{$0.path=="kernel/sched.c"}),let s=store.symbolsByFile[f.id]?.first(where:{$0.name=="schedule"}) {
                store.select(file:f.id,symbol:s.id);store.connections=true;atlas.apply()
                checks["source_loading"]=store.source(f.id).contains("asmlinkage void schedule(void)")
                checks["function_calls"] = !(store.outgoing[s.id] ?? []).isEmpty
                checks["cross_file_arcs"]=atlas.visibleLinkCount>0
                try atlas.snapshot(to:output.appendingPathComponent("schedule-connections.png"))
                let point=view.projectPoint(atlas.center(f.id))
                checks["geometry_hit_testing"]=atlas.pick(CGPoint(x:CGFloat(point.x),y:CGFloat(point.y)))==f.id
            }
            store.reset();store.mode = .map;atlas.apply();atlas.updateCamera(animated:false)
            checks["map_flattens_geometry"]=atlas.heights.values.allSatisfy{$0<0.3}
            let origin=view.projectPoint(SCNVector3(0,0,0))
            let east=view.projectPoint(SCNVector3(30,0,0))
            checks["map_camera_centered"]=abs(origin.x-view.bounds.midX)<2 && abs(origin.y-view.bounds.midY)<2
            checks["map_camera_axis_aligned"]=abs(east.y-origin.y)<0.5 && east.x>origin.x
            try atlas.snapshot(to:output.appendingPathComponent("map.png"))
            // Exercise source tiles through the actual composed view, not merely layout data.
            let sourceFixture="/* comment starts\ncontinues */ int x = 7;\n\treturn \"/* literal */\";\n"+String(repeating:"x",count:245)+"\n"
            let fixture=SourceDocument(text:sourceFixture)
            let rebuilt=(1...4).map {line in fixture.rows.filter{$0.number==line}.map(\.text).joined()}
            checks["source_soft_wrap_preserves_text"]=rebuilt==["/* comment starts","continues */ int x = 7;","        return \"/* literal */\";",String(repeating:"x",count:245)]
            let short=store.index.files.first{$0.path=="fs/read_write.c"}!
            let scheduler=store.index.files.first{$0.path=="kernel/sched.c"}!
            atlas.sourceTiles.focus(file:short.id,line:1)
            try atlas.snapshot(to:output.appendingPathComponent("source-unselected-file.png"))
            checks["unselected_file_renders_real_source"]=store.selectedFile==nil && (atlas.sourceTiles.renderedRows[short.id]?.contains(1) ?? false)
            atlas.sourceTiles.focus(file:scheduler.id,line:211)
            try atlas.snapshot(to:output.appendingPathComponent("source-schedule-line-211.png"))
            checks["middle_of_large_file_renders_source"]=atlas.sourceTiles.renderedRows[scheduler.id]?.contains(211) ?? false
            checks["function_body_follows_definition_in_tile"]=(212...225).allSatisfy{atlas.sourceTiles.renderedRows[scheduler.id]?.contains($0) ?? false}
            checks["source_zoom_exceeds_old_limit"]=atlas.scale<5
            atlas.sourceTiles.focus(file:scheduler.id,line:scheduler.lines)
            try atlas.snapshot(to:output.appendingPathComponent("source-last-line.png"))
            checks["last_source_line_is_reachable"]=atlas.sourceTiles.renderedRows[scheduler.id]?.contains(scheduler.lines) ?? false
            atlas.sourceTiles.focus(file:scheduler.id,line:211)
            let anchor=CGPoint(x:view.bounds.width*0.69,y:view.bounds.height*0.43)
            let before=atlas.planePoint(anchor,height:0.2)!
            atlas.zoom(-0.45,around:anchor)
            let after=atlas.planePoint(anchor,height:0.2)!
            checks["zoom_stays_under_pointer"]=hypot(after.x-before.x,after.z-before.z)<0.0001
            _=try atlas.renderImage()
            checks["visible_source_rows_are_culled"]=atlas.sourceTiles.textRowCount>0 && atlas.sourceTiles.textRowCount<500
            let sourceImageSize=view.bounds.size
            var sourceTimes:[Double]=[]
            for i in 0..<20 {
                let start=CFAbsoluteTimeGetCurrent()
                atlas.pan(dx:i%2==0 ? 3 : -3,dy:0)
                _=try atlas.renderImage()
                sourceTimes.append((CFAbsoluteTimeGetCurrent()-start)*1000)
            }
            sourceTimes.sort()
            checks["source_cache_is_bounded"]=atlas.sourceTiles.cachedGlyphCount<=1536 && atlas.sourceTiles.cachedDocumentCount<=20
            store.showCode=false
            _=try atlas.renderImage()
            checks["source_toggle"]=atlas.sourceTiles.renderedFiles.isEmpty
            store.showCode=true
            store.mode = .landscape;atlas.apply();atlas.heading=0;atlas.elevation=1.3
            atlas.sourceTiles.focus(file:scheduler.id,line:211)
            try atlas.snapshot(to:output.appendingPathComponent("source-landscape-roof.png"))
            checks["exposed_landscape_roof_has_source"]=atlas.sourceTiles.renderedRows[scheduler.id]?.contains(211) ?? false
            store.mode = .landscape;atlas.apply();atlas.home();atlas.updateCamera(animated:false)
            let renderer=SCNRenderer(device:view.device,options:nil);renderer.scene=atlas.scene;renderer.pointOfView=atlas.camera
            let size=CGSize(width:1440,height:1000)
            for i in 0..<3 {_ = renderer.snapshot(atTime:Double(i)/60,with:size,antialiasingMode:.multisampling4X)}
            var times:[Double]=[]
            for i in 0..<24 {
                atlas.heading += 0.012;atlas.updateCamera(animated:false)
                let start=CFAbsoluteTimeGetCurrent()
                _=renderer.snapshot(atTime:Double(i+3)/60,with:size,antialiasingMode:.multisampling4X)
                times.append((CFAbsoluteTimeGetCurrent()-start)*1000)
            }
            times.sort();atlas.home();atlas.updateCamera(animated:false)
            let receipt:[String:Any]=["checks":checks,"allPassed":checks.values.allSatisfy{$0},"device":atlas.deviceName,
                "indexDecodeMs":store.loadMilliseconds,"meshBuildMs":atlas.buildMilliseconds,"verificationSeconds":CFAbsoluteTimeGetCurrent()-t,
                "renderBenchmark":["method":"SCNRenderer completed 1440x1000 snapshots; 4x MSAA; 3 warmups; 24 camera updates; includes readback","samples":times.count,"medianMs":times[times.count/2],"p95Ms":times[Int(Double(times.count-1)*0.95)],"minMs":times.first!,"maxMs":times.last!],
                "sourceBenchmark":["method":"Completed native scene snapshot plus visible CoreText source, labels and camera pan; no PNG encoding; warm cache","width":sourceImageSize.width,"height":sourceImageSize.height,"samples":sourceTimes.count,"medianMs":sourceTimes[sourceTimes.count/2],"p95Ms":sourceTimes[Int(Double(sourceTimes.count-1)*0.95)],"cachedGlyphs":atlas.sourceTiles.cachedGlyphCount,"cachedDocuments":atlas.sourceTiles.cachedDocumentCount],
                "displayRefreshFPS":"Not inferred from offscreen timings","renderAPI":"Metal","continuousRendering":view.rendersContinuously]
            let data=try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]);try data.write(to:output.appendingPathComponent("app-verification.json"))
            print(String(data:data,encoding:.utf8)!)
        }catch{try? error.localizedDescription.write(to:output.appendingPathComponent("verification-error.txt"),atomically:true,encoding:.utf8)}
    }
}
