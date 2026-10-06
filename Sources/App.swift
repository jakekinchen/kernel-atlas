import AppKit
import SwiftUI

final class AppDelegate:NSObject,NSApplicationDelegate {
    var window:NSWindow?;var store:AtlasStore?
    func applicationDidFinishLaunching(_ notification:Notification) {
        do {
            let resources=Bundle.main.resourceURL ?? URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Corpus")
            let store=try AtlasStore(resources:resources);self.store=store
            let available=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1500,height:950)
            let frame=NSRect(x:0,y:0,width:min(1480,available.width-32),height:min(940,available.height-32))
            let window=NSWindow(contentRect:frame,styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            self.window=window;window.title="Kernel Atlas — Linux 1.0";window.titlebarAppearsTransparent=true
            window.titleVisibility = .hidden;window.toolbar=nil
            window.backgroundColor=NSColor(hex:"122033");window.appearance=NSAppearance(named:.darkAqua)
            window.contentView=NSHostingView(rootView:AtlasRoot(store:store).padding(.top,28).background(atlasPanel))
            window.minSize=NSSize(width:1120,height:750);window.center();window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps:true)
            if let index=CommandLine.arguments.firstIndex(of:"--verify"),CommandLine.arguments.indices.contains(index+1) {
                let folder=URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
                DispatchQueue.main.asyncAfter(deadline:.now()+2){Verification.run(store:store,window:window,output:folder)}
            }
        } catch {
            let alert=NSAlert();alert.messageText="Kernel Atlas could not open its source index";alert.informativeText=error.localizedDescription;alert.runModal();NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
}

@main struct KernelAtlas {
    static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let delegate=AppDelegate();app.delegate=delegate
        let menu=NSMenu();let item=NSMenuItem();menu.addItem(item)
        let appMenu=NSMenu();item.submenu=appMenu
        appMenu.addItem(withTitle:"About Kernel Atlas",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Hide Kernel Atlas",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(withTitle:"Quit Kernel Atlas",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let edit=NSMenuItem();edit.title="Edit";let em=NSMenu(title:"Edit");edit.submenu=em
        em.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        em.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        em.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a");menu.addItem(edit)
        let win=NSMenuItem();win.title="Window";let wm=NSMenu(title:"Window");win.submenu=wm
        wm.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        wm.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w");menu.addItem(win);app.windowsMenu=wm
        app.mainMenu=menu;app.run();withExtendedLifetime(delegate){}
    }
}
