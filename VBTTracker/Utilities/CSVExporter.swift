//
//  CSVExporter.swift
//  VBTTracker
//
//  Utility for exporting training session data to CSV format
//

import Foundation

struct CSVExporter {

    /// Generates a CSV string from training session data
    /// - Parameter sessionData: The training session to export
    /// - Returns: CSV-formatted string
    static func generateCSV(from sessionData: TrainingSessionData) -> String {
        var csv = ""

        // Header: Metadata section
        csv += "VBT Training Session Export\n"
        csv += "Date,\(formatDate(sessionData.date))\n"
        csv += "Target Zone (m/s),\(formatRange(sessionData.targetZone))\n"
        csv += "Velocity Loss Threshold (%),\(formatPercentage(sessionData.velocityLossThreshold))\n"
        csv += "Total Reps,\(sessionData.totalReps)\n"
        csv += "Reps in Target,\(sessionData.repsInTarget)\n"
        csv += "Velocity Loss (%),\(formatPercentage(sessionData.velocityLoss))\n"
        csv += "\n"

        // Rep-by-rep data header
        csv += "Rep Number,Mean Propulsive Velocity (m/s),Peak Propulsive Velocity (m/s),Velocity Loss from First (%),In Target Zone\n"

        // Rep-by-rep data
        for (index, rep) in sessionData.reps.enumerated() {
            let repNumber = index + 1
            let mpv = formatVelocity(rep.meanVelocity)
            let ppv = formatVelocity(rep.peakVelocity)
            let vlFromFirst = formatPercentage(rep.velocityLossFromFirst)
            let inTarget = sessionData.targetZone.contains(rep.meanVelocity) ? "Yes" : "No"

            csv += "\(repNumber),\(mpv),\(ppv),\(vlFromFirst),\(inTarget)\n"
        }

        // Summary statistics
        csv += "\n"
        csv += "Summary Statistics\n"

        if !sessionData.reps.isEmpty {
            let mpvValues = sessionData.reps.map { $0.meanVelocity }
            let ppvValues = sessionData.reps.map { $0.peakVelocity }

            csv += "Average MPV (m/s),\(formatVelocity(average(mpvValues)))\n"
            csv += "Average PPV (m/s),\(formatVelocity(average(ppvValues)))\n"
            csv += "Max MPV (m/s),\(formatVelocity(mpvValues.max() ?? 0))\n"
            csv += "Max PPV (m/s),\(formatVelocity(ppvValues.max() ?? 0))\n"
            csv += "Min MPV (m/s),\(formatVelocity(mpvValues.min() ?? 0))\n"
            csv += "Min PPV (m/s),\(formatVelocity(ppvValues.min() ?? 0))\n"
        }

        return csv
    }

    /// Generates a filename for the CSV export
    /// - Parameter date: Session date
    /// - Returns: Filename string
    static func generateFilename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "VBT_Session_\(formatter.string(from: date)).csv"
    }

    /// Writes CSV data to a temporary file and returns the URL
    /// - Parameters:
    ///   - csvString: The CSV content
    ///   - filename: The desired filename
    /// - Returns: URL to the temporary file
    static func writeToTemporaryFile(csvString: String, filename: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)

        try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Private Formatting Helpers

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func formatRange(_ range: ClosedRange<Double>) -> String {
        return "\(formatVelocity(range.lowerBound))-\(formatVelocity(range.upperBound))"
    }

    private static func formatVelocity(_ value: Double) -> String {
        return String(format: "%.3f", value)
    }

    private static func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
