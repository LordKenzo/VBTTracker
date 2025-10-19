//
//  SliderSettingRow.swift
//  VBTTracker
//
//  Created by Lorenzo Franceschini on 19/10/25.
//


//
//  SettingRow.swift
//  VBTTracker
//
//  Component riutilizzabile per row di impostazioni
//

import SwiftUI

// MARK: - Setting Row con Slider
struct SliderSettingRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let description: String?
    
    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 0.1,
        unit: String = "",
        description: String? = nil
    ) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.description = description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.2f")\(unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            Slider(value: value, in: range, step: step)
                .tint(.blue)
            
            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Setting Row con Toggle
struct ToggleSettingRow: View {
    let title: String
    let isOn: Binding<Bool>
    let icon: String?
    let description: String?
    
    init(
        title: String,
        isOn: Binding<Bool>,
        icon: String? = nil,
        description: String? = nil
    ) {
        self.title = title
        self.isOn = isOn
        self.icon = icon
        self.description = description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                HStack(spacing: 12) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                    }
                    Text(title)
                }
            }
            
            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Setting Row con Picker
struct PickerSettingRow<T: Hashable>: View {
    let title: String
    let selection: Binding<T>
    let options: [(T, String)]
    let icon: String?
    
    init(
        title: String,
        selection: Binding<T>,
        options: [(T, String)],
        icon: String? = nil
    ) {
        self.title = title
        self.selection = selection
        self.options = options
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }
            
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Setting Row con Navigation Link
struct NavigationSettingRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let badge: String?
    
    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = .blue,
        badge: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.badge = badge
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body)
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .cornerRadius(6)
                    }
                }
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Setting Row con Info/Status
struct InfoSettingRow: View {
    let title: String
    let value: String
    let icon: String?
    let status: StatusType?
    
    enum StatusType {
        case success
        case warning
        case error
        
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    init(
        title: String,
        value: String,
        icon: String? = nil,
        status: StatusType? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.status = status
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if let status = status {
                    Image(systemName: status.icon)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview("Slider Row") {
    List {
        SliderSettingRow(
            title: "Tempo tra Rep",
            value: .constant(0.8),
            range: 0.5...2.0,
            step: 0.1,
            unit: "s",
            description: "✅ Bilanciato (consigliato)"
        )
    }
}

#Preview("Toggle Row") {
    List {
        ToggleSettingRow(
            title: "Feedback Vocale",
            isOn: .constant(true),
            icon: "speaker.wave.2.fill",
            description: "Annuncia rep e zone durante l'allenamento"
        )
    }
}

#Preview("Navigation Row") {
    NavigationStack {
        List {
            NavigationLink(destination: Text("Dettaglio")) {
                NavigationSettingRow(
                    title: "Rilevamento Rep",
                    subtitle: "Parametri algoritmo",
                    icon: "waveform.path.ecg",
                    iconColor: .purple,
                    badge: "Avanzato"
                )
            }
        }
    }
}