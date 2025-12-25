//
//  Keystone.swift
//  Keystone - A Cross-Platform Code Editor for SwiftUI
//
//  A comprehensive code editor component for iOS and macOS built with SwiftUI.
//  Features include syntax highlighting, line numbers, invisible characters,
//  bracket matching, code folding, and more.
//

import SwiftUI

// MARK: - Public API

/// The main entry point for the Keystone code editor library.
public enum Keystone {
    /// The current version of the Keystone library.
    public static let version = "1.0.0"
}

// Re-export all public types
public typealias Editor = KeystoneEditor
public typealias Configuration = KeystoneConfiguration
public typealias Theme = KeystoneTheme
