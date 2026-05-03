import Foundation
import UserNotifications

enum SpendLimitNotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyExceededLimits(
        providers: [Provider],
        todayCostsUSD: [String: Double],
        now: Date = Date()
    ) {
        for provider in providers {
            guard let limit = provider.daily_spend_limit_usd,
                  limit > 0,
                  let cost = todayCostsUSD[provider.name],
                  cost >= limit else {
                continue
            }

            let key = notificationKey(provider: provider.name, day: dayString(now))
            guard !UserDefaults.standard.bool(forKey: key) else { continue }
            UserDefaults.standard.set(true, forKey: key)
            sendNotification(provider: provider.name, cost: cost, limit: limit)
        }
    }

    static func notificationKey(provider: String, day: String) -> String {
        "spend-limit-notified.\(day).\(provider)"
    }

    private static func sendNotification(provider: String, cost: Double, limit: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Provider daily limit reached"
        content.body = "\(provider): \(formatUSD(cost)) used today. Limit: \(formatUSD(limit))."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "provider-spend-limit-\(provider)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func formatUSD(_ amount: Double) -> String {
        if amount < 1 {
            return String(format: "$%.4f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
