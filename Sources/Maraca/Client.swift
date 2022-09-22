//
//  Client.swift
//  Maraca
//
//  Created by Chrishon Wyllie on 11/18/19.
//

import Foundation
import CaptureSDK
import WebKit.WKWebView

public class Client: NSObject, ClientConformanceProtocol {
    
    // MARK: - Variables
    
    internal private(set) var handle: ClientHandle!
    
    internal let ownershipId: String = UUID().uuidString
    
    internal static var disownedBlankId: String {
        // If this client does not have ownership, a
        // "blank" UUID string will be sent to the web
        // app using CaptureJS
        return "00000000-0000-0000-0000-000000000000"
    }
    
    internal private(set) var appInfo: SKTAppInfo?
    
    /// The URL of the webpage that opened the client.
    /// The Webview may navigate to other pages, but this client
    /// may only send JSON to this web page.
    internal private(set) var webpageURLString: String?
    
    internal private(set) weak var webview: WKWebView?
    
    internal private(set) var didOpenCapture: Bool = false
    
    internal private(set) var openedDevices: [ClientDeviceHandle : ClientDevice] = [:]
    
    required public override init() {
        super.init()
    }
}

// MARK: - Open / Close

extension Client {
    
    @discardableResult internal func openWithAppInfo(appInfo: SKTAppInfo, webview: WKWebView) throws -> ClientHandle {
        // => add new Client Instance to clients list in Maraca
        // => AppInfo Verify ==> TRUE
        // => send device Arrivals if devices connected
        // => return a handle
        
        guard didOpenCapture == false else {
            return handle
        }
        
        self.handle = Utility.generateUniqueHandle()
        
        guard appInfo.verify(withBundleId: appInfo.appID) == true else {
            throw MaracaError.invalidAppInfo("The AppInfo parameters are invalid")
        }
        
        self.appInfo = appInfo
        didOpenCapture = true
        
        self.webview = webview
        self.webpageURLString = webview.url?.absoluteString
        
        return handle
    }
    
    internal func open(captureHelperDevice: CaptureHelperDevice, jsonRPCObject: JsonRPCObject) {
        
        var clientDevice: ClientDevice!
        
        if hasPreviouslyOpened(device: captureHelperDevice) {
            clientDevice = getClientDevice(for: captureHelperDevice)
        } else {
            clientDevice = ClientDevice(captureHelperDevice: captureHelperDevice)
            openedDevices[clientDevice.handle] = clientDevice
        }
        
        let responseJsonRpc: JSONDictionary = [
            MaracaConstants.Keys.jsonrpc.rawValue:       jsonRPCObject.jsonrpc ?? Maraca.defaultJsonRpcVersion,
            MaracaConstants.Keys.id.rawValue:            jsonRPCObject.id ?? 2,
            MaracaConstants.Keys.result.rawValue: [
                MaracaConstants.Keys.handle.rawValue: clientDevice.handle
            ]
        ]
        
        replyToWebpage(with: responseJsonRpc)
        
        changeOwnership(forClientDeviceWith: clientDevice.handle, isOwned: true)
    }
    
    internal func close(responseId: Int) {
        openedDevices.removeAll()
        
        let responseJsonRpc: [String:  Any] = [
            MaracaConstants.Keys.jsonrpc.rawValue: Maraca.jsonRpcVersion ?? Maraca.defaultJsonRpcVersion,
            MaracaConstants.Keys.id.rawValue: responseId,
            MaracaConstants.Keys.result.rawValue: 0
        ]
        
        replyToWebpage(with: responseJsonRpc)
    }
    
    internal func closeDevice(withHandle handle: ClientDeviceHandle, responseId: Int) {
        guard let _ = openedDevices[handle] else {
            guard let webview = webview else {
                // The webview should not be nil
                fatalError("The Client must have been created without calling `openWithAppInfo`")
            }
            Utility.sendErrorResponse(withError: SKTResult.E_INVALIDHANDLE,
                                     webView: webview,
                                     handle: handle,
                                     responseId: responseId)
            return
        }
            
        openedDevices.removeValue(forKey: handle)
        
        let responseJsonRpc: [String:  Any] = [
            MaracaConstants.Keys.jsonrpc.rawValue: Maraca.jsonRpcVersion ?? Maraca.defaultJsonRpcVersion,
            MaracaConstants.Keys.id.rawValue: responseId,
            MaracaConstants.Keys.result.rawValue: 0
        ]
        
        replyToWebpage(with: responseJsonRpc)
    }
    
    internal func changeOwnership(forClientDeviceWith handle: ClientDeviceHandle, isOwned: Bool) {
        
        let responseJson: JSONDictionary = [
            MaracaConstants.Keys.jsonrpc.rawValue: Maraca.jsonRpcVersion ?? Maraca.defaultJsonRpcVersion,
            MaracaConstants.Keys.result.rawValue: [
                MaracaConstants.Keys.handle.rawValue: handle,
                MaracaConstants.Keys.event.rawValue: [
                    MaracaConstants.Keys.id.rawValue: SKTCaptureEventID.deviceOwnership.rawValue,
                    MaracaConstants.Keys.type.rawValue: SKTCaptureEventDataType.string.rawValue,
                    MaracaConstants.Keys.value.rawValue: (isOwned ? self.ownershipId : Client.disownedBlankId)
                ]
            ]
        ]
        notifyWebpage(with: responseJson)
    }
    
    internal func hasPreviouslyOpened(device: CaptureHelperDevice) -> Bool {
        return filterThroughOpenedDevices(matching: device) != nil
    }
        
    internal func getClientDevice(for device: CaptureHelperDevice) -> ClientDevice? {
        return filterThroughOpenedDevices(matching: device)
    }
    
    private func filterThroughOpenedDevices(matching device: CaptureHelperDevice) -> ClientDevice? {
        guard let deviceGuid = device.deviceInfo.guid else {
            return nil
        }
        return Array(openedDevices.values)
            .filter { return $0.guid == deviceGuid }.first
    }
    
    internal func resume() {
        guard didOpenCapture == true else {
            return
        }
        
        guard openedDevices.isEmpty == false else {
            return
        }
        
        for (handle, _) in openedDevices {
            changeOwnership(forClientDeviceWith: handle, isOwned: true)
        }
    }
    
    internal func suspend() {
        guard didOpenCapture == true else {
            return
        }
        
        guard openedDevices.isEmpty == false else {
            return
        }
        
        for (handle, _) in openedDevices {
            changeOwnership(forClientDeviceWith: handle, isOwned: false)
        }
    }
    
    // For responding back to a web page that has
    // opened a capture with a client, etc.
    internal func replyToWebpage(with jsonRpc: JSONDictionary) {
        sendJsonRpcToWebpage(jsonRpc: jsonRpc, javascriptFunctionName: "window.maraca.replyJsonRpc('")
    }
    
    // For sending information to the web page
    internal func notifyWebpage(with jsonRpc: JSONDictionary) {
        sendJsonRpcToWebpage(jsonRpc: jsonRpc, javascriptFunctionName: "window.maraca.receiveJsonRpc('")
    }
    
    private func sendJsonRpcToWebpage(jsonRpc: JSONDictionary, javascriptFunctionName: String) {
        
        guard webview?.url?.absoluteString == webpageURLString else {
            // Confirm that the WebView attached to this Client
            // is displaying the web page that originally opened it.
            // To prevent sending JSON to web applications that either
            // do not use CaptureJS or did not open a Client
            return
        }
        
        var javascript = javascriptFunctionName
        
        let jsonStringResult = Utility.convertJsonRpcToString(jsonRpc)
        switch jsonStringResult {
        case .success(let jsonString):
            
            // Refer to replyJSonRpc and receiveJsonRPC functions
            // REceive used for when received decoded data
            // reply for when replying back to web page that you opened the client, set a property etc.
            
            
            javascript.write(jsonString)
            
            
        case .failure(let error):
            let errorJSONStringResult = Utility.convertErrorToJSONString(error: error)
            switch errorJSONStringResult {
            case .success(let errorJSONString):
                // Refer to replyJSonRpc and receiveJsonRPC functions
                // REceive used for when received decoded data
                // reply for when replying back to web page that you opened the client, set a property etc.
                javascript.write(errorJSONString)
            case .failure(let error):
                let errorMessage = "Error converting JSON to String: \(error.localizedDescription)"
                javascript.write(errorMessage)
            }
        }
        
        javascript.write("'); ")
                
        webview?.evaluateJavaScript(javascript, completionHandler: { (object, error) in
            if let error = error {
                DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - error evaluating javascript expression: \(javascript). Error: \(error)\n")
            } else {
                DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - Success evaluating javascript expression: \(javascript)\n")
            }
        })
    }
}

// MARK: - Get / Set property

extension Client: ClientReceiverProtocol {
    
    internal func getProperty(with handle: ClientHandle, responseId: Int, property: SKTCaptureProperty) {
        
        if handle == self.handle {
            DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - Getting property from capture")
            
            getProperty(property: property, responseId: responseId) { (result) in
                self.replyToWebpage(with: resultDictionary(result))
            }
            
        } else if let _ = openedDevices[handle] {
            DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - Getting property from capture helper device")
            
            openedDevices[handle]?.getProperty(property: property, responseId: responseId, completion: { (result) in
                self.replyToWebpage(with: resultDictionary(result))
            })
            
        } else {
            
            let errorMessage = "There is no client or device with the specified handle. The device may have been recently closed"
            let errorResponseJsonRpc = Utility.constructErrorResponse(error: SKTResult.E_INVALIDHANDLE,
                                                                     errorMessage: errorMessage,
                                                                     handle: handle,
                                                                     responseId: responseId)
            DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - error response json rpc: \(errorResponseJsonRpc)")
            
            self.replyToWebpage(with: errorResponseJsonRpc)
        }
    }
    
    internal func setProperty(with handle: ClientHandle, responseId: Int, property: SKTCaptureProperty) {
        
        if handle == self.handle {
            // TODO
            // Will this affect other Clients?
            // Each Client instance uses a single CaptureHelper
            // shared instance
            // So setting a property to a particular value might
            // affect other Clients that don't want this.
            setProperty(property: property, responseId: responseId) { (result) in
                self.replyToWebpage(with: resultDictionary(result))
            }
        } else if let _ = openedDevices[handle] {
            openedDevices[handle]?.setProperty(property: property, responseId: responseId, completion: { (result) in
                self.replyToWebpage(with: resultDictionary(result))
            })
        } else {
            let errorResponseJsonRpc = Utility.constructErrorResponse(error: SKTResult.E_INVALIDHANDLE,
                                                                     errorMessage: "There is no client or device with the specified handle. The device may have been recently closed",
                                                                     handle: handle,
                                                                     responseId: responseId)
            self.replyToWebpage(with: errorResponseJsonRpc)
        }
    }
    
    
    
    
    
    
    
    internal func getProperty(property: SKTCaptureProperty, responseId: Int, completion: @escaping ClientReceiverCompletionHandler) {
        Maraca.shared.capture.getProperty(property) { (result, resultProperty) in
            
            guard result == SKTResult.E_NOERROR else {
                print(property.id.rawValue)
                print(property.type.rawValue)
                let errorResponseJsonRpc = Utility.constructErrorResponse(error: result,
                                                                         errorMessage: "There was an error with getting property from Capture. Error: \(result)",
                                                                         handle: self.handle,
                                                                         responseId: responseId)
                
                completion(.failure(ErrorResponse(json: errorResponseJsonRpc)))
                return
            }
            
            // Used a different name to differentiate between the three
            guard let unwrappedProperty = resultProperty else {
                // TODO
                // Return with some kind of error response instead.
                // But if the result != E_NOERROR, this will not be reached anyway.
                fatalError("This is an issue with CaptureHelper if the SKTCaptureProperty is nil")
            }
            
            do {
                let jsonFromGetProperty = try unwrappedProperty.jsonFromGetProperty(with: responseId)
                completion(.success(jsonFromGetProperty))
            } catch let error {
                DebugLogger.shared.addDebugMessage("\(String(describing: type(of: self))) - Error converting SKTCaptureProperty to a dictionary: \(error)")
                
                // Send an error response Json back to the web page
                // if a dictionary cannot be constructed from
                // the resulting SKTCaptureProperty
                let errorResponseJsonRpc = Utility.constructErrorResponse(error: SKTResult.E_INVALIDPARAMETER,
                                                                         errorMessage: error.localizedDescription,
                                                                         handle: self.handle,
                                                                         responseId: responseId)
                
                completion(.failure(ErrorResponse(json: errorResponseJsonRpc)))
            }
        }
    }
    
    internal func setProperty(property: SKTCaptureProperty, responseId: Int, completion: @escaping ClientReceiverCompletionHandler) {
        
        Maraca.shared.capture.setProperty(property) { (result, property) in
            
            guard result == .E_NOERROR else {
                
                let errorResponseJsonRpc = Utility.constructErrorResponse(error: result,
                                                                         errorMessage: "There was an error with setting property. Error: \(result)",
                                                                         handle: self.handle,
                                                                         responseId: responseId)
                
                completion(.failure(ErrorResponse(json: errorResponseJsonRpc)))
                return
            }
            
            let jsonRpc: [String : Any] = [
                MaracaConstants.Keys.jsonrpc.rawValue : Maraca.jsonRpcVersion ?? Maraca.defaultJsonRpcVersion,
                MaracaConstants.Keys.id.rawValue : responseId,
                MaracaConstants.Keys.result.rawValue: [
                    MaracaConstants.Keys.handle.rawValue : self.handle
                    // We might send the property back as well.
                ]
            ]
            
            completion(.success(jsonRpc))
        }
    }

}
