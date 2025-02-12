/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// This Activity Item Provider subclass does two things that are non-standard behaviour:
///
/// * We return NSNull if the calling activity is not supposed to see the title. For example the Copy action, which should only paste the URL. We also include Message and Mail to have parity with what Safari exposes.
/// * We set the subject of the item to the title, this means it will correctly be used when sharing to for example Mail. Again parity with Safari.
///
/// Note that not all applications use the Subject. For example OmniFocus ignores it, so we need to do both.

class TitleActivityItemProvider: UIActivityItemProvider {
    static let activityTypesToIgnore = [UIActivityType.copyToPasteboard, UIActivityType.message, UIActivityType.mail, UIActivityType.init("com.apple.CloudDocsUI.AddToiCloudDrive")]
    var extraActivityTypesToIgnore : [UIActivityType]
    
    init(title: String, activitiesToIgnore: [UIActivityType] = [UIActivityType]()) {
        extraActivityTypesToIgnore = activitiesToIgnore
        super.init(placeholderItem: title)
    }

    override var item : Any {
        if let activityType = activityType {
            if TitleActivityItemProvider.activityTypesToIgnore.contains(activityType) {
                return NSNull()
            }
            if extraActivityTypesToIgnore.contains(activityType) {
                return NSNull()
            }
        }
        return placeholderItem! as AnyObject
    }

    override func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivityType?) -> String {
        return placeholderItem as! String
    }
}
