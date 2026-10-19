/*
BSD 3-Clause License

Copyright (c) 2024, The Browser Company
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*/
import Foundation
import WinAppSDK
import WinSDK
@_spi(WinRTImplements) import WindowsFoundation

/// You should derive from SwiftApplication and mark this class as your @main entry point. This class
/// will ensure that the Windows Runtime is properly initialized and that your WinUI Application
/// is properly configured.
///
/// Example usage:
/// ```
/// import WinUI
///
/// @main
/// class MySwiftApp: SwiftApplication {
///   required init() {
///     super.init()
///   }
///
///  override func onLaunched(_ args: LaunchActivatedEventArgs) {
///    let window = Window()
///    window.content = TextBlock(text: "Hello, world!")
///    window.activate()
///   }
/// ```
open class SwiftApplication: Application, IXamlMetadataProvider {
    public typealias RunLoop = (DispatcherQueue) throws -> Int32
    private static weak var desktopApplication: SwiftApplication?

    public required override init() {
        super.init()
        SwiftApplication.desktopApplication = self
    }

    @_spi(WinRTImplements)
    override public func onLaunched(_ args: LaunchActivatedEventArgs?) {
        resources.mergedDictionaries.append(XamlControlsResources())
        onLaunched(args!)
    }

    /// If you've setup your project to be self-contained WinAppSDK
    open class var windowsAppSdkSelfContained: Bool { false }

    /// If you own your own run loop and don't want to use the WinUI one, override it here
    open class var runLoop: RunLoop { Self.defaultRunLoop }

    /// Override this method to provide your application's main entry point.
    /// The first window for your application should be created and activated here.
    open func onLaunched(_ args: LaunchActivatedEventArgs) {
    }

    /// Desktop input is offered to the app before WinUI menu preprocessing.
    open func preTranslateMessage(_ message: UnsafePointer<MSG>) -> Bool { false }

    private typealias pfnContentPreTranslateMessage = @convention(c) (UnsafePointer<MSG>?) -> Bool
    private static let contentPreTranslateMessage: pfnContentPreTranslateMessage = {
        let windowingDLL = LoadLibraryA("Microsoft.UI.Windowing.Core.dll")
        let contentPreTranslateMessage = GetProcAddress(windowingDLL, "ContentPreTranslateMessage")
        return unsafeBitCast(contentPreTranslateMessage!, to: pfnContentPreTranslateMessage.self)
    }()

    private static func defaultRunLoop(_ queue: DispatcherQueue) -> Int32 {
        // The below run loop is taken mostly from https://github.com/compnerd/swift-win32/blob/d34ff1b8b3f15cfdf2cb71109a3c313001122a54/Sources/SwiftWin32/App%20and%20Environment/ApplicationMain.swift#L183
        // with some tweaks for WinUI
        var msg: MSG = MSG()
        while true {

            // Process all messages in thread's message queue; for GUI applications UI
            // events must have high priority.
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    return Int32(msg.wParam)
                }

                if SwiftApplication.desktopApplication?.preTranslateMessage(&msg) == true { continue }
                if (!contentPreTranslateMessage(&msg)) {
                    TranslateMessage(&msg)
                    DispatchMessageW(&msg)
                }
            }

            // Foundation/Dispatch and WinUI share this thread. A nil deadline is
            // normal when there are no Foundation timers; never spin waiting for one.
            var deadline: Date?
            for _ in 0..<32 {
                deadline = Foundation.RunLoop.main.limitDate(forMode: .default)
                if deadline == nil || deadline!.timeIntervalSinceNow > 0 { break }
            }
            let seconds = min(0.03, max(0.001, deadline?.timeIntervalSinceNow ?? 0.03))
            _ = MsgWaitForMultipleObjects(0, nil, false, DWORD(seconds * 1_000), QS_ALLINPUT)

        }
        return 0
    }

    /// Override this method to provide any necessary shutdown code.
    open func onShutdown(exitCode: Int32) { }
    
    public static func main() {
        do {
            let appClass = String(describing: String(reflecting: Self.self))
            guard let instance = NSClassFromString(appClass) as? SwiftApplication.Type else {
                fatalError("unable to find application class \(appClass)")
            }

            try withExtendedLifetime(WindowsAppRuntimeInitializer(selfContained: instance.windowsAppSdkSelfContained)) {
                var application: SwiftApplication!
                let createAppCallback: (ApplicationInitializationCallbackParams?) -> Void = { _ in
                    application = instance.init()
                }
                let exitCode = try Application.startWithCustomRunLoop(instance.runLoop, createAppCallback)
              
                application.onShutdown(exitCode: exitCode)
            }
        }
        catch {
            fatalError("Failed to initialize WindowsAppRuntimeInitializer: \(error)")
        }
    }

    override open func queryInterface(_ iid: WindowsFoundation.IID) -> IUnknownRef? {
        switch iid {
        case __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper.IID:
            let ixmp = __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper(self)
            return ixmp?.queryInterface(iid)
        default:
            return super.queryInterface(iid)
        }
    }

    private lazy var metadataProvider: XamlControlsXamlMetaDataProvider = .init()
    public func getXamlType(_ type: TypeName) throws -> IXamlType! {
        try metadataProvider.getXamlType(type)
    }

    public func getXamlType(_ fullName: String) throws -> IXamlType! {
        try metadataProvider.getXamlType(fullName)
    }

    public func getXmlnsDefinitions() throws -> [XmlnsDefinition] {
        try metadataProvider.getXmlnsDefinitions()
    }
}
