// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "CappellaWinRT", products: [
    .library(name: "WinUI", type: .static, targets: ["WinUI"]),
    .library(name: "UWP", type: .static, targets: ["UWP"]),
    .library(name: "WinAppSDK", type: .static, targets: ["WinAppSDK"]),
    .library(name: "WindowsFoundation", type: .static, targets: ["WindowsFoundation"])
], targets: [
    .target(name: "CWinRT", linkerSettings: [.linkedLibrary("runtimeobject"), .linkedLibrary("ole32")]),
    .target(name: "CWinAppSDK"),
    .target(name: "WindowsFoundation", dependencies: ["CWinRT"]),
    .target(name: "UWP", dependencies: ["CWinRT", "WindowsFoundation"]),
    .target(name: "WinAppSDK", dependencies: ["CWinRT", "CWinAppSDK", "WindowsFoundation", "UWP"]),
    .target(name: "WinUI", dependencies: ["CWinRT", "WindowsFoundation", "UWP", "WinAppSDK"])
])
