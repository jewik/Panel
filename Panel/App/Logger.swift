//
//  Logger.swift
//  Notch
//
//  Created by Usanin Ivan on 17.10.2026.
//

import os
import Foundation

enum Log {
    // 1. Define a shared subsystem name (usually your Bundle ID)
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.yourcompany.macutility"

    // 2. Create category-specific master loggers
    static let general = Logger(subsystem: subsystem, category: "General")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let service = Logger(subsystem: subsystem, category: "Service")
    static let network = Logger(subsystem: subsystem, category: "Network")
    
//    Log.service.info("Example: \(general)")
}
