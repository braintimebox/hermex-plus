import Foundation
import HealthKit

// MARK: - Metric descriptor (declarative query config)

private struct Metric {
    let identifier: HKQuantityTypeIdentifier
    let label: String          // ключ в markdown
    let query: QueryType
    let unit: HKUnit
}

private enum QueryType {
    case sum        // HKStatisticsQuery.cumulativeSum
    case latest     // HKSampleQuery, последний сэмпл
}

// MARK: - Provider

@MainActor
final class AppleHealthProvider: ObservableObject {
    static let shared = AppleHealthProvider()

    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastSyncError: String?

    // ── Full metric catalogue ──────────────────────────────────────────
    // Всё, что Apple Health может отдать. Группировка: Activity → Body → Heart → Vitals → Sleep → Nutrition → Environment.

    private static let allMetrics: [Metric] = [
        // Activity (daily cumulative)
        Metric(identifier: .stepCount, label: "steps", query: .sum, unit: .count()),
        Metric(identifier: .activeEnergyBurned, label: "active_energy", query: .sum, unit: .kilocalorie()),
        Metric(identifier: .appleExerciseTime, label: "exercise_minutes", query: .sum, unit: .minute()),
        Metric(identifier: .appleStandTime, label: "stand_minutes", query: .sum, unit: .minute()),
        Metric(identifier: .flightsClimbed, label: "flights_climbed", query: .sum, unit: .count()),
        Metric(identifier: .distanceWalkingRunning, label: "distance_walk_run_km", query: .sum,
               unit: HKUnit.meterUnit(with: .kilo)),
        Metric(identifier: .distanceCycling, label: "distance_cycling_km", query: .sum,
               unit: HKUnit.meterUnit(with: .kilo)),
        Metric(identifier: .distanceSwimming, label: "distance_swimming_m", query: .sum, unit: .meter()),
        Metric(identifier: .swimmingStrokeCount, label: "swim_strokes", query: .sum, unit: .count()),

        // Body
        Metric(identifier: .bodyMass, label: "weight_kg", query: .latest,
               unit: .gramUnit(with: .kilo)),
        Metric(identifier: .bodyMassIndex, label: "bmi", query: .latest, unit: .count()),
        Metric(identifier: .bodyFatPercentage, label: "body_fat_pct", query: .latest,
               unit: .decimalPercent()),
        Metric(identifier: .leanBodyMass, label: "lean_body_mass_kg", query: .latest,
               unit: .gramUnit(with: .kilo)),
        Metric(identifier: .waistCircumference, label: "waist_cm", query: .latest,
               unit: .meterUnit(with: .centi)),
        Metric(identifier: .height, label: "height_cm", query: .latest,
               unit: .meterUnit(with: .centi)),

        // Heart
        Metric(identifier: .restingHeartRate, label: "heart_rate_resting", query: .latest,
               unit: hUnit("count/min")),
        Metric(identifier: .walkingHeartRateAverage, label: "heart_rate_walking", query: .latest,
               unit: hUnit("count/min")),
        Metric(identifier: .heartRateVariabilitySDNN, label: "hrv_rmssd", query: .latest,
               unit: hUnit("ms")),
        Metric(identifier: .heartRateRecoveryOneMinute, label: "heart_rate_recovery_1min", query: .latest,
               unit: hUnit("count/min")),

        // Vitals
        Metric(identifier: .oxygenSaturation, label: "spo2_pct", query: .latest,
               unit: hDecimalPercent()),
        Metric(identifier: .respiratoryRate, label: "respiratory_rate", query: .latest,
               unit: hUnit("count/min")),
        Metric(identifier: .vo2Max, label: "vo2max", query: .latest,
               unit: hUnit("mL/kg*min")),
        Metric(identifier: .bloodGlucose, label: "blood_glucose_mmol", query: .latest,
               unit: hUnit("mmol/L")),
        Metric(identifier: .bloodPressureSystolic, label: "blood_pressure_systolic", query: .latest,
               unit: hUnit("mmHg")),
        Metric(identifier: .bloodPressureDiastolic, label: "blood_pressure_diastolic", query: .latest,
               unit: hUnit("mmHg")),
        Metric(identifier: .bodyTemperature, label: "body_temperature_c", query: .latest,
               unit: .degreeCelsius()),

        // Nutrition (daily sums)
        Metric(identifier: .dietaryEnergyConsumed, label: "dietary_energy_kcal", query: .sum,
               unit: .kilocalorie()),
        Metric(identifier: .dietaryProtein, label: "dietary_protein_g", query: .sum, unit: .gram()),
        Metric(identifier: .dietaryCarbohydrates, label: "dietary_carbs_g", query: .sum, unit: .gram()),
        Metric(identifier: .dietaryFatTotal, label: "dietary_fat_g", query: .sum, unit: .gram()),
        Metric(identifier: .dietaryFiber, label: "dietary_fiber_g", query: .sum, unit: .gram()),
        Metric(identifier: .dietaryWater, label: "dietary_water_ml", query: .sum,
               unit: .literUnit(with: .milli)),

        // Environment / other
        Metric(identifier: .timeInDaylight, label: "time_in_daylight_min", query: .sum, unit: .minute()),
        Metric(identifier: .headphoneAudioExposure, label: "headphone_audio_db", query: .latest,
               unit: hUnit("dBASPL")),
        Metric(identifier: .environmentalAudioExposure, label: "env_audio_db", query: .latest,
               unit: hUnit("dBASPL")),
        Metric(identifier: .uvExposure, label: "uv_index", query: .latest, unit: .count()),
        Metric(identifier: .appleSleepingWristTemperature, label: "wrist_temperature_c", query: .latest,
               unit: .degreeCelsius()),
    ]

    private static var readTypes: Set<HKObjectType> {
        var types = Set(allMetrics.map { HKQuantityType($0.identifier) })
        types.insert(HKCategoryType(.sleepAnalysis))
        return types
    }

    private init() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        Task { await refreshAuthState() }
    }

    // MARK: - Auth

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        await refreshAuthState()
    }

    private func refreshAuthState() async {
        guard let status = try? await store.statusForAuthorizationRequest(
            toShare: [], read: Self.readTypes
        ) else {
            isAuthorized = false
            return
        }
        isAuthorized = status == .unnecessary
    }

    // MARK: - Sync

    func syncToday() async throws -> String? {
        guard isAuthorized else { throw HealthKitError.notAuthorized }
        isSyncing = true
        defer { isSyncing = false }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let pred = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictEndDate)

        var lines: [String] = ["[TRACKER]",
                               "## \(Self.dateStr(now))",
                               "- source: Apple Health (Hermes Plus)"]

        // Query all quantity metrics
        for metric in Self.allMetrics {
            let value: Double?
            switch metric.query {
            case .sum:    value = try await dailySum(id: metric.identifier, unit: metric.unit, predicate: pred)
            case .latest: value = try await latestQuantity(id: metric.identifier, unit: metric.unit, predicate: pred)
            }
            guard let v = value else { continue }
            lines.append("- \(metric.label): \(Self.fmt(v))")
        }

        // Sleep (category)
        if let sh = try await sleepHours(predicate: pred) {
            lines.append("- sleep_hours: \(Self.fmt(sh))")
        }

        lastSyncDate = now
        lastSyncError = nil
        return lines.joined(separator: "\n")
    }

    // MARK: - Query primitives

    private func dailySum(id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        let type = HKQuantityType(id)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                       options: .cumulativeSum) { _, stats, err in
                if let err { cont.resume(throwing: err); return }
                guard let s = stats?.sumQuantity() else { cont.resume(returning: nil); return }
                cont.resume(returning: s.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func latestQuantity(id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        let type = HKQuantityType(id)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                   sortDescriptors: [sort]) { _, samples, err in
                if let err { cont.resume(throwing: err); return }
                guard let s = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: s.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func sleepHours(predicate: NSPredicate) async throws -> Double? {
        let type = HKCategoryType(.sleepAnalysis)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                   sortDescriptors: [sort]) { _, samples, err in
                if let err { cont.resume(throwing: err); return }
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }
                let sleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.inBed.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let total = samples
                    .filter { sleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                let h = total / 3600.0
                cont.resume(returning: h > 0 ? h : nil)
            }
            store.execute(q)
        }
    }

    // MARK: - Helpers

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func dateStr(_ d: Date) -> String { dateFmt.string(from: d) }
    static func fmt(_ v: Double) -> String { v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v) }

    private static func hUnit(_ s: String) -> HKUnit { HKUnit(from: s) }
    private static func hDecimalPercent() -> HKUnit {
        // decimal fraction 0.0–1.0. We store as %, so query as raw decimal
        HKUnit(from: "")
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case unavailable, notAuthorized
    var errorDescription: String? {
        switch self {
        case .unavailable:  "HealthKit is not available on this device"
        case .notAuthorized: "Health data access not authorized. Enable in Settings → Health → Hermex."
        }
    }
}
