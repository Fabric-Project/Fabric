//
//  DocumentWindowManager.swift
//  Fabric Editor
//
//  Created by Anton Marini on 10/28/25.
//

import Foundation
import AppKit
import Metal
import simd
import Fabric

class DocumentOutputWindowManager : NSObject
{
   var outputwindow:NSWindow? = nil
   var outputRenderer:CAMetalDisplayLinkRenderer? = nil

    override init()
    {
        self.outputwindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 600),
                                     styleMask: [.titled, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
                                     backing: .buffered, defer: false)
        self.outputwindow?.isReleasedWhenClosed = false
        self.outputwindow?.makeKeyAndOrderFront(nil)
        self.outputwindow?.level = .normal // NSWindow.Level(NSWindow.Level.normal.rawValue + 1)

        super.init()

        self.outputwindow?.delegate = self
    }
    
    func setGraph(graph:Graph)
    {
        self.outputRenderer = CAMetalDisplayLinkRenderer(graph:graph)
        self.outputRenderer?.frame = CGRect(x: 0,
                                            y: 0,
                                            width: self.outputwindow?.frame.size.width ?? 600,
                                            height: self.outputwindow?.frame.size.height ?? 600)
            
        self.outputwindow?.contentView = self.outputRenderer
    }
    
    func closeOutputWindow()
    {
        self.outputwindow?.close()
    }
    
    deinit
    {
        print("Free DocumentOutputWindowManager")
//        if Thread.isMainThread
//        {
//            self.outputwindow?.close()
//        }
//        else
//        {
//            DispatchQueue.main.sync { [weak self] in
//                self?.outputwindow?.close()
//            }
//        }
        
    }
}

extension DocumentOutputWindowManager: NSWindowDelegate
{
    func windowWillClose(_ notification: Notification)
    {
        // Tell the renderer to stop *all* time/display-linked work
        self.outputRenderer?.teardown()

        // Break strong reference cycles and detach the view from the window
        self.outputwindow?.contentView = nil
        self.outputRenderer = nil
    }
}
