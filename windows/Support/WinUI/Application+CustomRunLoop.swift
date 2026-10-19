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
import Dispatch
import Foundation
import WinAppSDK

extension Application {
    /// same as WinUI.Application.start, but with RunLoop and Dispatch support.
    /// - Parameter handler: initialize the Application in this handler
    /// - Parameter runLoop: this is called once the Application is initialized, and is responsible for running the RunLoop
    public static func startWithCustomRunLoop(_ runLoop: SwiftApplication.RunLoop,
        _ handler: @MainActor (ApplicationInitializationCallbackParams?) -> Void
    ) throws -> Int32 {
        try MainActor.assumeIsolated {
            // A DispatcherQueue must exist on the thread before initializing WindowsXamlManager
            // We create a dispatcherQueueController to create and manage the DispatcherQueue
            let dispatcherQueueController: DispatcherQueueController = try DispatcherQueueController.createOnCurrentThread()

            handler(nil)

            guard let application = Application.current else {
                fatalError("Application not created in callback")
            }

            let xamlManager: WindowsXamlManager = try WindowsXamlManager.initializeForCurrentThread()
            application.dispatcherShutdownMode = .onLastWindowClose
            return try withExtendedLifetime([xamlManager, dispatcherQueueController, application]) {
                try runLoop(dispatcherQueueController.dispatcherQueue)
            }
        }
    }
}
