import AppKit
import SwiftUI

struct CodeFile: Codable, Identifiable {
    let id: Int; let path, name, group: String
    let bytes, lines, functions, branches, parseErrors: Int
    let sha256: String; let rect: [Double]
}
struct CodeSymbol: Codable, Identifiable {
    let id, file: Int; let name: String
    let line, endLine, branches: Int; let isStatic: Bool
}
struct CallEdge: Codable { let source, target, line: Int }
struct CodeGroup: Codable, Identifiable {
    let id, title, color, description: String; let bytes, files: Int
}
struct CodeDirectory: Codable { let path, group: String; let depth: Int; let rect: [Double] }
struct CodeIndex: Codable {
    let schema: Int; let title, release, sourceURL, archiveSHA256: String
    let totalBytes, totalLines, unresolvedCalls, parseErrors: Int
    let files: [CodeFile]; let symbols: [CodeSymbol]; let edges: [CallEdge]
    let groups: [CodeGroup]; let directories: [CodeDirectory]
}
struct SearchHit: Identifiable {
    let file: Int; let symbol: Int?; let title, subtitle: String
    var id: String { "\(file):\(symbol ?? -1)" }
}
struct Journey {
    let title, subtitle, icon: String; let stops: [JourneyStop]
}
struct JourneyStop {
    let file, symbol, title, explanation: String
}
let journeys = [
    Journey(title: "Bring Linux to life", subtitle: "Boot, initialize, schedule", icon: "power", stops: [
        JourneyStop(file:"init/main.c",symbol:"start_kernel",title:"The first breath",explanation:"After assembly establishes the machine, start_kernel initializes memory, traps, interrupts, the scheduler, and devices. Scroll through this function to see the system come together."),
        JourneyStop(file:"kernel/sched.c",symbol:"sched_init",title:"Give time a structure",explanation:"sched_init installs the timer interrupt and prepares task state. The shared scheduling machinery is ready before the system starts running ordinary processes."),
        JourneyStop(file:"kernel/sched.c",symbol:"schedule",title:"Choose who runs next",explanation:"The scheduler walks the task table and chooses a runnable task using its remaining counter. The early kernel's scheduling policy fits inside one readable function.")]),
    Journey(title:"A page fault, resolved",subtitle:"Virtual memory becomes real",icon:"square.stack.3d.up",stops:[
        JourneyStop(file:"mm/memory.c",symbol:"do_page_fault",title:"An address with no home",explanation:"A processor fault enters do_page_fault. The error code tells Linux whether this is a missing page or a protection violation."),
        JourneyStop(file:"mm/memory.c",symbol:"do_no_page",title:"Make a missing page",explanation:"do_no_page looks up the virtual memory area and asks its backing object for a page, or allocates an anonymous one."),
        JourneyStop(file:"mm/memory.c",symbol:"do_wp_page",title:"Copy only when needed",explanation:"Write protection can mean that two processes share a page. do_wp_page implements copy on write, preserving isolation while avoiding unnecessary copies.")]),
    Journey(title:"Follow a network packet",subtitle:"IP hands a packet to TCP",icon:"point.3.connected.trianglepath.dotted",stops:[
        JourneyStop(file:"net/inet/ip.c",symbol:"ip_rcv",title:"A packet arrives",explanation:"ip_rcv validates the IP header, handles fragments, decides whether to forward, and dispatches to the appropriate transport protocol."),
        JourneyStop(file:"net/inet/tcp.c",symbol:"tcp_rcv",title:"Find the conversation",explanation:"TCP associates the segment with a socket, checks its state, and processes acknowledgements and data. This route is a reading guide; protocol callbacks are indirect calls and are not invented as direct graph edges."),
        JourneyStop(file:"net/inet/tcp.c",symbol:"tcp_read",title:"Deliver bytes to a process",explanation:"The read path turns queued network segments into the stream of bytes a process requested. Explore the local helper calls and inspect the original implementation.")])
]

enum AtlasMode: String, CaseIterable { case landscape = "Landscape", map = "Map" }
enum HeightMetric: String, CaseIterable { case branches = "Branches", lines = "Lines", functions = "Functions" }

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let n=UInt64(hex, radix:16) ?? 0
        self.init(srgbRed:CGFloat((n>>16)&255)/255, green:CGFloat((n>>8)&255)/255, blue:CGFloat(n&255)/255, alpha:alpha)
    }
}
extension Color { init(hex: String) { self.init(nsColor:NSColor(hex:hex)) } }
let ink = Color(hex:"E7EEF7")
let secondaryInk = Color(hex:"94A7BE")
let atlasPanel = Color(hex:"122033")
func formatted(_ n:Int)->String { n.formatted() }
func megabytes(_ n:Int)->String { String(format:"%.2f MB", Double(n)/1_000_000) }

final class AtlasStore: ObservableObject {
    let index: CodeIndex; let resourceURL: URL
    let loadMilliseconds: Double
    let symbolsByFile: [Int:[CodeSymbol]]
    let outgoing: [Int:[CallEdge]]; let incoming: [Int:[CallEdge]]
    @Published var selectedFile: Int? = nil
    @Published var selectedSymbol: Int? = nil
    @Published var group: String? = nil
    @Published var mode = AtlasMode.landscape
    @Published var metric = HeightMetric.branches
    @Published var connections = false
    @Published var showLabels = true
    @Published var showCode = true
    @Published var search = "" { didSet { updateSearch() } }
    @Published var hits: [SearchHit] = []
    @Published var matchingFiles: Set<Int> = []
    @Published var journey: Int? = nil
    @Published var journeyStep = 0
    @Published var sourceOpen = false
    @Published var infoOpen = false
    @Published var errorMessage: String? = nil
    @Published var revision = 0
    @Published var hoveredFile: Int? = nil
    @Published var focusRevision = 0
    @Published var homeRevision = 0
    @Published var zoomRequest: Double = 0
    var scene: AtlasScene?
    private var sourceCache = NSCache<NSNumber, NSString>()
    init(resources: URL) throws {
        let t=CFAbsoluteTimeGetCurrent()
        resourceURL=resources
        let index=try JSONDecoder().decode(CodeIndex.self,from:Data(contentsOf:resources.appendingPathComponent("index.json")))
        guard index.schema == 1, index.totalBytes < 20_000_000,
              index.files.enumerated().allSatisfy({ $0.offset == $0.element.id }),
              index.symbols.enumerated().allSatisfy({ $0.offset == $0.element.id }),
              index.edges.allSatisfy({ index.symbols.indices.contains($0.source) && index.symbols.indices.contains($0.target) }) else {
            throw NSError(domain:"KernelAtlas",code:1,userInfo:[NSLocalizedDescriptionKey:"The bundled source index is invalid. Rebuild the app with scripts/build.sh."])
        }
        self.index=index
        symbolsByFile=Dictionary(grouping:index.symbols,by:\.file)
        outgoing=Dictionary(grouping:index.edges,by:\.source)
        incoming=Dictionary(grouping:index.edges,by:\.target)
        loadMilliseconds=(CFAbsoluteTimeGetCurrent()-t)*1000
        sourceCache.countLimit=6
    }
    var file: CodeFile? { selectedFile.map { index.files[$0] } }
    var symbol: CodeSymbol? { selectedSymbol.map { index.symbols[$0] } }
    var currentStop: JourneyStop? { journey.map { journeys[$0].stops[journeyStep] } }
    func color(_ group:String)->Color { Color(hex:index.groups.first{$0.id==group}?.color ?? "8296B0") }
    func nsColor(_ group:String)->NSColor { NSColor(hex:index.groups.first{$0.id==group}?.color ?? "8296B0") }
    func select(file:Int, symbol:Int? = nil) {
        selectedFile=file; selectedSymbol=symbol
        if let group, group != index.files[file].group { self.group=nil }
        revision+=1
    }
    func reset() {
        group=nil; selectedFile=nil; selectedSymbol=nil; journey=nil; search=""; connections=false
        homeRevision+=1; revision+=1
    }
    func chooseGroup(_ value:String) {
        journey=nil; group = group == value ? nil : value; revision+=1
    }
    func startJourney(_ id:Int) { journey=id; journeyStep=0; group=nil; search=""; showStop() }
    func stepJourney(_ delta:Int) {
        guard let journey else { return }
        journeyStep=min(max(0,journeyStep+delta),journeys[journey].stops.count-1); showStop()
    }
    func showStop() {
        guard let stop=currentStop, let f=index.files.first(where:{$0.path==stop.file}) else{return}
        let s=symbolsByFile[f.id]?.first{$0.name==stop.symbol}
        select(file:f.id,symbol:s?.id); connections=true
    }
    func updateSearch() {
        let q=search.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {hits=[]; matchingFiles=[]; return}
        let files=index.files.filter{$0.path.lowercased().contains(q)}.map { SearchHit(file:$0.id,symbol:nil,title:$0.name,subtitle:$0.path) }
        let syms=index.symbols.filter{$0.name.lowercased().contains(q)}.sorted{
            let a=$0.name.lowercased()==q, b=$1.name.lowercased()==q
            return a != b ? a : $0.name < $1.name
        }.map{SearchHit(file:$0.file,symbol:$0.id,title:$0.name+"()",subtitle:index.files[$0.file].path+":\($0.line)")}
        matchingFiles=Set((files+syms).map(\.file)); hits=Array((syms+files).prefix(100))
    }
    func source(_ id:Int)->String {
        if let s=sourceCache.object(forKey:NSNumber(value:id)) { return s as String }
        let url=resourceURL.appendingPathComponent("linux").appendingPathComponent(index.files[id].path)
        guard let data=try? Data(contentsOf:url) else{return "Unable to read this source file. Rebuild the app to restore the bundled corpus."}
        let text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) ?? "This file is not text."
        sourceCache.setObject(text as NSString,forKey:NSNumber(value:id)); return text
    }
    func relevantEdges(inbound:Bool)->[CallEdge] {
        if let selectedSymbol { return (inbound ? incoming[selectedSymbol] : outgoing[selectedSymbol]) ?? [] }
        guard let selectedFile else {return []}
        return (symbolsByFile[selectedFile] ?? []).flatMap { (inbound ? incoming[$0.id] : outgoing[$0.id]) ?? [] }
    }
}
