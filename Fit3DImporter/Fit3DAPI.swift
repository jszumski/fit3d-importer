//
//  Fit3DAPI.swift
//  Fit3DImporter
//
//  Created by John Szumski on 6/2/18.
//  Copyright © 2018 John Szumski. All rights reserved.
//

import Foundation

struct ScanRecord: Decodable {
    let recordDate: Date
    let id: Int
    let scanMeasurement: ScanMeasurement
    let wellnessMetrics: WellnessMetrics

    struct ScanMeasurement: Decodable {
        let waistNaturalGirth: Double
    }

    struct WellnessMetrics: Decodable {
        let bmi: Double
        let bfp: Double
        let height: Double
        let leanMass: Double
        let weight: Double
    }
}

class Fit3DAPI {
    class func fetchRecords(token: String, completion: @escaping (Bool, [ScanRecord], String) -> Void) {
        var request = URLRequest(url: URL(string: "https://api.fit3d.com/v1/records")!)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completion(false, [], error.localizedDescription)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode != 401 else {

                DispatchQueue.main.async {
                    completion(false, [], "Token expired")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(false, [], "Scans unavailable")
                }
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(DateFormatter.fit3d)

            if let records = try? decoder.decode([ScanRecord].self, from: data) {
                DispatchQueue.main.async {
                    completion(true, records, "\(records.count) available")
                }

            } else {
                DispatchQueue.main.async {
                    completion(false, [], "Scan format not readable")
                }
            }

        }).resume()
    }
}

extension DateFormatter {
    static let fit3d: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "UTC")

        return formatter
    }()
}
