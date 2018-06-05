//
//  AuthViewController.swift
//  Fit3DImporter
//
//  Created by John Szumski on 6/1/18.
//  Copyright © 2018 John Szumski. All rights reserved.
//

import Foundation
import WebKit

class AuthViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var completionBlock: ((Bool, String?, String) -> Void)?
    @IBOutlet private weak var webView: WKWebView?

    let dashboardURL = URL(string: "https://dashboard.fit3d.com")!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Login"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))

        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        webView?.load(URLRequest(url: dashboardURL))
    }

    // MARK: - UI response
    @objc func cancelTapped() {
        completionBlock?(false, nil, "Canceled")
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // a page was loaded, so let's see if we can pluck out a token
        webView.evaluateJavaScript("localStorage.getItem(\"token\")") { [weak self] (value, error) in
            guard let strongSelf = self else { return }

            // if we have a token, then we're done
            if let token = value as? String {
                strongSelf.completionBlock?(true, token, "Token found")
                print("Token: \(token)")

            // if no token but we aren't on the dashboard, then we just loaded the login form and need to keep waiting
            } else if webView.url != strongSelf.dashboardURL {
                return

            // if no token and we're on the dashboard, something weird happened and we need to bail
            } else {
                strongSelf.completionBlock?(false, nil, "No token found")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // something went wrong, we need to bail
        completionBlock?(false, nil, error.localizedDescription)
    }
}
