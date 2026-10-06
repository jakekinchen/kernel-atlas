import SwiftUI
import AppKit

struct QuietButton:ButtonStyle {
    var active=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12,weight:.medium)).foregroundStyle(active ? ink : secondaryInk)
            .padding(.horizontal,11).padding(.vertical,8)
            .background(active ? Color(hex:"2D435D") : configuration.isPressed ? Color(hex:"263B52") : Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:7))
    }
}
struct AtlasRoot:View {
    @ObservedObject var store:AtlasStore
    @FocusState private var searchFocused:Bool
    var body:some View {
        HStack(spacing:0) {
            sidebar.frame(width:214)
            Divider().overlay(Color.white.opacity(0.07))
            VStack(spacing:0) {
                header
                Divider().overlay(Color.white.opacity(0.07))
                HStack(spacing:0) {
                    VStack(spacing:0) {mapToolbar;map;legend}
                    Divider().overlay(Color.white.opacity(0.07))
                    Inspector(store:store).frame(width:326)
                }
            }
        }
        .background(Color(hex:"0D1929")).foregroundStyle(ink)
        .preferredColorScheme(.dark)
        .frame(minWidth:1120,minHeight:720)
        .sheet(isPresented:$store.sourceOpen) {SourceSheet(store:store)}
        .sheet(isPresented:$store.infoOpen) {AboutSheet(store:store)}
        .alert("Kernel Atlas",isPresented:Binding(get:{store.errorMessage != nil},set:{if !$0 {store.errorMessage=nil}})) {Button("OK"){store.errorMessage=nil}} message:{Text(store.errorMessage ?? "")}
        .background {
            Button(""){searchFocused=true}.keyboardShortcut("f",modifiers:.command).hidden()
            Button(""){store.homeRevision+=1}.keyboardShortcut("0",modifiers:.command).hidden()
            Button(""){if store.file != nil {store.sourceOpen=true}}.keyboardShortcut("o",modifiers:.command).hidden()
        }
    }
    var sidebar:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(systemName:"square.stack.3d.up.fill").font(.system(size:25,weight:.light)).foregroundStyle(Color(hex:"A3CBE3"))
                VStack(alignment:.leading,spacing:2){Text("Kernel Atlas").font(.system(size:16,weight:.semibold));Text("A source code observatory").font(.system(size:10)).foregroundStyle(secondaryInk)}
            }.padding(.horizontal,18).padding(.top,23).padding(.bottom,29)
            HStack(spacing:7){Image(systemName:"magnifyingglass").foregroundStyle(secondaryInk);TextField("Find a file or function",text:$store.search).textFieldStyle(.plain).font(.system(size:11)).focused($searchFocused);if !store.search.isEmpty{Button{store.search=""}label:{Image(systemName:"xmark.circle.fill")}.buttonStyle(.plain)}}
                .padding(9).background(Color(hex:"1B2D43"),in:RoundedRectangle(cornerRadius:7)).padding(.horizontal,14).padding(.bottom,22)
            if !store.search.isEmpty {searchResults}
            else {
                ScrollView {
                    VStack(alignment:.leading,spacing:3) {
                        Text("Source tree").font(.system(size:11,weight:.semibold)).foregroundStyle(secondaryInk).padding(.horizontal,20).padding(.bottom,8)
                        Button{store.reset()}label:{HStack{Image(systemName:"square.grid.3x3").frame(width:16);Text("Entire kernel");Spacer();Text("\(store.index.files.count)").font(.system(size:10)).foregroundStyle(secondaryInk)}}.buttonStyle(RailStyle(selected:store.group==nil && store.journey==nil)).padding(.horizontal,9)
                        ForEach(store.index.groups) {g in
                            Button{store.chooseGroup(g.id)}label:{HStack(spacing:9){RoundedRectangle(cornerRadius:2).fill(store.color(g.id)).frame(width:7,height:7);Text(g.id=="root" ? "Project files" : g.id).font(.system(size:12));Spacer();Text("\(g.files)").font(.system(size:10)).foregroundStyle(secondaryInk)}}.buttonStyle(RailStyle(selected:store.group==g.id)).padding(.horizontal,9)
                        }
                        Text("Guided journeys").font(.system(size:11,weight:.semibold)).foregroundStyle(secondaryInk).padding(.horizontal,20).padding(.top,26).padding(.bottom,9)
                        ForEach(journeys.indices,id:\.self) {i in
                            Button{store.startJourney(i)}label:{HStack(alignment:.top,spacing:10){Image(systemName:journeys[i].icon).font(.system(size:13)).frame(width:16).foregroundStyle(Color(hex:"B9CFE5"));VStack(alignment:.leading,spacing:4){Text(journeys[i].title).font(.system(size:11,weight:.medium));Text(journeys[i].subtitle).font(.system(size:10)).foregroundStyle(secondaryInk)}}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,5)}.buttonStyle(RailStyle(selected:store.journey==i)).padding(.horizontal,9)
                        }
                    }
                }
            }
            Spacer(minLength:16)
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:6){Circle().fill(Color(hex:"69C8B1")).frame(width:5,height:5);Text("Everything stays on this Mac").font(.system(size:10))}
                Button{store.infoOpen=true}label:{HStack{Text("About this atlas");Spacer();Image(systemName:"info.circle")}.font(.system(size:11)).foregroundStyle(secondaryInk)}.buttonStyle(.plain)
            }.padding(18)
        }.background(atlasPanel)
    }
    var searchResults:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:3){
                Text(store.hits.isEmpty ? "No files or functions found" : "\(store.matchingFiles.count) matching files").font(.system(size:11)).foregroundStyle(secondaryInk).padding(.horizontal,16).padding(.bottom,8)
                ForEach(store.hits){h in Button{store.journey=nil;store.select(file:h.file,symbol:h.symbol)}label:{VStack(alignment:.leading,spacing:4){Text(h.title).font(.system(size:11,weight:.medium)).lineLimit(1);Text(h.subtitle).font(.system(size:9)).foregroundStyle(secondaryInk).lineLimit(2)}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(RailStyle(selected:store.selectedFile==h.file && store.selectedSymbol==h.symbol)).padding(.horizontal,8)}
                if store.hits.isEmpty {Text("Try schedule, memory, or tcp.").font(.system(size:11)).foregroundStyle(secondaryInk).padding(16)}
                if store.hits.count==100 {Text("Showing the first 100 results. Refine your search to see more.").font(.system(size:10)).foregroundStyle(secondaryInk).padding(16)}
            }
        }
    }
    var header:some View {
        HStack(alignment:.center,spacing:18) {
            VStack(alignment:.leading,spacing:5){HStack(alignment:.firstTextBaseline,spacing:12){Text("Linux 1.0").font(.system(size:31,weight:.regular,design:.serif));Text("March 1994").font(.system(size:11)).foregroundStyle(secondaryInk)};Text("The first stable kernel. Every file, within reach.").font(.system(size:12)).foregroundStyle(secondaryInk)}
            Spacer()
            VStack(alignment:.trailing,spacing:6){Text("\(formatted(store.index.files.count)) files   /   \(megabytes(store.index.totalBytes))").font(.system(size:12,weight:.medium));Text("\(formatted(store.index.totalLines)) lines of history").font(.system(size:11)).foregroundStyle(secondaryInk)}
            Button{exportMap()}label:{Image(systemName:"square.and.arrow.up")}.buttonStyle(QuietButton()).help("Save a PNG of this map")
        }.padding(.horizontal,24).padding(.vertical,20)
    }
    var mapToolbar:some View {
        HStack(spacing:7) {
            ForEach(AtlasMode.allCases,id:\.self){mode in Button{store.mode=mode}label:{Label(mode.rawValue,systemImage:mode == .landscape ? "square.stack.3d.up" : "square.grid.2x2")}.buttonStyle(QuietButton(active:store.mode==mode))}
            Spacer(minLength:4)
            Menu{ForEach(HeightMetric.allCases,id:\.self){m in Button(m.rawValue){store.metric=m}}}label:{HStack(spacing:5){Text("Height: \(store.metric.rawValue.lowercased())");Image(systemName:"chevron.down").font(.system(size:8))}.font(.system(size:11)).foregroundStyle(secondaryInk)}.menuStyle(.borderlessButton).fixedSize().disabled(store.mode == .map)
            Button{store.connections.toggle()}label:{Image(systemName:"point.3.filled.connected.trianglepath.dotted")}.buttonStyle(QuietButton(active:store.connections)).help("Show named call relationships for the selection")
            Button{store.showLabels.toggle()}label:{Image(systemName:"textformat")}.buttonStyle(QuietButton(active:store.showLabels)).help("Show directory labels")
            Button{store.showCode.toggle()}label:{Image(systemName:"chevron.left.forwardslash.chevron.right")}.buttonStyle(QuietButton(active:store.showCode)).help("Reveal source code inside file tiles as you zoom")
        }.padding(.horizontal,16).padding(.vertical,12)
    }
    var map:some View {
        ZStack(alignment:.topLeading) {
            LandscapeView(store:store)
            VStack(alignment:.leading,spacing:4) {
                if let g=store.group,let group=store.index.groups.first(where:{$0.id==g}) {Text(group.title).font(.system(size:20,weight:.regular,design:.serif));Text(group.description).font(.system(size:11)).foregroundStyle(secondaryInk)}
                else {Text(store.mode == .landscape ? "The shape of a system" : "Every file has a place").font(.system(size:21,weight:.regular,design:.serif));Text(store.mode == .landscape ? "Area is source size. Height shows \(store.metric.rawValue.lowercased())." : "Zoom in to read the source inside every file.").font(.system(size:11)).foregroundStyle(secondaryInk)}
            }.padding(12).background(Color(hex:"102137").opacity(0.94),in:RoundedRectangle(cornerRadius:9)).padding(12).allowsHitTesting(false)
            VStack {Spacer();HStack(alignment:.bottom) {
                VStack(alignment:.leading,spacing:6) {
                    if let h=store.hoveredFile {let f=store.index.files[h];HStack(spacing:7){Circle().fill(store.color(f.group)).frame(width:6,height:6);Text(f.path).font(.system(size:11,weight:.medium));Text("\(formatted(f.lines)) lines").font(.system(size:10)).foregroundStyle(secondaryInk)}.padding(9).background(atlasPanel.opacity(0.95),in:RoundedRectangle(cornerRadius:6))}
                    Text(store.mode == .landscape ? "Drag to orbit   ·   Shift-drag to pan   ·   Scroll to zoom" : "Drag to pan   ·   Scroll into source   ·   Double-click to read").font(.system(size:10)).foregroundStyle(secondaryInk)
                }.allowsHitTesting(false)
                Spacer(minLength:3)
                VStack(spacing:5){Button{store.homeRevision+=1}label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.help("Fit entire kernel (0)");Button{store.zoomRequest-=0.18}label:{Image(systemName:"plus")}.help("Zoom in");Button{store.zoomRequest+=0.18}label:{Image(systemName:"minus")}.help("Zoom out")}.buttonStyle(QuietButton())
            }.padding(18)}
        }.clipped()
    }
    var legend:some View {
        HStack(spacing:14){HStack(spacing:5){Image(systemName:"cube.transparent");Text("One block, one file")};Spacer();Circle().fill(Color(hex:"69C8B1")).frame(width:5,height:5);Text("Metal · on demand");Button{store.infoOpen=true}label:{Image(systemName:"questionmark.circle")}.buttonStyle(.plain)}.font(.system(size:10)).foregroundStyle(secondaryInk).padding(.horizontal,20).padding(.vertical,13).background(atlasPanel.opacity(0.6))
    }
    func exportMap() {
        let save=NSSavePanel();save.allowedContentTypes=[.png];save.nameFieldStringValue="Linux-1.0-\(store.mode.rawValue).png"
        if save.runModal() == .OK,let url=save.url {do{try store.scene?.snapshot(to:url)}catch{store.errorMessage=error.localizedDescription}}
    }
}

struct RailStyle:ButtonStyle {
    let selected:Bool
    func makeBody(configuration:Configuration)->some View {configuration.label.foregroundStyle(selected ? ink : Color(hex:"B1C1D4")).font(.system(size:12)).padding(.horizontal,11).padding(.vertical,8).background(selected ? Color(hex:"293E57") : configuration.isPressed ? Color(hex:"1D3047") : .clear,in:RoundedRectangle(cornerRadius:7))}
}

struct Inspector:View {
    @ObservedObject var store:AtlasStore
    @State private var tab="Functions"
    @State private var inbound=false
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            if let file=store.file {fileInspector(file)} else {overview}
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(atlasPanel)
    }
    var overview:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack{Image(systemName:"viewfinder").font(.system(size:20,weight:.light));Spacer();Text("Start exploring").font(.system(size:11)).foregroundStyle(secondaryInk)}
                Text("Small enough to hold.\nDeep enough to get lost.").font(.system(size:25,weight:.regular,design:.serif)).lineSpacing(3)
                Text("Before millions of commits and billions of devices, Linux was this: a complete kernel for 386 and 486 PCs.").font(.system(size:13)).lineSpacing(5).foregroundStyle(Color(hex:"B1C1D4"))
                HStack(spacing:0){stat("\(formatted(store.index.symbols.count))","C functions");Spacer();stat("\(formatted(store.index.edges.count))","Named call sites")}
                Rectangle().fill(Color.white.opacity(0.08)).frame(height:1)
                Text("Read the landscape").font(.system(size:13,weight:.semibold))
                instruction("square.dashed.inset.filled","Footprint is file size","Large blocks hold more source bytes. Directories stay together.")
                instruction("chart.bar.xaxis","Height shows \(store.metric.rawValue.lowercased())",store.metric == .branches ? "Taller files contain more conditionals and loops, on a logarithmic scale." : "Taller files contain more \(store.metric.rawValue.lowercased()), on a logarithmic scale.")
                instruction("text.alignleft","Zoom into the actual source","Each file reveals its complete source with syntax and line numbers. Map mode is ideal for reading.")
                instruction("cursorarrow.rays","Select to see the connections","Inspect functions, follow named calls, and open the original source.")
                Button{store.startJourney(0)}label:{HStack{Text("Start with the boot sequence");Spacer();Image(systemName:"play.fill").font(.system(size:10))}.padding(.vertical,4)}.buttonStyle(QuietButton(active:true))
                Text("Or choose a neighborhood on the left. The three guided journeys connect the map to ideas you can actually read in the source.").font(.system(size:11)).foregroundStyle(secondaryInk).lineSpacing(4)
            }.padding(22)
        }
    }
    func instruction(_ icon:String,_ title:String,_ body:String)->some View {HStack(alignment:.top,spacing:12){Image(systemName:icon).font(.system(size:16,weight:.light)).foregroundStyle(Color(hex:"A3CBE3")).frame(width:21);VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:12,weight:.medium));Text(body).font(.system(size:11)).foregroundStyle(secondaryInk).lineSpacing(3)}}}
    func stat(_ value:String,_ label:String)->some View {VStack(alignment:.leading,spacing:5){Text(value).font(.system(size:20,weight:.medium,design:.rounded));Text(label).font(.system(size:10)).foregroundStyle(secondaryInk)}}
    func fileInspector(_ file:CodeFile)->some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:13) {
                HStack{Circle().fill(store.color(file.group)).frame(width:7,height:7);Text(file.group).font(.system(size:11)).foregroundStyle(secondaryInk);Spacer();Button{store.focusRevision+=1}label:{Image(systemName:"scope")}.buttonStyle(.plain).help("Focus selected file (F)");Button{store.selectedFile=nil;store.selectedSymbol=nil;store.journey=nil;store.revision+=1}label:{Image(systemName:"xmark")}.buttonStyle(.plain).help("Close inspector")}
                Text(file.name).font(.system(size:25,weight:.regular,design:.serif)).lineLimit(1).minimumScaleFactor(0.65)
                Text(file.path).font(.system(size:10,design:.monospaced)).foregroundStyle(secondaryInk).textSelection(.enabled)
                HStack{stat(formatted(file.lines),"Lines");Spacer();stat(formatted(file.functions),"Functions");Spacer();stat(formatted(file.branches),"Branches")}
                if let stop=store.currentStop,let journey=store.journey {
                    VStack(alignment:.leading,spacing:8){HStack{Text("\(store.journeyStep+1) of \(journeys[journey].stops.count)").font(.system(size:10)).foregroundStyle(secondaryInk);Spacer();Button{store.stepJourney(-1)}label:{Image(systemName:"chevron.left")}.disabled(store.journeyStep==0);Button{store.stepJourney(1)}label:{Image(systemName:"chevron.right")}.disabled(store.journeyStep==journeys[journey].stops.count-1)}.buttonStyle(.plain);Text(stop.title).font(.system(size:15,weight:.medium));Text(stop.explanation).font(.system(size:11)).foregroundStyle(Color(hex:"B9CADD")).lineSpacing(4)}.padding(13).background(Color(hex:"21354B"),in:RoundedRectangle(cornerRadius:9))
                }
                Button{store.sourceOpen=true}label:{HStack{Image(systemName:"chevron.left.forwardslash.chevron.right");Text("Read source");Spacer();Text("⌘O").foregroundStyle(secondaryInk)}}.buttonStyle(QuietButton(active:true))
            }.padding(20)
            HStack(spacing:6){ForEach(["Functions","Calls"],id:\.self){t in Button{tab=t}label:{Text(t).frame(maxWidth:.infinity)}.buttonStyle(QuietButton(active:tab==t))}}.padding(.horizontal,17).padding(.bottom,12)
            if tab=="Functions" {symbolList(file)}else {callList}
            VStack(alignment:.leading,spacing:5){if let s=store.symbol {Text("\(s.name)()  ·  line \(s.line)").font(.system(size:10,design:.monospaced)).lineLimit(1);Text("\(store.incoming[s.id]?.count ?? 0) incoming / \(store.outgoing[s.id]?.count ?? 0) outgoing named calls").font(.system(size:10)).foregroundStyle(secondaryInk)};Text("Syntax-based index. Macros and indirect calls are incomplete.").font(.system(size:9)).foregroundStyle(secondaryInk).lineSpacing(2)}.padding(17).frame(maxWidth:.infinity,alignment:.leading).background(Color(hex:"0E1B2B"))
        }
    }
    func symbolList(_ file:CodeFile)->some View {
        ScrollViewReader {proxy in ScrollView {
            LazyVStack(alignment:.leading,spacing:2){
                ForEach(store.symbolsByFile[file.id] ?? []) {s in
                    Button{store.select(file:file.id,symbol:s.id)}label:{HStack(alignment:.firstTextBaseline,spacing:5){Text(s.name).font(.system(size:11,design:.monospaced)).lineLimit(1);Spacer(minLength:2);Text("\(s.line)").font(.system(size:10,design:.monospaced)).foregroundStyle(secondaryInk)}}.buttonStyle(RailStyle(selected:store.selectedSymbol==s.id)).id(s.id)
                }
                if file.functions==0 {Text("No C function definitions were parsed in this file. Open the source to explore it directly.").font(.system(size:12)).foregroundStyle(secondaryInk).lineSpacing(4).padding(15)}
            }.padding(.horizontal,9)
        }.onChange(of:store.selectedSymbol){_,id in if let id {proxy.scrollTo(id,anchor:.center)}}.onAppear{if let id=store.selectedSymbol {proxy.scrollTo(id,anchor:.center)}}}
    }
    var callList:some View {
        VStack(alignment:.leading,spacing:8) {
            Picker("Direction",selection:$inbound){Text("Outgoing").tag(false);Text("Incoming").tag(true)}.pickerStyle(.segmented).padding(.horizontal,17)
            Toggle("Draw relationships on map",isOn:$store.connections).toggleStyle(.checkbox).font(.system(size:11)).padding(.horizontal,19)
            let edges=store.relevantEdges(inbound:inbound)
            Text("\(edges.count) sites\(store.symbol == nil ? " in this file" : " for this function")").font(.system(size:10)).foregroundStyle(secondaryInk).padding(.horizontal,19)
            ScrollView {LazyVStack(alignment:.leading,spacing:2){ForEach(Array(edges.prefix(300).enumerated()),id:\.offset){_,edge in
                let destination=store.index.symbols[inbound ? edge.source : edge.target]
                let caller=store.index.symbols[edge.source]
                Button{store.select(file:destination.file,symbol:destination.id)}label:{VStack(alignment:.leading,spacing:4){Text(destination.name+"()").font(.system(size:11,design:.monospaced));Text(store.index.files[destination.file].path).font(.system(size:9)).foregroundStyle(secondaryInk);Text("Call at \(store.index.files[caller.file].name):\(edge.line)").font(.system(size:9)).foregroundStyle(secondaryInk)}}.buttonStyle(RailStyle(selected:false))
            };if edges.isEmpty {Text("No resolved named calls in this direction. This does not rule out macros or function-pointer calls.").font(.system(size:11)).foregroundStyle(secondaryInk).lineSpacing(4).padding(18)};if edges.count>300{Text("Showing the first 300 call sites.").font(.system(size:10)).foregroundStyle(secondaryInk).padding(18)}}.padding(.horizontal,8)}
        }
    }
}

struct SourceSheet:View {
    @ObservedObject var store:AtlasStore
    var body:some View {
        VStack(spacing:0){HStack{VStack(alignment:.leading,spacing:4){Text(store.file?.path ?? "Source").font(.system(size:17,weight:.medium));Text(store.symbol.map{"\($0.name)() · line \($0.line)"} ?? "Original Linux 1.0 source").font(.system(size:11)).foregroundStyle(secondaryInk)};Spacer();Button("Reveal file"){if let f=store.file {NSWorkspace.shared.activateFileViewerSelecting([store.resourceURL.appendingPathComponent("linux/"+f.path)])}}.buttonStyle(QuietButton());Button("Done"){store.sourceOpen=false}.buttonStyle(QuietButton(active:true)).keyboardShortcut(.escape,modifiers:[])}.padding(18);Divider();if let f=store.file {SourceTextView(text:store.source(f.id),line:store.symbol?.line ?? 1)};HStack{Text("Read-only original · GPL-2.0 · Source included in the app");Spacer();Text("\(store.file?.lines ?? 0) lines")}.font(.system(size:10)).foregroundStyle(secondaryInk).padding(12)}.frame(width:940,height:690).background(atlasPanel).foregroundStyle(ink).preferredColorScheme(.dark)
    }
}

struct SourceTextView:NSViewRepresentable {
    let text:String;let line:Int
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.autohidesScrollers=true
        let view=NSTextView();view.isEditable=false;view.isSelectable=true;view.isRichText=false;view.backgroundColor=NSColor(hex:"0D1929")
        view.textContainerInset=NSSize(width:18,height:18);view.isHorizontallyResizable=true;view.isVerticallyResizable=true
        view.textContainer?.widthTracksTextView=false;view.textContainer?.containerSize=NSSize(width:10000,height:CGFloat.greatestFiniteMagnitude)
        view.minSize=NSSize(width:900,height:650);view.maxSize=NSSize(width:10000,height:CGFloat.greatestFiniteMagnitude)
        scroll.documentView=view;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let view=scroll.documentView as? NSTextView else{return}
        let numbered=text.components(separatedBy:"\n").enumerated().map{String(format:"%5d  ",$0.offset+1)+$0.element}.joined(separator:"\n")
        let string=numbered as NSString
        let result=NSMutableAttributedString(string:numbered,attributes:[.font:NSFont.monospacedSystemFont(ofSize:12,weight:.regular),.foregroundColor:NSColor(hex:"C5D5E7")])
        let styles:[(String,String)]=[("(?m)^ *[0-9]+  ","50677F"),("\\b(?:if|else|while|for|return|static|void|int|unsigned|long|char|struct|const|switch|case|break|sizeof|typedef|volatile|extern|do|goto|asmlinkage)\\b","BBA2E2"),("\\b[0-9]+(?:x[0-9a-fA-F]+)?\\b","E9B971"),("\"(?:[^\"\\\\]|\\\\.)*\"","8BC9B0"),("(?s)/\\*.*?\\*/|(?m)//[^\\n]*","6F92A1")]
        for (pattern,color) in styles {if let regex=try? NSRegularExpression(pattern:pattern){for match in regex.matches(in:numbered,range:NSRange(location:0,length:string.length)){result.addAttribute(.foregroundColor,value:NSColor(hex:color),range:match.range)}}}
        view.textStorage?.setAttributedString(result)
        let target=max(1,line),prefix=numbered.components(separatedBy:"\n").prefix(target-1).joined(separator:"\n")
        let offset=(prefix as NSString).length+(target>1 ? 1 : 0)
        if offset<string.length {let range=string.lineRange(for:NSRange(location:offset,length:0));view.textStorage?.addAttribute(.backgroundColor,value:NSColor(hex:"243D54"),range:range);view.setSelectedRange(NSRange(location:offset,length:0));view.scrollRangeToVisible(range)}
    }
}

struct AboutSheet:View {
    @ObservedObject var store:AtlasStore
    var body:some View {
        VStack(alignment:.leading,spacing:18){HStack{Text("An atlas, with provenance").font(.system(size:25,design:.serif));Spacer();Button("Done"){store.infoOpen=false}.keyboardShortcut(.escape,modifiers:[])}
            Text("Kernel Atlas is an original native Mac explorer inspired by Rik Arends’ Makepad Scope. Scope remains private in the public Director README. This app uses SwiftUI, AppKit, and a Metal-backed SceneKit renderer.").font(.system(size:13)).lineSpacing(4)
            Text("The complete Linux 1.0 source is bundled unchanged: \(formatted(store.index.totalBytes)) bytes, below the 20 MB limit. Its archive SHA-256 matches kernel.org’s published checksum. The original COPYING file is included.").font(.system(size:12)).foregroundStyle(secondaryInk).lineSpacing(4)
            Link("Original source at kernel.org",destination:URL(string:store.index.sourceURL)!)
            Text("How to read the data").font(.system(size:14,weight:.semibold))
            Text("Block area encodes source bytes before directory padding. Height uses log₂(1 + value), capped for legibility. Branches count parsed conditionals, loops, and cases; they are not a formal complexity score. Color identifies the top-level directory.").font(.system(size:12)).lineSpacing(4)
            Text("C functions and named calls come from Tree-sitter. Calls resolve to a same-file definition or a unique non-static definition. This is syntax-based navigation, not a compiler-resolved call graph: conditional builds, macros, inline assembly, and function pointers are incomplete. There are \(formatted(store.index.unresolvedCalls)) unresolved named call sites and \(formatted(store.index.parseErrors)) parser error nodes. Map arcs aggregate cross-file relationships and show up to 28 neighbors; the call list preserves individual sites.").font(.system(size:12)).foregroundStyle(secondaryInk).lineSpacing(4)
            Text("Keyboard: ⌘F search · ⌘O source · 0 fit · F focus · 2 map · 3 landscape. Drag to orbit, Shift-drag to pan, pinch or scroll to zoom. Reduced motion follows macOS.").font(.system(size:11)).foregroundStyle(secondaryInk).lineSpacing(4)
            HStack{Text(store.scene?.deviceName ?? "Metal");Spacer();Text(String(format:"Index decoded in %.1f ms",store.loadMilliseconds))}.font(.system(size:10)).foregroundStyle(secondaryInk)
        }.padding(28).frame(width:650).background(atlasPanel).foregroundStyle(ink).preferredColorScheme(.dark)
    }
}
