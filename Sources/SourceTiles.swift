import AppKit
import CoreText
import SceneKit

private struct SourceSpan {
    let range:NSRange
    let color:NSColor
}
struct SourceRow {
    let number:Int
    let continuation:Bool
    let text:String
    fileprivate let spans:[SourceSpan]
}

/// A stable layout of the entire original file, independent of the camera zoom.
/// Soft wrapping is visual only; every row keeps its original source line number.
final class SourceDocument {
    let rows:[SourceRow]
    let maxColumns:Int
    let gutterColumns:Int
    let functionRows:[Int]
    static let font=NSFont.monospacedSystemFont(ofSize:12,weight:.regular)
    static let advance=("M" as NSString).size(withAttributes:[.font:font]).width
    static let lineHeight:CGFloat=17
    private static let keywords:Set<String>=["if","else","while","for","do","return","switch","case","default","break","continue","goto","sizeof","static","inline","extern","const","volatile","unsigned","signed","int","void","long","short","char","float","double","struct","union","enum","typedef","asmlinkage","__asm__","asm"]
    init(text:String,functionLines:Set<Int> = []) {
        var output:[SourceRow]=[]
        var blockComment=false
        let lines=text.components(separatedBy:"\n")
        var longest=1
        for (index,line) in lines.enumerated() {
            // A final newline terminates the previous source line, not a new line.
            if index==lines.count-1 && line.isEmpty && index>0 {break}
            var expanded="",column=0
            for ch in line {
                if ch=="\t" {let n=8-column%8;expanded+=String(repeating:" ",count:n);column+=n}
                else if ch != "\r" {expanded.append(ch);column+=1}
            }
            let string=expanded as NSString
            let spans=Self.tokenize(string,blockComment:&blockComment)
            // 100-column soft wrapping makes long lines readable without discarding them.
            let chunks=max(1,Int(ceil(Double(string.length)/100)))
            for chunk in 0..<chunks {
                let start=chunk*100,length=min(100,max(0,string.length-start))
                let range=NSRange(location:start,length:length)
                let clipped=spans.compactMap {span -> SourceSpan? in
                    let intersection=NSIntersectionRange(range,span.range)
                    guard intersection.length>0 else{return nil}
                    return SourceSpan(range:NSRange(location:intersection.location-start,length:intersection.length),color:span.color)
                }
                let value=string.substring(with:range)
                output.append(SourceRow(number:index+1,continuation:chunk>0,text:value,spans:clipped))
                longest=max(longest,length)
            }
        }
        rows=output;maxColumns=longest;gutterColumns=String(max(1,lines.count)).count+2
        functionRows=output.indices.filter{!output[$0].continuation && functionLines.contains(output[$0].number)}
    }
    private static func tokenize(_ text:NSString,blockComment:inout Bool)->[SourceSpan] {
        var result:[SourceSpan]=[],i=0
        func add(_ start:Int,_ end:Int,_ hex:String) {if end>start {result.append(SourceSpan(range:NSRange(location:start,length:end-start),color:NSColor(hex:hex)))}}
        func identifier(_ c:unichar)->Bool {(c>=65 && c<=90)||(c>=97 && c<=122)||(c>=48 && c<=57)||c==95}
        while i<text.length {
            let start=i,c=text.character(at:i)
            if blockComment {
                while i<text.length {
                    if text.character(at:i)==42 && i+1<text.length && text.character(at:i+1)==47 {i+=2;blockComment=false;break}
                    i+=1
                }
                add(start,i,"829FA9");continue
            }
            if c==47 && i+1<text.length {
                let next=text.character(at:i+1)
                if next==47 {add(i,text.length,"829FA9");break}
                if next==42 {blockComment=true;i+=2
                    while i<text.length {
                        if text.character(at:i)==42 && i+1<text.length && text.character(at:i+1)==47 {i+=2;blockComment=false;break}
                        i+=1
                    }
                    add(start,i,"829FA9");continue
                }
            }
            if c==34 || c==39 {
                i+=1
                while i<text.length {let t=text.character(at:i);i+=1;if t==92 {i=min(text.length,i+1)}else if t==c {break}}
                add(start,i,"9DD7B5");continue
            }
            if c>=48 && c<=57 {i+=1;while i<text.length && identifier(text.character(at:i)){i+=1};add(start,i,"E8BD82");continue}
            if identifier(c) {
                i+=1;while i<text.length && identifier(text.character(at:i)){i+=1}
                let word=text.substring(with:NSRange(location:start,length:i-start))
                if keywords.contains(word) {add(start,i,"CDB5EE")}
                else {var next=i;while next<text.length && (text.character(at:next)==32 || text.character(at:next)==9){next+=1};if next<text.length && text.character(at:next)==40 {add(start,i,"97C9EC")}}
                continue
            }
            i+=1
        }
        return result
    }
}

struct SourceTileLayout {
    let file:Int
    let worldX,worldZ,worldWidth,worldDepth,unit:CGFloat
    let columns,rowsPerColumn:Int
    let columnStarts:[Int]
    let columnWidth,logicalWidth,logicalHeight:CGFloat
    static let margin:CGFloat=18,header:CGFloat=38
    init(file:CodeFile,document:SourceDocument) {
        self.file=file.id
        let r=file.rect
        let gap=min(0.22,min(r[2],r[3])*0.12)
        let inset=CGFloat(gap/2+min(r[2],r[3])*0.018)
        worldX=CGFloat(r[0]-60)+inset;worldZ=CGFloat(r[1]-47)+inset
        worldWidth=max(0.00001,CGFloat(r[2])-inset*2);worldDepth=max(0.00001,CGFloat(r[3])-inset*2)
        columnWidth=CGFloat(document.maxColumns+document.gutterColumns)*SourceDocument.advance+28
        var best:CGFloat=0,bestColumns=1,bestRows=document.rows.count
        for n in 1...min(32,max(1,document.rows.count)) {
            let count=Int(ceil(Double(document.rows.count)/Double(n)))
            let width=CGFloat(n)*columnWidth+Self.margin*2
            let height=CGFloat(count)*SourceDocument.lineHeight+Self.header+Self.margin
            let fit=min(worldWidth/width,worldDepth/height)
            if fit>best {best=fit;bestColumns=n;bestRows=count}
        }
        columns=bestColumns
        var starts=[0]
        if bestColumns>1 {
            for column in 1..<bestColumns {
                let desired=column*bestRows
                let candidates=document.functionRows.filter{abs($0-desired)<=20 && $0>starts.last!+1 && $0<document.rows.count-(bestColumns-column)}
                starts.append(candidates.min(by:{abs($0-desired)<abs($1-desired)}) ?? min(document.rows.count-1,desired))
            }
        }
        columnStarts=starts
        rowsPerColumn=max(1,starts.enumerated().map{column,start in (column+1<starts.count ? starts[column+1] : document.rows.count)-start}.max() ?? 1)
        unit=min(worldWidth/(CGFloat(columns)*columnWidth+Self.margin*2),worldDepth/(CGFloat(rowsPerColumn)*SourceDocument.lineHeight+Self.header+Self.margin))
        logicalWidth=worldWidth/unit;logicalHeight=worldDepth/unit
    }
    func position(row:Int)->CGPoint {
        let column=columnStarts.lastIndex(where:{$0<=row}) ?? 0
        return CGPoint(x:Self.margin+CGFloat(column)*columnWidth,y:Self.header+CGFloat(row-columnStarts[column])*SourceDocument.lineHeight)
    }
    func worldPosition(row:Int,height:CGFloat)->SCNVector3 {
        let p=position(row:row)
        return SCNVector3(worldX+(p.x+columnWidth*0.45)*unit,height,worldZ+(p.y+60)*unit)
    }
}

/// Draw only visible rows in visible file roofs. CoreText stays sharp at every scale;
/// neither full-file textures nor thousands of native text views are allocated.
final class SourceTileRenderer {
    weak var atlas:AtlasScene?
    private var documents:[Int:SourceDocument]=[:],documentUse:[Int:Int]=[:]
    private var glyphs:[String:CTLine]=[:],glyphUse:[String:Int]=[:]
    private var tick=0
    private(set) var renderedFiles=Set<Int>()
    private(set) var renderedRows:[Int:Set<Int>]=[:]
    private(set) var textRowCount=0
    private(set) var densityRowCount=0
    private(set) var lastDrawMilliseconds:Double=0
    var cachedDocumentCount:Int {documents.count}
    var cachedGlyphCount:Int {glyphs.count}
    func document(_ file:Int)->SourceDocument? {
        tick+=1
        if let d=documents[file] {documentUse[file]=tick;return d}
        guard let store=atlas?.store else{return nil}
        if documents.count>=20,let oldest=documentUse.min(by:{$0.value<$1.value})?.key {documents.removeValue(forKey:oldest);documentUse.removeValue(forKey:oldest)}
        let d=SourceDocument(text:store.source(file),functionLines:Set((store.symbolsByFile[file] ?? []).map(\.line)));documents[file]=d;documentUse[file]=tick;return d
    }
    private func glyph(file:Int,index:Int,row:SourceRow,gutter:Int)->CTLine {
        let key="\(file):\(index)";tick+=1
        if let line=glyphs[key] {glyphUse[key]=tick;return line}
        if glyphs.count>=1536 {
            for (key,_) in glyphUse.sorted(by:{$0.value<$1.value}).prefix(128) {glyphs.removeValue(forKey:key);glyphUse.removeValue(forKey:key)}
        }
        let prefix=row.continuation ? String(repeating:" ",count:gutter) : String(repeating:" ",count:max(0,gutter-2-String(row.number).count))+"\(row.number)  "
        let text=NSMutableAttributedString(string:prefix+row.text,attributes:[.font:SourceDocument.font,.foregroundColor:NSColor(hex:"D2DFE9")])
        text.addAttribute(.foregroundColor,value:NSColor(hex:"5C7A90"),range:NSRange(location:0,length:(prefix as NSString).length))
        for span in row.spans {text.addAttribute(.foregroundColor,value:span.color,range:NSRange(location:(prefix as NSString).length+span.range.location,length:span.range.length))}
        let line=CTLineCreateWithAttributedString(text);glyphs[key]=line;glyphUse[key]=tick;return line
    }
    private func transform(_ layout:SourceTileLayout,height:CGFloat,view:AtlasSCNView)->CGAffineTransform {
        let p=view.projectPoint(SCNVector3(layout.worldX,height,layout.worldZ))
        let x=view.projectPoint(SCNVector3(layout.worldX+layout.worldWidth,height,layout.worldZ))
        let y=view.projectPoint(SCNVector3(layout.worldX,height,layout.worldZ+layout.worldDepth))
        return CGAffineTransform(a:(x.x-p.x)/layout.logicalWidth,b:(x.y-p.y)/layout.logicalWidth,c:(y.x-p.x)/layout.logicalHeight,d:(y.y-p.y)/layout.logicalHeight,tx:p.x,ty:p.y)
    }
    @discardableResult func draw(in bounds:NSRect)->Set<Int> {
        let began=CFAbsoluteTimeGetCurrent()
        defer {lastDrawMilliseconds=(CFAbsoluteTimeGetCurrent()-began)*1000}
        renderedFiles=[];renderedRows=[:];textRowCount=0;densityRowCount=0
        guard let atlas,let store=atlas.store,let view=atlas.view,store.showCode,let context=NSGraphicsContext.current?.cgContext else{return []}
        var visibleWorld:NSRect?=nil
        if atlas.currentMode == .map {
            let points=[CGPoint(x:bounds.minX,y:bounds.minY),CGPoint(x:bounds.maxX,y:bounds.maxY)].compactMap{atlas.planePoint($0,height:0.2)}
            if points.count==2 {visibleWorld=NSRect(x:min(points[0].x,points[1].x),y:min(points[0].z,points[1].z),width:abs(points[0].x-points[1].x),height:abs(points[0].z-points[1].z))}
        }
        for file in store.index.files {
            if let group=store.group,group != file.group {continue}
            if !store.search.isEmpty && !store.matchingFiles.contains(file.id) && store.selectedFile != file.id {continue}
            let r=file.rect,height=CGFloat(atlas.heights[file.id] ?? 0)+0.018
            if let visibleWorld,!visibleWorld.intersects(NSRect(x:r[0]-60,y:r[1]-47,width:r[2],height:r[3])) {continue}
            let a=view.projectPoint(SCNVector3(r[0]-60,height,r[1]-47))
            let b=view.projectPoint(SCNVector3(r[0]+r[2]-60,height,r[1]-47))
            let c=view.projectPoint(SCNVector3(r[0]-60,height,r[1]+r[3]-47))
            let d=view.projectPoint(SCNVector3(r[0]+r[2]-60,height,r[1]+r[3]-47))
            let box=NSRect(x:min(a.x,b.x,c.x,d.x),y:min(a.y,b.y,c.y,d.y),width:max(a.x,b.x,c.x,d.x)-min(a.x,b.x,c.x,d.x),height:max(a.y,b.y,c.y,d.y)-min(a.y,b.y,c.y,d.y))
            guard box.intersects(bounds),min(hypot(b.x-a.x,b.y-a.y),hypot(c.x-a.x,c.y-a.y))>52 else{continue}
            guard let doc=document(file.id) else{continue}
            let layout=SourceTileLayout(file:file,document:doc)
            let matrix=transform(layout,height:height,view:view)
            guard abs(matrix.a*matrix.d-matrix.b*matrix.c)>1e-12 else{continue}
            let pixelsPerUnit=min(hypot(matrix.a,matrix.b),hypot(matrix.c,matrix.d))
            let fontPixels=12*pixelsPerUnit
            guard fontPixels>0.32 else{continue}
            let localBounds=CGRect(x:0,y:0,width:layout.logicalWidth,height:layout.logicalHeight)
            let visible=bounds.applying(matrix.inverted()).intersection(localBounds)
            guard !visible.isNull else{continue}
            if atlas.currentMode == .landscape {
                // Only reveal source on exposed roofs; don't paint through foreground blocks.
                let samples=[CGPoint(x:visible.midX,y:visible.midY),CGPoint(x:visible.minX+1,y:visible.minY+1),CGPoint(x:visible.maxX-1,y:visible.minY+1),CGPoint(x:visible.minX+1,y:visible.maxY-1),CGPoint(x:visible.maxX-1,y:visible.maxY-1)].map{$0.applying(matrix)}.filter{bounds.contains($0)}
                guard !samples.isEmpty,samples.allSatisfy({atlas.pick($0)==file.id}) else{continue}
            }
            renderedFiles.insert(file.id)
            context.saveGState();context.concatenate(matrix);context.clip(to:localBounds)
            context.setFillColor(NSColor(hex:"102135",alpha:0.96).cgColor);context.fill(localBounds)
            context.setStrokeColor(store.nsColor(file.group).withAlphaComponent(0.8).cgColor);context.setLineWidth(1/max(0.001,pixelsPerUnit));context.stroke(localBounds)
            context.textMatrix=CGAffineTransform(scaleX:1,y:-1)
            // At intermediate zoom, true source line lengths supply the structure.
            // At reading zoom, the exact characters replace those small strokes.
            let firstColumn=max(0,Int(floor((visible.minX-SourceTileLayout.margin)/layout.columnWidth)))
            let lastColumn=min(layout.columns-1,Int(ceil(visible.maxX/layout.columnWidth)))
            let firstRow=max(0,Int(floor((visible.minY-SourceTileLayout.header)/SourceDocument.lineHeight))-1)
            let lastRow=min(layout.rowsPerColumn-1,Int(ceil((visible.maxY-SourceTileLayout.header)/SourceDocument.lineHeight))+1)
            if firstColumn<=lastColumn && firstRow<=lastRow {
                for column in firstColumn...lastColumn {
                    let strideRows=fontPixels<2.4 ? max(1,Int(ceil(1.1/(SourceDocument.lineHeight*pixelsPerUnit)))) : 1
                    for rowIndex in stride(from:firstRow,through:lastRow,by:strideRows) {
                        let index=layout.columnStarts[column]+rowIndex
                        let end=column+1<layout.columns ? layout.columnStarts[column+1] : doc.rows.count
                        guard index<end else{break}
                        let row=doc.rows[index],position=layout.position(row:index)
                        if fontPixels>=2.4 {
                            if file.id==store.selectedFile,let symbol=store.symbol,row.number==symbol.line {
                                context.setFillColor(NSColor(hex:"304B63").cgColor);context.fill(CGRect(x:position.x-4,y:position.y,width:layout.columnWidth-16,height:SourceDocument.lineHeight))
                            }
                            context.textPosition=CGPoint(x:position.x,y:position.y+12)
                            CTLineDraw(glyph(file:file.id,index:index,row:row,gutter:doc.gutterColumns),context)
                            renderedRows[file.id,default:[]].insert(row.number);textRowCount+=1
                        }else if !row.text.isEmpty {
                            let indent=row.text.prefix(while:{$0==" "}).count
                            let width=CGFloat(max(0,row.text.count-indent))*SourceDocument.advance
                            context.setFillColor(store.nsColor(file.group).withAlphaComponent(0.48).cgColor)
                            context.fill(CGRect(x:position.x+CGFloat(indent+doc.gutterColumns)*SourceDocument.advance,y:position.y+6,width:width,height:max(2,0.45/pixelsPerUnit)));densityRowCount+=1
                        }
                    }
                }
            }
            context.restoreGState()
            // Keep the identity readable while the top of a long source tile leaves view.
            if atlas.currentMode == .map {
                let clipped=box.intersection(bounds.insetBy(dx:2,dy:3))
                if clipped.width>110 && clipped.height>45 {
                    let title="\(file.path)  /  \(file.lines) lines"
                    let rect=NSRect(x:clipped.minX+4,y:min(box.maxY-25,bounds.maxY-89),width:max(0,min(clipped.width-8,420)),height:22)
                    if rect.maxY>clipped.minY+18 {
                        NSColor(hex:"142B43",alpha:0.97).setFill();rect.fill()
                        let style=NSMutableParagraphStyle();style.lineBreakMode = .byTruncatingMiddle
                        (title as NSString).draw(in:rect.insetBy(dx:7,dy:4),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.medium),.foregroundColor:store.nsColor(file.group),.paragraphStyle:style])
                    }
                }
            }
        }
        return renderedFiles
    }
    func focus(file:Int,line:Int?) {
        guard let atlas,let store=atlas.store,let view=atlas.view,let doc=document(file) else{return}
        let f=store.index.files[file],layout=SourceTileLayout(file:f,document:doc)
        let row=line.flatMap{line in doc.rows.firstIndex{$0.number==line}} ?? 0
        atlas.target=layout.worldPosition(row:row,height:CGFloat(atlas.heights[file] ?? 0))
        // 12 pt source and approximately one column in the available viewport.
        atlas.scale=max(0.002,Double(layout.unit*view.bounds.height*0.5))
        atlas.updateCamera(animated:false)
    }
}
