//
//  ConnectionModule.swift
//  sample-videochat-webrtc-swift
//
//  Created by Injoit on 02.04.2021.
//  Copyright © 2021 QuickBlox. All rights reserved.
//

import UIKit
import Quickblox
import QuickbloxWebRTC
import SystemConfiguration

typealias CompletionAction = (() -> Void)
typealias DisconnectionAction = ((Bool?) -> Void)

/// The module is responsible for automatic connection establishment with QuickBlox.
///
/// The connection depends on the application state and call activity.
/// The establishing connection process can start from the authorization if the "QBSession" token was expired.
class ConnectionModule: NSObject {
    //MARK: - Properties
    /// Determining the connection state.
    ///
    /// Calling this property starts the connection process when it's not established.
    var established: Bool {
        var connected = false
        if tokenHasExpired == false, QBChat.instance.isConnected {
            connected = true
        }
        
        if connected == false {
            establishConnection()
        }
        return connected
    }
    /// The authorization process running.
    private(set) var isProcessing: Bool = false
    /// Determining the "QBSession" token state.
    var tokenHasExpired: Bool {
        return QBSession.current.tokenHasExpired
    }

    /// Called when "QBSession" token was expired and authorization is started.
    var onStartAuthorization: CompletionAction?
    /// Called when authorization complete.
    var onAuthorize: CompletionAction?
    /// Called when "QBSession" token was expired and authorization is failed.
    var onAuthorizeFailed: CompletionAction?
    /// Called when the connection started establishing.
    var onStartConnection: CompletionAction?
    /// Called when the connection was established or re-established.
    var onConnect: CompletionAction?
    /// Called when connection lost.
    var onDisconnect: DisconnectionAction?

    private var appActiveStateObserver: Any?
    private var appInactiveStateObserver: Any?
    
    private var isReachability: SCNetworkReachability? {
        return reachability()
    }
    private var isNetwork: Bool? {
        var flags: SCNetworkReachabilityFlags = []
        guard let reachability = isReachability,
              SCNetworkReachabilityGetFlags(reachability, &flags) else {
            return nil
        }
        return flags.contains(.reachable)
    }
    
    private var activeCall: Bool = false
    
    
    //MARK: - Life Cycle
    override init() {
        super.init()
        
        QBSettings.autoReconnectEnabled = true
        QBSettings.networkIndicatorManagerEnabled = true
        QBChat.instance.addDelegate(self)
    }
    
    deinit {
        QBChat.instance.removeDelegate(self)
    }
    
    // MARK: - Public Methods
    func reachability() -> SCNetworkReachability? {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
       let isReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        })
        return isReachability
    }

    func setupAppActiveStateObserver() {
        if appActiveStateObserver != nil {
            return
        }
        let center = NotificationCenter.default
        appActiveStateObserver = center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                    object: nil,
                                                    queue: OperationQueue.main,
                                                    using: { [weak self] (note) in
                                                        guard let self = self else { return }
                                                        self.establishConnection()
                                                    })
    }
    
    func setupAppInactiveStateObserver() {
        if appInactiveStateObserver != nil {
            return
        }
        let center = NotificationCenter.default
        appInactiveStateObserver = center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                      object: nil,
                                                      queue: OperationQueue.main,
                                                      using: { [weak self] (note) in
                                                        guard let self = self else { return }
                                                        if self.activeCall == true { return }
                                                        self.disconnect()
                                                      })
    }

    /// Activating the automatic connection and disconnection process when the application state change.
    ///
    /// Calling this method starts the connection process when it's not established.
    func activateAutomaticMode() {
        setupAppActiveStateObserver()
        
        setupAppInactiveStateObserver()
        
        establishConnection()
    }
    
    /// Prevents breaking connection when the application state change.
    func activateCallMode() {
        activeCall = true
    }
    
    /// Break connection when application state is inactive.
    func deactivateCallMode() {
        activeCall = false
        if UIApplication.shared.applicationState == .active {
            return
        }
        disconnect()
    }
    
    /// Stop trying connection automatically.
    func deactivateAutomaticMode() {
        let center = NotificationCenter.default
        center.removeObserver(appActiveStateObserver as Any)
        center.removeObserver(appInactiveStateObserver as Any)
    }
    
    /// Establishes a connection with the Quickblox.
    func establishConnection() {
        
        let profile = Profile()
        guard profile.isFull else {
            return
        }
        
        if QBSession.current.tokenHasExpired {
            if isProcessing {
                return
            }
            isProcessing = true
            
            onStartAuthorization?()
            
            QBRequest.logIn(withUserLogin: profile.login, password: profile.password, successBlock: { [weak self] response, user in
                guard let self = self else { return }
                
                self.isProcessing = false
                self.onAuthorize?()
                self.connect(withId: profile.ID, password: profile.password)
                
            }, errorBlock: { [weak self] response in
                self?.isProcessing = false
                self?.onAuthorizeFailed?()
            })
            return
        }
        self.connect(withId: profile.ID, password: profile.password)
    }
    
    /// Disconnects and unauthorize from the Quickblox.
    func breakConnection(withCompletion completion:@escaping CompletionAction) {
        if isProcessing {
            return
        }
        isProcessing = true
        
        if QBChat.instance.isConnected == false {
            logout(withCompletion: completion)
            return
        }
        
        QBChat.instance.disconnect { [weak self] (error) in
            self?.logout(withCompletion: completion)
        }
    }
    
    //MARK: - Internal
    private func logout(withCompletion completion:@escaping CompletionAction) {
        QBRequest.logOut(successBlock: { [weak self] response in
            self?.isProcessing = false
            completion()
        }) {  [weak self] response in
            self?.isProcessing = false
            completion()
        }
    }

    private func connect(withId userID:UInt, password: String) {
        if QBChat.instance.isConnected || QBChat.instance.isConnecting {
            return
        }
        onStartConnection?()
        QBChat.instance.connect(withUserID: userID, password: password, completion: nil)
        return
    }
    
    private func disconnect() {
        if QBChat.instance.isConnected == false { return }
        QBChat.instance.disconnect(completionBlock: nil)
    }
}

//MARK: - QBChatDelegate
extension ConnectionModule: QBChatDelegate {
    func chatDidConnect() {
        onConnect?()
    }
    
    func chatDidNotConnectWithError(_ error: Error) {
        onDisconnect?(isNetwork)
    }
    
    func chatDidDisconnectWithError(_ error: Error?) {
        guard error != nil else { return }
        onDisconnect?(isNetwork)
    }
    
    func chatDidReconnect() {
        onConnect?()
    }
}
