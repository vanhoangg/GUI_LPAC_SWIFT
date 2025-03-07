//
//  Utils.swift
//  TestLPACKit
//
//  Created by hoang.dinh on 3/7/25.
//

import UIKit
extension UIViewController {
     func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}
