//
//  ChatManager.swift
//  sample-chat-swift
//
//  Created by Injoit on 1/28/19.
//  Copyright © 2019 Quickblox. All rights reserved.
//

import UIKit
import Quickblox

enum UIUserInterfaceIdiom : Int
{
  case Unspecified
  case Phone
  case Pad
}

struct ScreenSize
{
  static let SCREEN_WIDTH         = UIScreen.main.bounds.size.width
  static let SCREEN_HEIGHT        = UIScreen.main.bounds.size.height
  static let SCREEN_MAX_LENGTH    = max(ScreenSize.SCREEN_WIDTH, ScreenSize.SCREEN_HEIGHT)
  static let SCREEN_MIN_LENGTH    = min(ScreenSize.SCREEN_WIDTH, ScreenSize.SCREEN_HEIGHT)
}

struct DeviceType
{
  static let IS_IPHONE_4_OR_LESS  = UIDevice.current.userInterfaceIdiom == .phone && ScreenSize.SCREEN_MAX_LENGTH < 568.0
  static let IS_IPHONE_5          = UIDevice.current.userInterfaceIdiom == .phone && ScreenSize.SCREEN_MAX_LENGTH == 568.0
  static let IS_IPHONE_6          = UIDevice.current.userInterfaceIdiom == .phone && ScreenSize.SCREEN_MAX_LENGTH == 667.0
  static let IS_IPHONE_6P         = UIDevice.current.userInterfaceIdiom == .phone && ScreenSize.SCREEN_MAX_LENGTH == 736.0
  static let IS_IPAD              = UIDevice.current.userInterfaceIdiom == .pad && ScreenSize.SCREEN_MAX_LENGTH == 1024.0
}

enum MessageType : String {
    case createGroupDialog = "1"
    case addUsersToGroupDialog = "2"
    case leaveGroupDialog = "3"
}

struct ChatManagerConstant {
    static let messagesLimitPerDialog = 30
    static let usersLimit: UInt = 100
    static let chatServiceDomain = "com.q-municate.chatservice"
    static let errorDomaimCode = -1000
    static let notFound = "SA_STR_DIALOG_REMOVED".localized
}

protocol ChatManagerDelegate: class {
    func chatManagerWillUpdateStorage(_ chatManager: ChatManager)
    func chatManager(_ chatManager: ChatManager, didFailUpdateStorage message: String)
    func chatManager(_ chatManager: ChatManager, didUpdateStorage message: String)
    func chatManager(_ chatManager: ChatManager, didUpdateChatDialog chatDialog: QBChatDialog)
}

typealias DialogsIterationHandler = (_ response: QBResponse?,
    _ objects: [QBChatDialog]?,
    _ usersIDs: Set<NSNumber>?,
    _ stop: Bool?) -> Void
typealias DialogsPage = (_ page: QBResponsePage) -> Void
typealias DialogCompletion = (_ response: QBResponse?, _ dialog: QBChatDialog?) -> Void

typealias UsersIterationHandler = (_ response: QBResponse?, _ objects: [QBUUser]?, _ stop: Bool?) -> Void
typealias UsersPage = (_ page: QBGeneralResponsePage) -> Void

typealias MessagesCompletion = ( _ messages: [QBChatMessage],
    _ isLast: Bool) -> Void

typealias MessagesErrorHandler = (_ error: String?) -> Void

class ChatManager: NSObject {
    
    //MARK: - Properties
    
    weak var delegate: ChatManagerDelegate?
    
    var storage = ChatStorage()
    
    //MARK: - Life Cycle
    //Shared Instance
    static let instance: ChatManager = {
        let instance = ChatManager()
        return instance
    }()
    
    //MARK: - Public Methods
    func updateStorage() {
        self.delegate?.chatManagerWillUpdateStorage(self)
        if Reachability.instance.networkConnectionStatus() == .notConnection {
            SVProgressHUD.dismiss()
            return
        }
        
        var message = ""
        updateAllDialogs(withPageLimit: DialogsConstant.dialogsPageLimit,
                         completion: { (response: QBResponse?) -> Void in
                            if let response = response {
                                message = self.errorMessage(response: response) ?? ""
                            }
                            if message.isEmpty {
                                self.delegate?.chatManager(self, didUpdateStorage: "SA_STR_COMPLETED".localized)
                            } else {
                                self.delegate?.chatManager(self, didFailUpdateStorage: message)
                            }
        })
    }
    
    func sendLeaveMessage(_ text: String,
                          to dialog: QBChatDialog,
                          completion: @escaping QBChatCompletionBlock) {
        
        let currentUser = Profile()
        guard currentUser.isFull == true else {
            return
        }
        
        let message = QBChatMessage()
        message.senderID = currentUser.ID
        message.text = text
        message.markable = true
        message.deliveredIDs = [(NSNumber(value: currentUser.ID))]
        message.readIDs = [(NSNumber(value: currentUser.ID))]
        message.customParameters["save_to_history"] = true
        message.customParameters["notification_type"] = MessageType.leaveGroupDialog.rawValue
        
        let systemMessage = QBChatMessage()
        systemMessage.senderID = currentUser.ID
        systemMessage.markable = false
        systemMessage.text = text
        systemMessage.deliveredIDs = [(NSNumber(value: currentUser.ID))]
        systemMessage.readIDs = [(NSNumber(value: currentUser.ID))]
        systemMessage.customParameters["notification_type"] = MessageType.leaveGroupDialog.rawValue
        systemMessage.customParameters["dialog_id"] = dialog.id
        
        guard let occupantIDs = dialog.occupantIDs else {
            return
        }
        
        dialog.send(message, completionBlock: { error in
            completion(error)
        })
        for occupantID in occupantIDs {
            if currentUser.ID == occupantID.intValue {
                continue
            }
            systemMessage.recipientID = occupantID.uintValue
            QBChat.instance.sendSystemMessage(systemMessage)
        }
        
    }
    
    func sendAddingMessage(_ text: String,
                           action: DialogAction,
                           withUsers usersIDs: [NSNumber],
                           to dialog: QBChatDialog,
                           completion: @escaping QBChatCompletionBlock) {
        let currentUser = Profile()
        guard currentUser.isFull == true else {
            return
        }
        
        let IDs = usersIDs.map({ $0.stringValue }).joined(separator: ",")
        
        guard dialog.occupantIDs != nil else {
            return
        }
        
        let chatMessage = QBChatMessage()
        chatMessage.senderID = currentUser.ID
        chatMessage.dialogID = dialog.id
        chatMessage.deliveredIDs = [(NSNumber(value: currentUser.ID))]
        chatMessage.readIDs = [(NSNumber(value: currentUser.ID))]
        chatMessage.text = text
        chatMessage.markable = true
        chatMessage.customParameters["save_to_history"] = true
        if action == .create {
            chatMessage.customParameters["notification_type"] = MessageType.createGroupDialog.rawValue
        } else if action == .add {
            chatMessage.customParameters["notification_type"] = MessageType.addUsersToGroupDialog.rawValue
            chatMessage.customParameters["new_occupants_ids"] = IDs
        }
        
        let systemMessage = QBChatMessage()
        systemMessage.senderID = currentUser.ID
        systemMessage.markable = false
        systemMessage.text = text
        systemMessage.deliveredIDs = [(NSNumber(value: currentUser.ID))]
        systemMessage.readIDs = [(NSNumber(value: currentUser.ID))]

        if action == .create {
            systemMessage.customParameters["notification_type"] = MessageType.createGroupDialog.rawValue
        } else if action == .add {
            systemMessage.customParameters["notification_type"] = MessageType.addUsersToGroupDialog.rawValue
        }
        systemMessage.customParameters["dialog_id"] = dialog.id
        
        dialog.send(chatMessage, completionBlock: { error in
            completion(error)
        })
        for occupantID in usersIDs {
            if currentUser.ID == occupantID.intValue {
                continue
            }
            systemMessage.recipientID = occupantID.uintValue
            QBChat.instance.sendSystemMessage(systemMessage)
        }
    }
    
    //MARK: - Users
    func loadUser(_ id: UInt, completion: ((QBUUser?) -> Void)? = nil) {
        QBRequest.user(withID: id, successBlock: { (response, user) in
            self.storage.update(users: [user])
            completion?(user)
        }) { (response) in
            debugPrint("[ChatManager] loadUser error: \(self.errorMessage(response: response) ?? "")")
            completion?(nil)
        }
    }
    
    func searchUsers(_ name: String,  currentPage: UInt, perPage: UInt, completion: @escaping (_ response: QBResponse?, _ objects: [QBUUser], _ cancel: Bool) -> Void) {
        let page = QBGeneralResponsePage(currentPage: currentPage, perPage: perPage)
        QBRequest.users(withFullName: name, page: page,
                        successBlock: { (response, page, users) in
                            let cancel = users.count < page.perPage
                            completion(nil, users, cancel)
        }, errorBlock: { response in
            completion(response, [], false)
            debugPrint("[ChatManager] searchUsers error: \(self.errorMessage(response: response) ?? "")")
        })
    }
    
    func fetchUsers(currentPage: UInt, perPage: UInt, completion: @escaping (_ response: QBResponse?, _ objects: [QBUUser], _ cancel: Bool) -> Void) {
        let page = QBGeneralResponsePage(currentPage: currentPage, perPage: perPage)
        QBRequest.users(withExtendedRequest: ["order": "desc date last_request_at"],
                        page: page,
                        successBlock: { (response, page, users) in
                            let cancel = users.count < page.perPage
                            completion(nil, users, cancel)
        }, errorBlock: { response in
            completion(response, [], false)
            debugPrint("[ChatManager] searchUsers error: \(self.errorMessage(response: response) ?? "")")
        })
    }
    
    // MARK: - Dialogs
    func createGroupDialog(withName name: String,
                           photo: String?,
                           occupants: [QBUUser],
                           completion: DialogCompletion? = nil) {
        
        let chatDialog = QBChatDialog(dialogID: nil, type: .group)
        
        chatDialog.name = name
        chatDialog.occupantIDs = occupants.map({ NSNumber(value: $0.id) })
        
        QBRequest.createDialog(chatDialog, successBlock: { response, dialog in
            dialog.join(completionBlock: { (error) in
                if error != nil {
                    completion?(response, nil)
                    return
                }
                self.storage.update(dialogs:[dialog])
                //Notify about create new dialog
                let dialogName = dialog.name ?? ""
                self.delegate?.chatManager(self, didUpdateStorage: "SA_STR_CREATE_NEW".localized + dialogName)
                completion?(response, dialog)
            })
        }, errorBlock: { response in
            debugPrint("[ChatManager] createGroupDialog error: \(self.errorMessage(response: response) ?? "")")
            completion?(response, nil)
        })
    }
    
    func createPrivateDialog(withOpponent opponent: QBUUser,
                             completion: DialogCompletion? = nil) {
        assert(opponent.id > 0, "Incorrect user ID")
        if let dialog = storage.privateDialog(opponentID: opponent.id) {
            completion?(nil, dialog)
        } else {
            let currentUser = Profile()
            guard currentUser.isFull == true else {
                return
            }
            let dialog = QBChatDialog(dialogID: nil, type: .private)
            dialog.occupantIDs = [NSNumber(value: opponent.id)]
            QBRequest.createDialog(dialog, successBlock: { response, createdDialog in
                self.storage.update(dialogs:[createdDialog])
                //Notify about create new dialog
                let dialogName = createdDialog.name ?? ""
                self.delegate?.chatManager(self, didUpdateStorage: "SA_STR_CREATE_NEW".localized + dialogName)
                completion?(response, createdDialog)
            }, errorBlock: { response in
                debugPrint("[ChatManager] createPrivateDialog error: \(self.errorMessage(response: response) ?? "")")
                completion?(response, nil)
            })
        }
    }
    
    func leaveDialog(withID dialogId: String, completion: ((QBResponse?) -> Void)? = nil) {
        guard let dialog = storage.dialog(withID: dialogId) else {
            return
        }
        
        switch dialog.type {
        case .private:
            QBRequest.deleteDialogs(withIDs: Set([dialogId]),
                                    forAllUsers: false,
                                    successBlock: {
                                        response,
                                        deletedObjectsIDs, notFoundObjectsIDs, wrongPermissionsObjectsIDs in
                                        
                                        self.storage.deleteDialog(withID: dialogId)
                                        self.delegate?.chatManager(self, didUpdateStorage: "SA_STR_COMPLETED".localized)
                                        completion?(nil)
                                        
            }, errorBlock: { response in
                if (response.status == .notFound || response.status == .forbidden), dialog.type != .publicGroup {
                    self.storage.deleteDialog(withID: dialogId)
                }
                let errorMessage = self.errorMessage(response: response)
                self.delegate?.chatManager(self, didFailUpdateStorage: errorMessage ?? "")
            })
        case .group:
            QBRequest.update(dialog, successBlock: { (response, dialog) in
                self.storage.deleteDialog(withID: dialogId)
                self.delegate?.chatManager(self, didUpdateStorage: "SA_STR_COMPLETED".localized)
                completion?(nil)
            }) { (response) in
                if (response.status == .notFound || response.status == .forbidden), dialog.type != .publicGroup {
                    self.storage.deleteDialog(withID: dialogId)
                }
                let errorMessage = self.errorMessage(response: response)
                self.delegate?.chatManager(self, didFailUpdateStorage: errorMessage ?? "")
                completion?(response)
            }
        case .publicGroup:
            break
        }
    }
    
    func loadDialog(withID dialogID: String, completion: @escaping (_ loadedDialog: QBChatDialog?) -> Void) {
        let responsePage = QBResponsePage(limit: 1, skip: 0)
        let extendedRequest = ["_id": dialogID]
        QBRequest.dialogs(for: responsePage, extendedRequest: extendedRequest,
                          successBlock: { response, dialogs, dialogsUsersIDs, page in
                            guard let chatDialog = dialogs.first else {
                                completion(nil)
                                return
                            }
                            let usersIDs: Set<NSNumber> = Set(self.storage.users.map({ NSNumber(value: $0.id) }))
                            let usersForDownload = dialogsUsersIDs.subtracting(usersIDs)
                            if usersForDownload.isEmpty == false {
                                let downloadUsersIDs = usersForDownload.map({ $0.stringValue })
                                self.loadUsers(downloadUsersIDs) { (response) in
                                    if let error = response?.error?.error {
                                        debugPrint("[ChatManager] loadUsers error: \(error.localizedDescription)")
                                    }
                                }
                            }
                            self.storage.update(dialogs:[chatDialog])
                            completion(chatDialog)
        }, errorBlock: { response in
            completion(nil)
            debugPrint("[ChatManager] loadDialog error: \(self.errorMessage(response: response) ?? "")")
        })
    }
    
    private func prepareDialog(with dialogID: String, with message: QBChatMessage) {
        let currentUser = Profile()
        if let dialog = storage.dialog(withID: dialogID) {
            dialog.updatedAt = message.dateSent
            dialog.lastMessageDate = message.dateSent
            dialog.lastMessageText = message.text
            if currentUser.isFull == true,
                message.senderID != currentUser.ID {
                dialog.unreadMessagesCount = dialog.unreadMessagesCount + 1
            }
            
            if message.attachments?.isEmpty == false {
                dialog.lastMessageText = "[Attachment]"
            }
            if let notificationType = message.customParameters["notification_type"] as? String {
                
                switch(notificationType) {
                case MessageType.createGroupDialog.rawValue: break
                case MessageType.addUsersToGroupDialog.rawValue:
                    if let occupantIDs = dialog.occupantIDs,
                        let strIDs = message.customParameters["new_occupants_ids"] as? String {
                        let strArray: [String] = strIDs.components(separatedBy: ",")
                        
                        var newOccupantIDs: [NSNumber] = []
                        var missingOccupantIDs: [NSNumber] = []
                        for strID in strArray {
                            if let uintID = UInt(strID) {
                                if occupantIDs.contains(NSNumber(value: uintID)) == true {
                                    continue
                                } else {
                                    newOccupantIDs.append(NSNumber(value: uintID))
                                    if storage.user(withID: uintID) == nil {
                                        missingOccupantIDs.append(NSNumber(value: uintID))
                                    }
                                }
                            }
                        }
                        
                        if missingOccupantIDs.isEmpty == false {
                            let missingOccupantIDStrArray = missingOccupantIDs.map({ $0.stringValue })
                            QBRequest.users(withIDs: missingOccupantIDStrArray, page: nil, successBlock: { (response, page, newUsers) in
                                self.storage.update(users: newUsers)
                                dialog.occupantIDs = occupantIDs + newOccupantIDs
                                self.storage.update(dialogs:[dialog])
                                self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
                                
                            }, errorBlock: { response in
                                debugPrint("[ChatManager] loadUsers error: \(self.errorMessage(response: response) ?? "")")
                            })
                        } else {
                            dialog.occupantIDs = occupantIDs + newOccupantIDs
                            self.storage.update(dialogs:[dialog])
                            self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
                        }
                    }
                case MessageType.leaveGroupDialog.rawValue:
                    if var occupantIDs = dialog.occupantIDs,
                        occupantIDs.contains(NSNumber(value: message.senderID)) == true {
                        occupantIDs = occupantIDs.filter({ $0.uintValue != message.senderID })
                        dialog.occupantIDs = occupantIDs
                        self.storage.update(dialogs:[dialog])
                        self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
                    }
                default: break
                    
                }
            } else {
                self.storage.update(dialogs:[dialog])
                self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
            }
        } else {
            loadDialog(withID: dialogID, completion: { dialog in
                guard let dialog = dialog else {
                    return
                }
                if let notificationType = message.customParameters["notification_type"] as? String {
                    if dialog.type == .private {
                        return
                    }
                    switch(notificationType) {
                    case MessageType.createGroupDialog.rawValue: dialog.unreadMessagesCount = 1
                    case MessageType.addUsersToGroupDialog.rawValue:break
                    case MessageType.leaveGroupDialog.rawValue:break
                    default: break
                    }
                }
                dialog.lastMessageText = message.text
                dialog.updatedAt = Date()
                self.storage.update(dialogs:[dialog])
                self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
            })
        }
    }
    
    func updateDialog(with dialogID: String, with message: QBChatMessage) {
        if storage.user(withID: message.senderID) != nil {
            prepareDialog(with: dialogID, with: message)
        } else {
            QBRequest.user(withID: message.senderID, successBlock: { response, user in
                self.storage.update(users:[user])
                self.prepareDialog(with: dialogID, with: message)
            }, errorBlock: { response in
                debugPrint("[ChatManager] updateDialog error: \(self.errorMessage(response: response) ?? "")")
            })
        }
    }
    
    //MARK: - Messages
    func messages(withID dialogID: String,
                  extendedRequest extendedParameters: [String: String]? = nil,
                  skip: Int,
                  limit: Int,
                  successCompletion: MessagesCompletion? = nil,
                  errorHandler: MessagesErrorHandler? = nil ) {
        
        let page = QBResponsePage(limit: limit, skip: skip)
        let extendedRequest = extendedParameters?.isEmpty == false ? extendedParameters : parametersForMessages()
        QBRequest.messages(withDialogID: dialogID,
                           extendedRequest: extendedRequest,
                           for: page,
                           successBlock: { response, messages, page in
                            var sortedMessages = messages
                            sortedMessages = Array(sortedMessages.reversed())
                            
                            var cancel = false
                            let numberOfMessages = sortedMessages.count
                            cancel = numberOfMessages < page.limit ? true : false
                            
                            successCompletion?(sortedMessages, cancel)
                            
        }, errorBlock: { response in
            // case where we may have deleted dialog from another device
            if response.status == .notFound || response.status.rawValue == 403 {
                self.storage.deleteDialog(withID: dialogID)
                errorHandler?(ChatManagerConstant.notFound)
                return
            }
            errorHandler?(self.errorMessage(response: response))
        })
    }
    
    
    func send(_ message: QBChatMessage, to dialog: QBChatDialog, completion: QBChatCompletionBlock?) {
        dialog.send(message) { (error) in
            if let error = error {
                completion?(error)
            }
            dialog.updatedAt = Date()
            self.storage.update(dialogs: [dialog])
            self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
            completion?(nil)
        }
    }
    
    func read(_ message: QBChatMessage,
              dialog: QBChatDialog,
              completion: QBChatCompletionBlock?) {
        let currentUser = Profile()
        if currentUser.isFull == false {
            completion?(nil)
            return
        }
        if   message.dialogID != dialog.id  {
            return
        }
        
        if message.deliveredIDs?.contains(NSNumber(value: currentUser.ID)) == false {
            QBChat.instance.mark(asDelivered: message) { error in
            }
        }
        QBChat.instance.read(message) { error in
            debugPrint("[ChatManager] error \(error.debugDescription)")
            if error == nil {
                // updating dialog
                if dialog.unreadMessagesCount > 0 {
                    dialog.unreadMessagesCount = dialog.unreadMessagesCount - 1
                }
                if UIApplication.shared.applicationIconBadgeNumber > 0 {
                    let badgeNumber = UIApplication.shared.applicationIconBadgeNumber
                    UIApplication.shared.applicationIconBadgeNumber = badgeNumber - 1
                }
                self.storage.update(dialogs: [dialog])
                self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
                completion?(nil)
            }
        }
    }
    
    func read(_ messages: [QBChatMessage],
              dialog: QBChatDialog,
              completion: QBChatCompletionBlock?) {
        let currentUser = Profile()
        if currentUser.isFull == false {
            completion?(nil)
            return
        }
        
        let readGroup = DispatchGroup()
        
        for message in messages {
            if   message.dialogID != dialog.id  {
                continue
            }
            
            readGroup.enter()
            if message.deliveredIDs?.contains(NSNumber(value: currentUser.ID)) == false {
                QBChat.instance.mark(asDelivered: message) { error in
                    debugPrint("mark as Delivered")
                }
            }
            QBChat.instance.read(message) { error in
                if error == nil {
                    // updating dialog
                    if dialog.unreadMessagesCount > 0 {
                        dialog.unreadMessagesCount = dialog.unreadMessagesCount - 1
                    }
                    if UIApplication.shared.applicationIconBadgeNumber > 0 {
                        let badgeNumber = UIApplication.shared.applicationIconBadgeNumber
                        UIApplication.shared.applicationIconBadgeNumber = badgeNumber - 1
                    }
                    readGroup.leave()
                }
            }
        }
        readGroup.notify(queue: DispatchQueue.main) {
            self.storage.update(dialogs: [dialog])
            self.delegate?.chatManager(self, didUpdateChatDialog: dialog)
            completion?(nil)
        }
    }
    
    func joinOccupants(withIDs ids: [NSNumber], to chatDialog: QBChatDialog,
                       completion: @escaping (_ response: QBResponse?, _ updatedDialog: QBChatDialog?) -> Void) {
        let pushOccupantsIDs = ids.map({ $0.stringValue })
        chatDialog.pushOccupantsIDs = pushOccupantsIDs
        QBRequest.update(chatDialog, successBlock: { response, updatedDialog in
            
            chatDialog.pushOccupantsIDs = []
            self.storage.update(dialogs:[updatedDialog])
            completion(response, updatedDialog)
        }, errorBlock: { response in
            chatDialog.pushOccupantsIDs = []
            completion(response, nil)
        })
    }
    
    //MARK: - Connect/Disconnect
    func connect(completion: QBChatCompletionBlock? = nil) {
        let currentUser = Profile()
        
        guard currentUser.isFull == true else {
            completion?(NSError(domain: ChatManagerConstant.chatServiceDomain,
                                code: ChatManagerConstant.errorDomaimCode,
                                userInfo: [
                                    NSLocalizedDescriptionKey: "Please enter your login and username."
            ]))
            return
        }
        if QBChat.instance.isConnected == true {
            completion?(nil)
        } else {
            QBSettings.autoReconnectEnabled = true
            QBChat.instance.connect(withUserID: currentUser.ID,
                                    password: currentUser.password,
                                    completion: completion)
        }
    }
    
    func disconnect(completion: QBChatCompletionBlock? = nil) {
        if QBChat.instance.isConnected == true {
            QBChat.instance.disconnect(completionBlock: completion)
        } else {
            completion?(nil)
        }
    }
    
    //MARK: - Internal Methods
    
    //MARK: - Users
    private func updateUsers(completion: @escaping (_ response: QBResponse?) -> Void) {
        let firstPage = QBGeneralResponsePage(currentPage: 1, perPage: 100)
        QBRequest.users(withExtendedRequest: ["order": "desc date last_request_at"],
                        page: firstPage,
                        successBlock: { (response, page, users) in
                            self.storage.update(users:users)
                            completion(response)
        }, errorBlock: { response in
            completion(response)
            debugPrint("[ChatManager] updateUsers error: \(self.errorMessage(response: response) ?? "")")
        })
    }
    
    private func loadUsers(_ usersIDs: [String], completion: @escaping (_ response: QBResponse?) -> Void) {

        var skip: UInt = 1
        var t_request: UsersPage?
        let request: UsersPage? = { usersPage in
            QBRequest.users(withIDs: usersIDs,
                            page: usersPage,
                            successBlock: { (usersResponse, usersResponsePage, users) in
                                
                                self.storage.update(users: users)
                                
                                skip = skip + 1
                                let cancel = users.count < ChatManagerConstant.usersLimit ? true : false
                                if cancel == false {
                                    
                                    t_request?(QBGeneralResponsePage(currentPage: skip, perPage: ChatManagerConstant.usersLimit))
                                } else {
                                    completion(usersResponse)
                                    t_request = nil
                                }
            }, errorBlock: { response in
                completion(response)
                debugPrint("[ChatManager] usersWithIDs error: \(self.errorMessage(response: response) ?? "")")
                t_request = nil
            })
        }
        t_request = request
        request?(QBGeneralResponsePage(currentPage: skip, perPage: ChatManagerConstant.usersLimit))
    }
    
    //MARK: - Dialogs
    private func updateAllDialogs(withPageLimit limit: Int,
                                  extendedRequest: [String: String]? = nil,
                                  iterationBlock: DialogsIterationHandler? = nil,
                                  completion: @escaping (_ response: QBResponse?) -> Void) {
        var usersForUpdate = Set<NSNumber>()
        var t_request: DialogsPage?
        let request: DialogsPage? = { responsePage in
            QBRequest.dialogs(for: responsePage,
                              extendedRequest: extendedRequest,
                              successBlock: { response,
                                dialogs, dialogsUsersIDs, page in

                                for ID in dialogsUsersIDs {
                                    usersForUpdate.insert(ID)
                                }

                                self.storage.update(dialogs:dialogs)

                                page.skip += dialogs.count
                                let cancel = page.totalEntries <= page.skip
                                iterationBlock?(response, dialogs, dialogsUsersIDs, cancel)
                                if cancel == false {
                                    t_request?(page)
                                } else {
     
                                    let usersIDs = usersForUpdate.map({ $0.stringValue })
                                    self.loadUsers(usersIDs) { (response) in
                                        if let error = response?.error?.error {
                                            debugPrint("[ChatManager] loadUsers error: \(error.localizedDescription)")
                                        }
                                    }
                                    completion(response)
                                    t_request = nil
                                }
            }, errorBlock: { response in
                completion(response)
                debugPrint("[ChatManager] updateAllDialogs error: \(self.errorMessage(response: response) ?? "")")
                t_request = nil
            })
        }
        t_request = request
        request?(QBResponsePage(limit: limit))
    }
    
    //MARK: - Messages
    private func parametersForMessages() -> [String : String] {
        let parameters = ["sort_desc": "date_sent", "mark_as_read": "0"]
        return parameters
    }
    
    //Handle Error
    private func errorMessage(response: QBResponse) -> String? {
        var errorMessage : String
        if response.status.rawValue == 502 {
            errorMessage = "SA_STR_BAD_GATEWAY".localized
        } else if response.status.rawValue == 0 {
            errorMessage = "SA_STR_NETWORK_ERROR".localized
        } else {
            guard let qberror = response.error,
                let error = qberror.error else {
                    return nil
            }
            
            errorMessage = error.localizedDescription.replacingOccurrences(of: "(",
                                                                           with: "",
                                                                           options:.caseInsensitive,
                                                                           range: nil)
            errorMessage = errorMessage.replacingOccurrences(of: ")",
                                                             with: "",
                                                             options: .caseInsensitive,
                                                             range: nil)
        }
        return errorMessage
    }
}
