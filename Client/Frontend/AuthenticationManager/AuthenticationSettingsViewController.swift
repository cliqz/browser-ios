/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SwiftKeychainWrapper
import LocalAuthentication

private let logger = Logger.browserLogger

private func presentNavAsFormSheet(_ presented: UINavigationController, presenter: UINavigationController?) {
    presented.modalPresentationStyle = .formSheet
    presenter?.present(presented, animated: true, completion: nil)
}

class TurnPasscodeOnSetting: Setting {
    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil) {
        super.init(title: NSAttributedString.tableRowTitle(AuthenticationStrings.turnOnPasscode),
                   delegate: delegate)
    }

    override func onClick(_ navigationController: UINavigationController?) {
        presentNavAsFormSheet(UINavigationController(rootViewController: SetupPasscodeViewController()),
                              presenter: navigationController)
    }
}

class TurnPasscodeOffSetting: Setting {
    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil) {
        super.init(title: NSAttributedString.tableRowTitle(AuthenticationStrings.turnOffPasscode),
                   delegate: delegate)
    }

    override func onClick(_ navigationController: UINavigationController?) {
        presentNavAsFormSheet(UINavigationController(rootViewController: RemovePasscodeViewController()),
                              presenter: navigationController)
    }
}

class ChangePasscodeSetting: Setting {
    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil, enabled: Bool) {
        let attributedTitle: NSAttributedString = (enabled ?? false) ?
            NSAttributedString.tableRowTitle(AuthenticationStrings.changePasscode) :
            NSAttributedString.disabledTableRowTitle(AuthenticationStrings.changePasscode)

        super.init(title: attributedTitle,
                   delegate: delegate,
                   enabled: enabled)
    }

    override func onClick(_ navigationController: UINavigationController?) {
        presentNavAsFormSheet(UINavigationController(rootViewController: ChangePasscodeViewController()),
                              presenter: navigationController)
    }
}

class RequirePasscodeSetting: Setting {
    fileprivate weak var navigationController: UINavigationController?

    override var accessoryType: UITableViewCellAccessoryType { return .disclosureIndicator }

    override var style: UITableViewCellStyle { return .value1 }

    override var status: NSAttributedString {
        // Only show the interval if we are enabled and have an interval set.
        let authenticationInterval = KeychainWrapper.sharedAppContainerKeychain.authenticationInfo()
        if let interval = authenticationInterval?.requiredPasscodeInterval, enabled {
            return NSAttributedString.disabledTableRowTitle(interval.settingTitle)
        }
        return NSAttributedString(string: "")
    }

    init(settings: SettingsTableViewController, delegate: SettingsDelegate? = nil, enabled: Bool? = nil) {
        self.navigationController = settings.navigationController
        let title = AuthenticationStrings.requirePasscode
        let attributedTitle = (enabled ?? true) ? NSAttributedString.tableRowTitle(title) : NSAttributedString.disabledTableRowTitle(title)
        super.init(title: attributedTitle,
                   delegate: delegate,
                   enabled: enabled)
    }

    override func onClick(_: UINavigationController?) {
        guard let authInfo = KeychainWrapper.sharedAppContainerKeychain.authenticationInfo() else {
            navigateToRequireInterval()
            return
        }

        if authInfo.requiresValidation() {
            AppAuthenticator.presentAuthenticationUsingInfo(authInfo,
            touchIDReason: AuthenticationStrings.requirePasscodeTouchReason,
            success: {
                self.navigateToRequireInterval()
            },
            cancel: nil,
            fallback: {
                AppAuthenticator.presentPasscodeAuthentication(self.navigationController, delegate: self)
            })
        } else {
            self.navigateToRequireInterval()
        }
    }

    fileprivate func navigateToRequireInterval() {
        navigationController?.pushViewController(RequirePasscodeIntervalViewController(), animated: true)
    }
}

extension RequirePasscodeSetting: PasscodeEntryDelegate {
    @objc func passcodeValidationDidSucceed() {
        navigationController?.dismiss(animated: true) {
            self.navigateToRequireInterval()
        }
    }
}

class TouchIDSetting: Setting {
    fileprivate let authInfo: AuthenticationKeychainInfo?

    fileprivate weak var navigationController: UINavigationController?
    fileprivate weak var switchControl: UISwitch?

    fileprivate var touchIDSuccess: (() -> Void)? = nil
    fileprivate var touchIDFallback: (() -> Void)? = nil

    init(
        title: NSAttributedString?,
        navigationController: UINavigationController? = nil,
        delegate: SettingsDelegate? = nil,
        enabled: Bool? = nil,
        touchIDSuccess: (() -> Void)? = nil,
        touchIDFallback: (() -> Void)? = nil)
    {
        self.touchIDSuccess = touchIDSuccess
        self.touchIDFallback = touchIDFallback
        self.navigationController = navigationController
        self.authInfo = KeychainWrapper.sharedAppContainerKeychain.authenticationInfo()
        super.init(title: title, delegate: delegate, enabled: enabled)
    }

    override func onConfigureCell(_ cell: UITableViewCell) {
        super.onConfigureCell(cell)

        // In order for us to recognize a tap gesture without toggling the switch,
        // the switch is wrapped in a UIView which has a tap gesture recognizer. This way
        // we can disable interaction of the switch and still handle tap events.
        let control = UISwitch()
        control.onTintColor = UIConstants.ControlTintColor
        control.isOn = authInfo?.useTouchID ?? false
        control.isUserInteractionEnabled = false
        switchControl = control

        let accessoryContainer = UIView(frame: control.frame)
        accessoryContainer.addSubview(control)

        let gesture = UITapGestureRecognizer(target: self, action: #selector(TouchIDSetting.switchTapped))
        accessoryContainer.addGestureRecognizer(gesture)

        cell.accessoryView = accessoryContainer
    }

    @objc fileprivate func switchTapped() {
        guard let authInfo = authInfo else {
            logger.error("Authentication info should always be present when modifying Touch ID preference.")
            return
        }

        if authInfo.useTouchID {
            AppAuthenticator.presentAuthenticationUsingInfo(
                authInfo,
                touchIDReason: AuthenticationStrings.disableTouchReason,
                success: self.touchIDSuccess,
                cancel: nil,
                fallback: self.touchIDFallback
            )
        } else {
            toggleTouchID(true)
        }
    }

    func toggleTouchID(_ enabled: Bool) {
        authInfo?.useTouchID = enabled
        KeychainWrapper.sharedAppContainerKeychain.setAuthenticationInfo(authInfo)
        switchControl?.setOn(enabled, animated: true)
    }
}

class AuthenticationSettingsViewController: SettingsTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        updateTitleForTouchIDState()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(AuthenticationSettingsViewController.refreshSettings(_:)), name: NSNotification.Name(rawValue: NotificationPasscodeDidRemove), object: nil)
        notificationCenter.addObserver(self, selector: #selector(AuthenticationSettingsViewController.refreshSettings(_:)), name: NSNotification.Name(rawValue: NotificationPasscodeDidCreate), object: nil)
        notificationCenter.addObserver(self, selector: #selector(AuthenticationSettingsViewController.refreshSettings(_:)), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)

        tableView.accessibilityIdentifier = "AuthenticationManager.settingsTableView"
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: NSNotification.Name(rawValue: NotificationPasscodeDidRemove), object: nil)
        notificationCenter.removeObserver(self, name: NSNotification.Name(rawValue: NotificationPasscodeDidCreate), object: nil)
        notificationCenter.removeObserver(self, name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
    }

    override func generateSettings() -> [SettingSection] {
        if let _ = KeychainWrapper.sharedAppContainerKeychain.authenticationInfo() {
            return passcodeEnabledSettings()
        } else {
            return passcodeDisabledSettings()
        }
    }

    fileprivate func updateTitleForTouchIDState() {
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            navigationItem.title = AuthenticationStrings.touchIDPasscodeSetting
        } else {
            navigationItem.title = AuthenticationStrings.passcode
        }
    }

    fileprivate func passcodeEnabledSettings() -> [SettingSection] {
        var settings = [SettingSection]()

        let passcodeSectionTitle = NSAttributedString(string: AuthenticationStrings.passcode)
        let passcodeSection = SettingSection(title: passcodeSectionTitle, children: [
            TurnPasscodeOffSetting(settings: self),
            ChangePasscodeSetting(settings: self, delegate: nil, enabled: true)
        ])

        var requirePasscodeSectionChildren: [Setting] = [RequirePasscodeSetting(settings: self)]
        let localAuthContext = LAContext()
        if localAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            requirePasscodeSectionChildren.append(
                TouchIDSetting(
                    title: NSAttributedString.tableRowTitle(
                        NSLocalizedString("Use Touch ID", tableName:  "AuthenticationManager", comment: "List section title for when to use Touch ID")
                    ),
                    navigationController: self.navigationController,
                    delegate: nil,
                    enabled: true,
                    touchIDSuccess: { [unowned self] in
                        self.touchIDAuthenticationSucceeded()
                    },
                    touchIDFallback: { [unowned self] in
                        self.fallbackOnTouchIDFailure()
                    }
                )
            )
        }

        let requirePasscodeSection = SettingSection(title: nil, children: requirePasscodeSectionChildren)
        settings += [
            passcodeSection,
            requirePasscodeSection,
        ]

        return settings
    }

    fileprivate func passcodeDisabledSettings() -> [SettingSection] {
        var settings = [SettingSection]()

        let passcodeSectionTitle = NSAttributedString(string: AuthenticationStrings.passcode)
        let passcodeSection = SettingSection(title: passcodeSectionTitle, children: [
            TurnPasscodeOnSetting(settings: self),
            ChangePasscodeSetting(settings: self, delegate: nil, enabled: false)
        ])

        let requirePasscodeSection = SettingSection(title: nil, children: [
            RequirePasscodeSetting(settings: self, delegate: nil, enabled: false),
        ])

        settings += [
            passcodeSection,
            requirePasscodeSection,
        ]

        return settings
    }
}

extension AuthenticationSettingsViewController {
    func refreshSettings(_ notification: Notification) {
        updateTitleForTouchIDState()
        settings = generateSettings()
        tableView.reloadData()
    }
}

extension AuthenticationSettingsViewController: PasscodeEntryDelegate {
    fileprivate func getTouchIDSetting() -> TouchIDSetting? {
        guard settings.count >= 2 && settings[1].count >= 2 else {
            return nil
        }
        return settings[1][1] as? TouchIDSetting
    }

    func touchIDAuthenticationSucceeded() {
        getTouchIDSetting()?.toggleTouchID(false)
    }

    func fallbackOnTouchIDFailure() {
        AppAuthenticator.presentPasscodeAuthentication(self.navigationController, delegate: self)
    }

    @objc func passcodeValidationDidSucceed() {
        getTouchIDSetting()?.toggleTouchID(false)
        navigationController?.dismiss(animated: true, completion: nil)
    }
}
