//
//  ViewController.swift
//  Fit3DImporter
//
//  Created by John Szumski on 6/1/18.
//  Copyright © 2018 John Szumski. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet private weak var resultsTextView: UITextView?
    private var loginToken: String?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        appendLog(message: "Ready for Login")
    }

    // MARK: - UI response
    @IBAction
    private func loginTapped() {
        appendLog(message: "Attemping login... ")

        let authVC = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "authVC") as! AuthViewController
        authVC.completionBlock = { [weak self] success, token, message in
            self?.loginToken = token

            self?.appendLog(result: "\(success ? "✓" : "✗") \(message)")
            self?.appendLog(message: "Ready for Import")

            authVC.dismiss(animated: true, completion: nil)
        }

        present(UINavigationController(rootViewController: authVC), animated: true, completion: nil)
    }

    @IBAction
    private func importTapped() {
        appendLog(message: "Downloading scans... ")

        guard let token = loginToken else {
            self.appendLog(result: "✗ No token found")
            return
        }

        Fit3DAPI.fetchRecords(token: token) { [weak self] success, records, message in
            self?.appendLog(result: "\(success ? "✓" : "✗") \(message)")

            if success {
                let importer = DataImporter(scans: records)
                importer.completionBlock = {
                    DispatchQueue.main.async {
                        self?.appendLog(message: "Import finished")
                    }
                }

                importer.start(messageHandler: { [weak self] message in
                    DispatchQueue.main.async {
                        self?.appendLog(message: message)
                    }
                }, resultHandler: { [weak self] result in
                    DispatchQueue.main.async {
                        self?.appendLog(result: result)
                    }
                })
            }
        }
    }

    // MARK: - Helpers
    private func appendLog(message: String) {
        guard let textView = resultsTextView else { return }

        var text = textView.text ?? ""
        text.append("\(message)\n")

        textView.text = text
    }

    private func appendLog(result: String) {
        guard let textView = resultsTextView else { return }

        var text = textView.text ?? ""
        text.append("\t\(result)\n")

        textView.text = text
    }
}

