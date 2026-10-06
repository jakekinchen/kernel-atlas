import AppKit
let size=NSSize(width:1024,height:1024)
let image=NSImage(size:size)
func c(_ hex:UInt32)->NSColor {NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)}
func polygon(_ points:[NSPoint],_ color:NSColor) {let p=NSBezierPath();p.move(to:points[0]);for v in points.dropFirst(){p.line(to:v)};p.close();color.setFill();p.fill()}
func cube(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ d:CGFloat,_ h:CGFloat,_ color:NSColor) {
    let a=NSPoint(x:x,y:y), b=NSPoint(x:x+w,y:y+w*0.48), e=NSPoint(x:x-d,y:y+d*0.48), f=NSPoint(x:x+w-d,y:y+(w+d)*0.48)
    polygon([a,b,NSPoint(x:b.x,y:b.y+h),NSPoint(x:a.x,y:a.y+h)],color.blended(withFraction:0.38,of:.black)!)
    polygon([a,e,NSPoint(x:e.x,y:e.y+h),NSPoint(x:a.x,y:a.y+h)],color.blended(withFraction:0.18,of:.black)!)
    polygon([NSPoint(x:a.x,y:a.y+h),NSPoint(x:b.x,y:b.y+h),NSPoint(x:f.x,y:f.y+h),NSPoint(x:e.x,y:e.y+h)],color)
}
image.lockFocus()
let bg=NSBezierPath(roundedRect:NSRect(x:42,y:42,width:940,height:940),xRadius:205,yRadius:205)
NSGradient(starting:c(0x263D56),ending:c(0x102034))!.draw(in:bg,angle:-65)
cube(502,195,375,355,44,c(0x57758B))
cube(501,248,322,303,20,c(0x253D52))
cube(485,430,155,140,204,c(0x7EABEE))
cube(334,356,141,108,145,c(0x69C8B1))
cube(595,332,179,121,235,c(0xE9B971))
cube(493,273,85,145,140,c(0xBAA0DE))
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
