//
//  DataImporter.swift
//  Fit3DImporter
//
//  Created by John Szumski on 6/2/18.
//  Copyright © 2018 John Szumski. All rights reserved.
//

import Foundation
import HealthKit

class DataImporter {
    let healthStore = HKHealthStore()
    let scans: [ScanRecord]
    let types: Set = [HKObjectType.quantityType(forIdentifier: .bodyMass)!,
                      HKObjectType.quantityType(forIdentifier: .leanBodyMass)!,
                      HKObjectType.quantityType(forIdentifier: .bodyMassIndex)!,
                      HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
                      HKObjectType.quantityType(forIdentifier: .waistCircumference)!,
                      HKObjectType.quantityType(forIdentifier: .height)!]

    var completionBlock: (() -> Void)?


    // MARK: - Lifecycle
    init(scans: [ScanRecord]) {
        self.scans = scans
    }

    func start(messageHandler: @escaping (String) -> Void, resultHandler: @escaping (String) -> Void) {
        let promptWillAppear = count(forAuthStatus: .notDetermined) > 0

        if promptWillAppear {
            messageHandler("Requesting permission...")
        }

        // request write access to import new values, request read access to prevent duplicates
        healthStore.requestAuthorization(toShare: types, read: types, completion: { finished, error in
            if finished {
                // if a prompt appeared, log what permissions the user chose
                if promptWillAppear {
                    let countAuthed = self.count(forAuthStatus: HKAuthorizationStatus.sharingAuthorized)
                    let countDenied = self.count(forAuthStatus: HKAuthorizationStatus.sharingAuthorized)

                    if countAuthed == self.types.count {
                        resultHandler("✓ Granted")

                    } else if countDenied == self.types.count {
                        resultHandler("✗ Denied")

                    } else {
                        resultHandler("- \(countAuthed) of \(self.types.count) granted")
                    }
                }


                // attempt to import what we can
                let queue = OperationQueue()
                queue.name = "queue.importScan"
                queue.maxConcurrentOperationCount = 1

                let scanOperations = self.scans.map({ ImportScanOperation(healthStore: self.healthStore, scan: $0, messageHandler: messageHandler, resultHandler: resultHandler) })

                queue.addOperations(scanOperations, waitUntilFinished: false)
                queue.addOperation {
                    self.completionBlock?()
                }

            } else {
                resultHandler("✗ Canceled")
            }
        })
    }


    // MARK: - Helpers
    private func count(forAuthStatus status: HKAuthorizationStatus) -> Int {
        return types.map({ healthStore.authorizationStatus(for: $0) }).filter({ $0 == status }).count
    }
}

// MARK: - Operations

class ImportScanOperation: AsyncOperation {
    let healthStore: HKHealthStore
    let scan: ScanRecord
    let messageHandler: (String) -> Void
    let resultHandler: (String) -> Void

    let queue: OperationQueue


    // MARK: - Lifecycle
    init(healthStore: HKHealthStore, scan: ScanRecord, messageHandler: @escaping (String) -> Void, resultHandler: @escaping (String) -> Void) {
        self.healthStore = healthStore
        self.scan = scan
        self.messageHandler = messageHandler
        self.resultHandler = resultHandler

        // create a queue that will save each sample serially
        self.queue = OperationQueue()
        self.queue.name = "queue.importScan.\(scan.id)"
        self.queue.maxConcurrentOperationCount = 1

        super.init()
    }

    override func start() {
        super.start()

        messageHandler("Importing scan from \(DateFormatter.full.string(from: scan.recordDate))...")

        // save each value individually
        // while we could save them in one go, if we didn't have permission for any type then all of them would not be saved
        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                           type: .height, name: "Height", value: scan.wellnessMetrics.height, unit: .inch(), date: scan.recordDate))

        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                           type: .bodyMass, name: "Weight", value: scan.wellnessMetrics.weight, unit: .pound(), date: scan.recordDate))

        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                             type: .leanBodyMass, name: "Weight (lean)", value: scan.wellnessMetrics.leanMass, unit: .pound(), date: scan.recordDate))

        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                        type: .bodyMassIndex, name: "BMI", value: scan.wellnessMetrics.bmi, unit: .count(), date: scan.recordDate))

        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                            type: .bodyFatPercentage, name: "Body Fat", value: scan.wellnessMetrics.bfp, unit: .percent(), date: scan.recordDate))

        queue.addOperation(ImportSampleOperation(healthStore: healthStore, scan: scan, updateHandler: resultHandler,
                                          type: .waistCircumference, name: "Waist", value: scan.scanMeasurement.waistNaturalGirth, unit: .inch(), date: scan.recordDate))

        // clean up
        queue.addOperation {
            self.state = .finished
        }
    }
}

// MARK: -

class AsyncSampleOperation: AsyncOperation {
    let healthStore: HKHealthStore
    let scan: ScanRecord
    let updateHandler: (String) -> Void

    let type: HKQuantityTypeIdentifier
    let humanReadableName: String
    let value: Double
    let unit: HKUnit
    let date: Date

    // MARK: - Lifecycle
    init(healthStore: HKHealthStore, scan: ScanRecord, updateHandler: @escaping (String) -> Void, type: HKQuantityTypeIdentifier, name: String, value: Double, unit: HKUnit, date: Date) {
        self.healthStore = healthStore
        self.scan = scan
        self.updateHandler = updateHandler

        self.type = type
        self.humanReadableName = name
        self.value = value
        self.unit = unit
        self.date = date
    }
}

class ImportSampleOperation: AsyncSampleOperation {
    let queue: OperationQueue

    // MARK: - Lifecycle
    override init(healthStore: HKHealthStore, scan: ScanRecord, updateHandler: @escaping (String) -> Void, type: HKQuantityTypeIdentifier, name: String, value: Double, unit: HKUnit, date: Date) {
        // create a queue that will serially execute the query and (if needed) save the sample
        self.queue = OperationQueue()
        self.queue.name = "queue.importScan.\(scan.id).\(type.rawValue)"
        self.queue.maxConcurrentOperationCount = 1

        super.init(healthStore: healthStore, scan: scan, updateHandler: updateHandler, type: type, name: name, value: value, unit: unit, date: date)
    }

    override func start() {
        super.start()

        if self.isCancelled { return }

        let readOp = ReadSampleOperation(healthStore: healthStore, scan: scan, updateHandler: updateHandler, type: type, name: humanReadableName, value: value, unit: unit, date: date)
        let writeOp = SaveSampleOperation(healthStore: healthStore, scan: scan, updateHandler: updateHandler, type: type, name: humanReadableName, value: value, unit: unit, date: date)

        // determine if this value already exists in the store
        readOp.completionBlock = {
            if readOp.foundMatch {
                writeOp.cancel()

                self.updateHandler("- \(self.humanReadableName): Already exists")
            }
        }
        queue.addOperation(readOp)

        // save the value to the store
        // note that this operation may be canceled by the read op
        queue.addOperation(writeOp)

        // clean up
        queue.addOperation {
            self.state = .finished
        }
    }
}

class ReadSampleOperation: AsyncSampleOperation {
    var foundMatch = false

    override func start() {
        super.start()

        if self.isCancelled { return }

        let mostRecentPredicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let quantityType = HKObjectType.quantityType(forIdentifier: type)!

        let query = HKSampleQuery(sampleType: quantityType, predicate: mostRecentPredicate, limit: 10, sortDescriptors: nil) { (query, samples, error) in
            defer { self.state = .finished }

            guard let match = samples?.first as? HKQuantitySample else { return }

            // determine if this value and date already exist
            self.foundMatch = (match.startDate == self.date &&
                               match.quantity.doubleValue(for: self.unit) == self.value)
        }

        HKHealthStore().execute(query)
    }
}

class SaveSampleOperation: AsyncSampleOperation {
    override func start() {
        super.start()

        if self.isCancelled { return }

        let sample = HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: type)!,
                                      quantity: HKQuantity.init(unit: unit, doubleValue: value),
                                      start: date,
                                      end: date)

        self.healthStore.save(sample) { success, error in
            defer { self.state = .finished }

            // if successful, print the saved value
            if success {
                let formattedValue = NumberFormatter.decimal.string(from: NSNumber(value: self.value)) ?? "?"
                let formattedUnit = self.displayString(forValue: self.value, inUnit: self.unit)

                self.updateHandler("✓ \(self.humanReadableName): \(formattedValue)\(formattedUnit)")

            // if unsuccessful, give the user an explanation
            } else {
                guard let error = error as? HKError else {
                    self.updateHandler("✗ \(self.humanReadableName): Unknown error)")
                    return
                }

                if error.code == HKError.errorAuthorizationDenied {
                    self.updateHandler("✗ \(self.humanReadableName): Permission denied")

                } else if error.code == HKError.errorInvalidArgument {
                    self.updateHandler("✗ \(self.humanReadableName): Value already exists")

                } else {
                    self.updateHandler("✗ \(self.humanReadableName): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers
    private func displayString(forValue value: Double, inUnit unit: HKUnit) -> String {
        // special case: BMI has no unit
        if unit == HKUnit.count() {
            return ""
        }

        if unit == HKUnit.pound() {
            return MassFormatter.person.unitString(fromValue: value, unit: HKUnit.massFormatterUnit(from: unit))
        }

        if unit == HKUnit.inch() {
            return LengthFormatter.person.unitString(fromValue: value, unit: HKUnit.lengthFormatterUnit(from: unit))
        }

        if unit == HKUnit.percent() {
            return "%"
        }

        return ""
    }
}

// MARK: - Formatters

extension DateFormatter {
    static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy h:mm a"
        formatter.timeZone = TimeZone(identifier: "ET")

        return formatter
    }()
}

extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2

        return formatter
    }()
}

extension MassFormatter {
    static let person: MassFormatter = {
        let formatter = MassFormatter()
        formatter.isForPersonMassUse = true

        return formatter
    }()
}

extension LengthFormatter {
    static let person: LengthFormatter = {
        let formatter = LengthFormatter()
        formatter.isForPersonHeightUse = true

        return formatter
    }()
}
