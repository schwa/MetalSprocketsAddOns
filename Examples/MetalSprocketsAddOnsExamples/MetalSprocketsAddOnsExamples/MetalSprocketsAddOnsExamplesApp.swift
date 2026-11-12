//
//  MetalSprocketsAddOnsExamplesApp.swift
//  MetalSprocketsAddOnsExamples
//
//  Created by Jonathan Wight.
//

import MetalSprocketsAddOnsExamplesSupport
import SwiftUI

@main
struct MetalSprocketsAddOnsExamplesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(visionOS)
        ImmersiveDemoSpace()
        #endif
    }
}
