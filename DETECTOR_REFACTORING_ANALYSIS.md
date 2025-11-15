# Comprehensive Analysis: VBTRepDetector vs DistanceBasedRepDetector

## EXECUTIVE SUMMARY

Both detector classes follow the same fundamental state machine pattern for rep detection but are specialized for different sensor input types:
- **VBTRepDetector**: Accelerometer-based (WitMotion IMU)
- **DistanceBasedRepDetector**: Direct distance measurement (Arduino VL53L0X laser)

Despite differences in input data and some implementation details, they share ~70% of their architectural patterns. The refactoring should extract a shared base protocol with default implementations, while keeping sensor-specific logic isolated.

---

## 1. COMMON PROPERTIES AND CONFIGURATION

### 1.1 IDENTICAL PROPERTIES

#### Sample Rate
```swift
// BOTH
var sampleRateHz: Double = 50.0
```
**Status**: Identical
**Shareable**: YES - via protocol with default 50.0

#### Look-Ahead Samples
```swift
// VBTRepDetector
var lookAheadSamples: Int = 10

// DistanceBasedRepDetector
var lookAheadSamples: Int {
    let profile = SettingsManager.shared.detectionProfile
    switch profile {
    case .maxStrength:   return 10
    case .strength:      return 7
    case .strengthSpeed: return 5
    case .speed:         return 3
    case .maxSpeed:      return 2
    case .generic, .test: return 5
    }
}
```
**Status**: Similar concept, different implementations
**Differences**: 
- VBT uses fixed value
- Distance uses profile-based computed property

**Recommendation**: Create protocol with computed property, each implementation can override


#### Velocity Measurement / Modes
```swift
// VBTRepDetector
enum VelocityMeasurementMode {
    case concentricOnly
    case fullROM
}
var velocityMode: VelocityMeasurementMode = .concentricOnly

// DistanceBasedRepDetector
// No equivalent - always calculates from concentric phase
```
**Status**: VBT-specific feature
**Shareable**: NO - keep in VBTRepDetector

#### Learned Pattern
```swift
// VBTRepDetector (only)
var learnedPattern: LearnedPattern?
```
**Status**: VBT-specific
**Reason**: Pattern learning based on acceleration signature, not applicable to distance
**Shareable**: NO


### 1.2 SIMILAR CONFIGURATION (with differences)

#### ROM (Range of Motion) Configuration

```swift
// VBTRepDetector
private var MIN_CONC_DISPLACEMENT: Double {
    let settings = SettingsManager.shared
    if settings.useCustomROM {
        return settings.customROM * (1.0 - settings.customROMTolerance)
    }
    return 0.20  // meters
}

private var MAX_CONC_DISPLACEMENT: Double {
    let settings = SettingsManager.shared
    if settings.useCustomROM {
        return settings.customROM * (1.0 + settings.customROMTolerance)
    }
    return 0.80
}

// DistanceBasedRepDetector
var expectedROM: Double {
    if SettingsManager.shared.useCustomROM {
        return SettingsManager.shared.customROM * 1000.0  // m -> mm
    }
    return 500.0  // mm
}

private var minROM: Double {
    let tolerance = SettingsManager.shared.customROMTolerance
    let calculated = expectedROM * (1.0 - tolerance)
    return max(calculated - 10.0, 50.0)
}

private var maxROM: Double {
    let tolerance = SettingsManager.shared.customROMTolerance
    return expectedROM * (1.0 + tolerance) + 10.0
}
```

**Status**: Same logic, different units
**Differences**:
- VBT: meters (0.20-0.80m for bench press)
- Distance: millimeters (500mm default)
- Distance adds 10mm buffer + 50mm floor
- Distance uses tolerances differently

**Recommendation**: Extract to shared struct with unit conversion utilities


#### Minimum Concentric Duration

```swift
// VBTRepDetector
private let DEFAULT_MIN_CONCENTRIC: TimeInterval = 0.45

private func minConcentricDurationSec() -> TimeInterval {
    if DEBUG_DETECTION { return 0.30 }
    let fromPattern = learnedPattern.map { 
        max(0.50, $0.avgConcentricDuration * 0.8) 
    } ?? max(0.50, DEFAULT_MIN_CONCENTRIC)
    let baseDuration = lowSRSafeMode ? max(0.35, fromPattern * 0.85) : fromPattern
    return baseDuration * SettingsManager.shared.detectionProfile.durationMultiplier
}

// DistanceBasedRepDetector
private var minConcentricDuration: TimeInterval {
    let profile = SettingsManager.shared.detectionProfile
    switch profile {
    case .maxStrength:   return 0.5
    case .strength:      return 0.4
    case .strengthSpeed: return 0.3
    case .speed:         return 0.2
    case .maxSpeed:      return 0.15
    case .generic:       return 0.3
    case .test:          return 0.1
    }
}
```

**Status**: Similar intent, very different implementations
**Differences**:
- VBT: Adaptive based on patterns + safety mode + debug mode
- Distance: Simple profile switch
- VBT applies multiplier from detection profile
- Distance hardcoded per profile

**Recommendation**: Create protocol with method that can be overridden per implementation
- Base: minimal duration with profile multiplier
- VBT override: add pattern learning logic
- Distance override: profile switch


#### Amplitude Threshold

```swift
// VBTRepDetector (only)
private var minAmplitude: Double {
    let settings = SettingsManager.shared
    let base: Double
    if let p = learnedPattern {
        base = max(0.18, p.dynamicMinAmplitude * 0.9)
    } else if isInWarmup {
        base = max(0.18, settings.repMinAmplitude * 0.6)
    } else if let learned = learnedMinAmplitude {
        base = max(0.18, learned * 0.7)
    } else {
        base = 0.25
    }
    let adjusted = lowSRSafeMode ? max(0.15, base * 0.8) : base
    return adjusted * settings.detectionProfile.amplitudeMultiplier
}

// DistanceBasedRepDetector
private let MIN_VELOCITY_THRESHOLD = 50.0  // mm/s
```

**Status**: VBT has amplitude; Distance has velocity threshold
**Shareable**: Partially
- Extract concepts but keep separate thresholds


### 1.3 SMOOTHING WINDOW

```swift
// BOTH - Identical implementation
private var windowSize: Int {
    max(5, SettingsManager.shared.repSmoothingWindow)
}
```

**Status**: Identical
**Shareable**: YES - via protocol default


### 1.4 SAFETY MODE (Low Sample Rate)

```swift
// VBTRepDetector (only)
private var lowSRSafeMode: Bool { sampleRateHz < 40 }
```

**Status**: VBT-specific
**Used for**: Relaxing thresholds for low sample rates
**Shareable**: Could be extracted to protocol, useful for both


---

## 2. STATE MACHINE PATTERNS

### 2.1 Phase Enum (IDENTICAL)

```swift
// BOTH - Identical
enum Phase { 
    case idle
    case descending
    case ascending
    case completed 
}
var onPhaseChange: ((Phase) -> Void)?
```

**Status**: Perfectly identical
**Shareable**: YES - extract to protocol or shared type


### 2.2 Cycle State Enum (DIFFERENT)

#### VBTRepDetector
```swift
private enum CycleState { 
    case waitingDescent
    case waitingAscent 
}
private var cycleState: CycleState = .waitingDescent
```
**Logic**: Two states - waiting for valley, waiting for peak
- waitingDescent: looking for a valley (direction change from up to down)
- waitingAscent: tracking concentric phase from valley to peak

#### DistanceBasedRepDetector
```swift
private enum CycleState {
    case waitingDescent    // Await start of eccentric phase
    case descending        // In eccentric phase
    case waitingAscent     // Await start of concentric
    case ascending         // In concentric phase
}
private var state: CycleState = .waitingDescent
```
**Logic**: Four states - more granular tracking
- waitingDescent → descending → waitingAscent → ascending → waitingDescent

**Status**: Fundamentally different approaches
**Reason**: 
- VBT: Detects direction changes mathematically
- Distance: Uses explicit Arduino state + confirmation (3 consecutive samples)

**Recommendation**: Keep both CycleState enums separate
- Too much logic difference in state transitions
- Extract shared base protocol but keep CycleState implementation-specific


### 2.3 Direction Tracking

#### VBTRepDetector
```swift
private enum Direction { case none, up, down }
private var currentDirection: Direction = .none

private func detectDirection() -> Direction {
    guard smoothedValues.count >= 4 else { return .none }
    let last4 = Array(smoothedValues.suffix(4))
    let thr = lowSRSafeMode ? 0.01 : 0.03
    var ups = 0, downs = 0
    for i in 1..<last4.count {
        let d = last4[i] - last4[i-1]
        if d >  thr { ups  += 1 }
        if d < -thr { downs += 1 }
    }
    if ups   >= 2 && ups   > downs { return .up }
    if downs >= 2 && downs > ups   { return .down }
    return currentDirection
}
```

#### DistanceBasedRepDetector
```swift
// No Direction enum - uses MovementState from Arduino directly
// Arduino provides: .approaching, .receding, .idle
```

**Status**: Completely different approaches
**VBT**: Derives direction from smoothed acceleration changes
**Distance**: Receives pre-processed state from Arduino firmware

**Recommendation**: Keep separate, not shareable
- Core difference in data source and processing philosophy


---

## 3. COMMON VALIDATION LOGIC

### 3.1 Refractory Period (VERY SIMILAR)

```swift
// VBTRepDetector
private var minRefractory: TimeInterval {
    let base = DEBUG_DETECTION ? 0.40 : DEFAULT_REFRACTORY
    return lowSRSafeMode ? max(0.50, base * 0.75) : base
}

// Later in code:
let refractoryOK = lastRepTime == nil || 
    now.timeIntervalSince(lastRepTime!) >= minRefractory

// DistanceBasedRepDetector
private let MIN_TIME_BETWEEN_REPS: TimeInterval = 0.8

// In validation:
if let lastRep = lastRepTime, 
   currentSample.timestamp.timeIntervalSince(lastRep) < MIN_TIME_BETWEEN_REPS {
    print("❌ Rep scartata: troppo vicina all'ultima...")
    resetCycle()
    return
}
```

**Status**: Same concept, different implementation
**Differences**:
- VBT: Property with safety mode adjustment (~0.80s default)
- Distance: Fixed constant (0.8s)
- VBT: Boolean check in validation
- Distance: Guard in completion method

**Recommendation**: Extract to protocol method with default implementation
```swift
protocol RepDetectorProtocol {
    var lastRepTime: Date? { get set }
    var minRefractoryPeriod: TimeInterval { get }
    
    func isRefractoryPeriodValid(currentTime: Date) -> Bool {
        guard let lastRep = lastRepTime else { return true }
        return currentTime.timeIntervalSince(lastRep) >= minRefractoryPeriod
    }
}
```


### 3.2 Duration Validation (SIMILAR)

```swift
// VBTRepDetector
let durOK = concDur >= minConcentricDurationSec()

// DistanceBasedRepDetector
guard concentricDuration >= minConcentricDuration else {
    print("❌ Rep scartata: durata concentrica troppo breve...")
    resetCycle()
    return
}
```

**Status**: Same logic, different call sites
**Shareable**: YES - extract to shared method


### 3.3 ROM/Displacement Validation (SIMILAR)

```swift
// VBTRepDetector
if useDisplacementGate, concentricSamples.count >= MIN_CONC_SAMPLES {
    let (mpv0, ppv0, disp) = calculatePropulsiveVelocitiesAndDisplacement(...)
    if let d = disp {
        dispOK = (MIN_CONC_DISPLACEMENT...MAX_CONC_DISPLACEMENT).contains(d)
    }
}

// DistanceBasedRepDetector
guard displacementMM >= minROM, displacementMM <= maxROM else {
    print("❌ Rep scartata: ROM fuori range...")
    resetCycle()
    return
}
```

**Status**: Same concept, units differ
**Recommendation**: Extract to protocol with configurable ranges
```swift
protocol RepDetectorProtocol {
    var minROMDistance: Double { get }
    var maxROMDistance: Double { get }
    
    func isDisplacementValid(_ displacement: Double) -> Bool {
        return (minROMDistance...maxROMDistance).contains(displacement)
    }
}
```


### 3.4 Amplitude Validation (VBT Only)

```swift
// VBTRepDetector
let ampOK = amplitude >= minAmplitude

// DistanceBasedRepDetector
// Relies on velocity checks instead
```

**Status**: VBT-specific
**Reason**: Acceleration-based approach needs amplitude; distance doesn't need it (uses ROM validation)


---

## 4. COMMON CALLBACKS AND INTERFACES

### 4.1 Phase Change Callback (IDENTICAL)

```swift
// VBT
enum Phase { case idle, descending, ascending, completed }
var onPhaseChange: ((Phase) -> Void)?

// Distance
enum Phase { case idle, descending, ascending, completed }
var onPhaseChange: ((Phase) -> Void)?
```

**Status**: Identical
**Shareable**: YES - via protocol


### 4.2 Unrack Callback (IDENTICAL)

```swift
// BOTH
var onUnrack: (() -> Void)?

// VBTRepDetector
private func maybeAnnounceUnrack(current: Double) {
    guard !hasAnnouncedUnrack, lastRepTime == nil, abs(current) > idleThreshold * 2 else { return }
    if let until = unrackCooldownUntil, Date() < until { return }
    onUnrack?()
    hasAnnouncedUnrack = true
    unrackCooldownUntil = Date().addingTimeInterval(5)
}

// DistanceBasedRepDetector
if baselineDistance == nil, samples.count >= BASELINE_SAMPLES {
    baselineDistance = samples.prefix(BASELINE_SAMPLES).map(\.distance).reduce(0, +) / Double(BASELINE_SAMPLES)
    print("📏 Baseline stabilita: \(String(format: "%.1f", baselineDistance!)) mm")
    onUnrack?()
}
```

**Status**: Same callback signature, different logic for triggering
**VBT**: Calls on first significant movement after idle
**Distance**: Calls after baseline established (first N samples)

**Recommendation**: Extract callback to protocol, but keep trigger logic separate


### 4.3 Rep Detected Callback (DIFFERENT)

```swift
// VBTRepDetector
// Returns RepDetectionResult (immutable struct)
struct RepDetectionResult {
    let repDetected: Bool
    let currentValue: Double
    let meanPropulsiveVelocity: Double?
    let peakPropulsiveVelocity: Double?
    let duration: Double?
}

func addSample(accZ: Double, timestamp: Date) -> RepDetectionResult

// DistanceBasedRepDetector
// Uses callback with custom struct
struct RepMetrics {
    let meanPropulsiveVelocity: Double
    let peakPropulsiveVelocity: Double
    let displacement: Double
    let concentricDuration: TimeInterval
    let eccentricDuration: TimeInterval
    let totalDuration: TimeInterval
}
var onRepDetected: ((RepMetrics) -> Void)?
```

**Status**: Different return mechanisms
**VBT**: Returns result synchronously (polling model)
**Distance**: Uses callback (event model)

**Differences in metrics**:
- VBT: duration is concentric duration only
- Distance: includes eccentricDuration AND totalDuration
- Distance includes currentValue (missing)
- VBT includes currentValue (missing in Distance)

**Recommendation**: Create shared protocol with default callback mechanism
```swift
protocol RepDetectorProtocol {
    var onRepDetected: ((RepMetrics) -> Void)? { get set }
    
    // Shared metrics struct with all fields
    struct RepMetrics {
        let repDetected: Bool
        let currentValue: Double?
        let meanPropulsiveVelocity: Double?
        let peakPropulsiveVelocity: Double?
        let concentricDuration: TimeInterval
        let eccentricDuration: TimeInterval?
        let totalDuration: TimeInterval?
        let displacement: Double?  // meters
    }
}
```


---

## 5. COMMON DATA STRUCTURES

### 5.1 Sample Structures

#### VBTRepDetector
```swift
struct AccelMA { let timestamp: Date; let accZ: Double }

struct ConcentricSample {
    let timestamp: Date
    let accZ: Double
    let smoothedAccZ: Double
}

private var samples: [AccelerationSample] = []
private var concentricSamples: [ConcentricSample] = []
```

#### DistanceBasedRepDetector
```swift
private struct DistanceSample {
    let timestamp: Date
    let distance: Double   // mm
    let velocity: Double   // mm/s
}

private var samples: [DistanceSample] = []
private var concentricSamples: [DistanceSample] = []
```

**Status**: Similar pattern but different data types
**Shareable**: Partially - structure pattern is identical, data types differ

**Recommendation**: Create generic protocol for samples
```swift
protocol RepSample {
    var timestamp: Date { get }
}

struct AccelerationSample: RepSample {
    let timestamp: Date
    let accZ: Double
    var isPeak: Bool = false
    var isValley: Bool = false
}

struct DistanceSample: RepSample {
    let timestamp: Date
    let distance: Double
    let velocity: Double
}
```


### 5.2 Smoothed Values Storage

```swift
// BOTH - Identical pattern
private var smoothedValues: [Double] = []

// Update mechanism (different)
// VBT: Appends from calculateMovingAverage()
// Distance: Appends from updateSmoothedValues()
```

**Status**: Identical concept
**Shareable**: YES - can be generic


### 5.3 Tracking Peak/Valley (VBT Only)

```swift
// VBTRepDetector
private var lastPeak: (value: Double, index: Int, time: Date)?
private var lastValley: (value: Double, index: Int, time: Date)?

// DistanceBasedRepDetector
// Uses different approach - tracks start/end points instead
private var eccentricStartTime: Date?
private var eccentricStartDistance: Double?
private var concentricStartTime: Date?
private var concentricStartDistance: Double?
private var concentricPeakDistance: Double?
```

**Status**: Fundamentally different
**Reason**: 
- VBT: Mathematical peak/valley detection
- Distance: Phase-based tracking from Arduino state

**Shareable**: NO - keep separate


---

## 6. COMMON RESET AND LIFECYCLE METHODS

### 6.1 Full Reset (SIMILAR)

#### VBTRepDetector
```swift
func reset() {
    samples.removeAll()
    smoothedValues.removeAll()
    lastPeak = nil
    lastValley = nil
    lastRepTime = nil
    isFirstMovement = true
    isInWarmup = true
    repAmplitudes.removeAll()
    learnedMinAmplitude = nil
    currentDirection = .none
    cycleState = .waitingDescent
    concentricSamples.removeAll()
    isTrackingConcentric = false
    hasAnnouncedUnrack = false
    unrackCooldownUntil = nil
}
```

#### DistanceBasedRepDetector
```swift
func reset() {
    queue.sync {
        samples.removeAll()
        smoothedDistances.removeAll()
        state = .waitingDescent
        lastRepTime = nil
        eccentricStartTime = nil
        eccentricStartDistance = nil
        concentricSamples.removeAll()
        concentricStartTime = nil
        concentricStartDistance = nil
        concentricPeakDistance = nil
        baselineDistance = nil
        idleStartTime = nil
    }
}
```

**Status**: Same pattern, different state variables
**Differences**:
- Distance uses dispatch queue for thread safety
- Distance doesn't reset phase-specific tracking like VBT does
- VBT resets more state (warmup, pattern learning, direction)

**Recommendation**: Create protocol with default reset() that clears shared state
```swift
protocol RepDetectorProtocol {
    var samples: [RepSample] { get set }
    var smoothedValues: [Double] { get set }
    var lastRepTime: Date? { get set }
    
    func reset() {
        samples.removeAll()
        smoothedValues.removeAll()
        lastRepTime = nil
        // Call resetImplementationSpecific()
    }
    
    func resetImplementationSpecific()  // Override in subclasses
}
```


### 6.2 Cycle Reset (DISTANCE ONLY)

```swift
private func resetCycle() {
    state = .waitingDescent
    eccentricStartTime = nil
    eccentricStartDistance = nil
    concentricSamples.removeAll()
    concentricStartTime = nil
    concentricStartDistance = nil
    concentricPeakDistance = nil
    if idleStartTime == nil {
        idleStartTime = Date()
    }
    onPhaseChange?(.idle)
}
```

**Status**: Distance-specific (VBT doesn't have equivalent)
**Reason**: Distance tracks phases explicitly; VBT uses cycle state only

**Shareable**: Partially - pattern could be useful for VBT


---

## 7. COMMON VELOCITY CALCULATION

### 7.1 VBT: Propulsive Velocities with Displacement

```swift
private func calculatePropulsiveVelocitiesAndDisplacement(
    from src: [ConcentricSample]
) -> (Double?, Double?, Double?) {
    // 1. Get acceleration samples
    // 2. Detrend acceleration
    // 3. Integrate to get velocity
    // 4. Find peak velocity
    // 5. Apply zero-crossing cutoff
    // 6. Calculate MPV/PPV
    // 7. Apply velocity correction factor based on sample rate
    // 8. Integrate velocity to get displacement
}

private func clampVBT(_ mpv: Double?, _ ppv: Double?) -> (Double?, Double?)
```

**Process**:
- Takes smoothed acceleration samples
- Detrends (removes gravity/DC offset)
- Integrates to velocity using trapezoidal rule
- Finds propulsive phase (up to zero-crossing of acceleration)
- Calculates mean and peak
- Applies velocity correction for low sample rates (25-60Hz interpolation)
- Integrates velocity to get displacement
- Clamps to realistic ranges (0.05-2.5 m/s MPV, 0.05-3.0 m/s PPV)


### 7.2 Distance: Direct Velocity from Arduino

```swift
private func calculateVelocityMetrics() -> (mpv: Double, ppv: Double) {
    guard !concentricSamples.isEmpty else { return (0.0, 0.0) }
    
    // Arduino already provides velocity in mm/s
    let velocities = concentricSamples.map { abs($0.velocity) / 1000.0 }
    
    let ppv = velocities.max() ?? 0.0
    let propulsiveVelocities = velocities.filter { $0 > 0.01 }
    let mpv = propulsiveVelocities.isEmpty ? 0.0 : 
        propulsiveVelocities.reduce(0, +) / Double(propulsiveVelocities.count)
    
    return (mpv, ppv)
}
```

**Process**:
- Uses pre-calculated velocity from Arduino (mm/s)
- Converts to m/s
- Takes absolute value (concentrica = negative velocity)
- Calculates PPV (max velocity)
- Filters propulsive velocities (> 0.01 m/s)
- Calculates MPV (mean of propulsive velocities)


**Status**: Fundamentally different approaches
**Shareable**: NO - completely different calculations
- VBT must integrate from acceleration
- Distance receives velocity directly from sensor


---

## 8. THREAD SAFETY AND QUEUING

### VBTRepDetector
```swift
// No explicit thread safety mechanism
final class VBTRepDetector { ... }
```

### DistanceBasedRepDetector
```swift
final class DistanceBasedRepDetector: ObservableObject {
    private let queue = DispatchQueue(label: "com.vbttracker.repdetector", 
                                     qos: .userInitiated)
    
    func processSample(...) {
        queue.sync { processSampleUnsafe(...) }
    }
}
```

**Status**: Different approaches
**VBT**: No explicit thread safety (assumes main thread)
**Distance**: Uses serial dispatch queue for thread safety

**Recommendation**: Add thread safety to protocol
```swift
protocol RepDetectorProtocol {
    func addSample(...) // or processSample(...)
    // Should be thread-safe
}
```


---

## 9. UNRACK DETECTION (VBT ONLY)

```swift
private var hasAnnouncedUnrack = false
private var unrackCooldownUntil: Date?

private func maybeAnnounceUnrack(current: Double) {
    guard !hasAnnouncedUnrack, lastRepTime == nil, 
          abs(current) > idleThreshold * 2 else { return }
    if let until = unrackCooldownUntil, Date() < until { return }
    onUnrack?()
    hasAnnouncedUnrack = true
    unrackCooldownUntil = Date().addingTimeInterval(5)
}
```

**Status**: VBT-specific
**Reason**: Based on acceleration threshold above idle
**Distance**: Uses baseline establishment instead

**Shareable**: NO - different concepts


---

## 10. PATTERN LEARNING (VBT ONLY)

```swift
// VBTRepDetector has complete pattern learning system:
var learnedPattern: LearnedPattern?
func recognizePatternIfPossible()
func savePatternSequence(...)

// DistanceBasedRepDetector: NO PATTERN LEARNING
```

**Status**: VBT-specific feature
**Reason**: Signature recognition from acceleration samples
**Shareable**: NO - not applicable to distance sensor


---

## 11. DEBUG STATE (VBT ONLY)

```swift
private let DEBUG_DETECTION = false
func printDebugState()
func validateCurrentMovement() -> String
```

**Status**: VBT-specific debugging
**Distance**: Has logging but no formal debug mode

**Recommendation**: Could create shared debug protocol


---

## DETAILED COMMONALITY MATRIX

| Component | VBT | Distance | Shared? | Notes |
|-----------|-----|----------|---------|-------|
| **Configuration** |
| sampleRateHz | Yes | Yes | YES - protocol default |
| lookAheadSamples | Yes (fixed) | Yes (computed) | PARTIAL - different implementation |
| velocityMode | Yes (enum) | No | NO - VBT-specific |
| learnedPattern | Yes | No | NO - VBT-specific |
| windowSize | Yes | Yes | YES - identical |
| lowSRSafeMode | Yes | No | PARTIAL - concept useful for both |
| **State** |
| Phase enum | Yes | Yes | YES - identical |
| CycleState enum | Yes (2-state) | Yes (4-state) | NO - too different |
| Direction | Yes | No | NO - different approach |
| samples | Yes | Yes | PARTIAL - different types |
| smoothedValues | Yes | Yes | YES - both use [Double] |
| lastRepTime | Yes | Yes | YES - identical |
| concentricSamples | Yes | Yes | PARTIAL - different types |
| **Validation** |
| Refractory period | Yes | Yes | YES - extract method |
| Duration validation | Yes | Yes | YES - extract method |
| ROM/Displacement | Yes | Yes | PARTIAL - units differ |
| Amplitude threshold | Yes | No | NO - VBT only |
| **Callbacks** |
| onPhaseChange | Yes | Yes | YES - identical |
| onUnrack | Yes | Yes | PARTIAL - different trigger logic |
| onRepDetected | Yes (return) | Yes (callback) | PARTIAL - different mechanisms |
| **Methods** |
| reset() | Yes | Yes | YES - different state but same concept |
| addSample/processSample | Yes | Yes | PARTIAL - different signatures |
| calculateVelocities | Yes | Yes | NO - completely different |
| resetCycle | No | Yes | PARTIAL - useful for both |
| **Tracking** |
| lastPeak/Valley | Yes | No | NO - VBT-specific |
| Baseline/Eccentric tracking | No | Yes | NO - Distance-specific |

---

## REFACTORING ARCHITECTURE RECOMMENDATION

### 1. Create Shared Protocol Hierarchy

```swift
// Base protocol for all rep detectors
protocol RepDetectorProtocol: AnyObject {
    
    // Configuration
    var sampleRateHz: Double { get set }
    var lookAheadSamples: Int { get }
    
    // Callbacks
    var onPhaseChange: ((Phase) -> Void)? { get set }
    var onUnrack: (() -> Void)? { get set }
    
    // Lifecycle
    func reset()
    
    // State query
    var lastRepTime: Date? { get }
    var isInMotion: Bool { get }
    
    // Validation helpers
    var minRefractoryPeriod: TimeInterval { get }
    func isRefractoryPeriodValid(currentTime: Date) -> Bool
}

// Extension with default implementations
extension RepDetectorProtocol {
    func isRefractoryPeriodValid(currentTime: Date) -> Bool {
        guard let lastRep = lastRepTime else { return true }
        return currentTime.timeIntervalSince(lastRep) >= minRefractoryPeriod
    }
}

// Shared Phase enum
enum DetectorPhase {
    case idle
    case descending
    case ascending
    case completed
}
```

### 2. Create Shared Configuration Struct

```swift
struct DetectorConfig {
    var sampleRateHz: Double = 50.0
    var minRefractoryPeriod: TimeInterval = 0.80
    var smoothingWindow: Int = 5
    var lowSRSafeMode: Bool { sampleRateHz < 40 }
    
    // ROM configuration (unit-agnostic)
    struct ROMConfig {
        let expectedValue: Double  // Could be meters or mm
        let minValue: Double
        let maxValue: Double
        
        func isValid(_ value: Double) -> Bool {
            return (minValue...maxValue).contains(value)
        }
    }
}
```

### 3. Sensor-Specific Detector Classes

```swift
final class VBTRepDetector: RepDetectorProtocol, ObservableObject {
    // Keep all VBT-specific logic:
    // - Pattern learning
    // - Direction detection
    // - Acceleration-based velocity calculation
    // - 2-state cycle machine
    // - Amplitude threshold
    // - Unrack detection
    
    var learnedPattern: LearnedPattern?
    var velocityMode: VelocityMeasurementMode = .concentricOnly
    
    // Implement protocol methods
    func reset() { /* specific reset */ }
}

final class DistanceBasedRepDetector: RepDetectorProtocol, ObservableObject {
    // Keep all distance-specific logic:
    // - Arduino state consumption
    // - 4-state cycle machine
    // - Direct velocity from sensor
    // - ROM from distance delta
    // - Baseline establishment
    
    private let queue = DispatchQueue(...)
    
    // Implement protocol methods
    func reset() { /* specific reset */ }
}
```

### 4. Create Shared Utility Types

```swift
// Shared validation result
struct ValidationResult {
    let isValid: Bool
    let failureReasons: [String]
}

// Shared phase tracking helper
struct PhaseTracker {
    var currentPhase: DetectorPhase = .idle
    var onPhaseChange: ((DetectorPhase) -> Void)?
    
    mutating func setPhase(_ phase: DetectorPhase) {
        if phase != currentPhase {
            currentPhase = phase
            onPhaseChange?(phase)
        }
    }
}

// Shared refractory period validation
struct RefractoryValidator {
    private var lastEventTime: Date?
    let minimumInterval: TimeInterval
    
    mutating func recordEvent(at: Date = Date()) {
        lastEventTime = at
    }
    
    func canProceed(at: Date = Date()) -> Bool {
        guard let last = lastEventTime else { return true }
        return at.timeIntervalSince(last) >= minimumInterval
    }
}
```

### 5. What to Keep Separate

#### VBTRepDetector Exclusive
- Pattern learning system
- Direction detection (up/down)
- Acceleration integration to velocity
- Amplitude thresholding
- Velocity correction factor for low SR
- Unrack detection via acceleration
- 2-state cycle machine
- Debug state validation

#### DistanceBasedRepDetector Exclusive
- Arduino MovementState consumption
- Baseline recalibration
- 4-state cycle machine
- Direct velocity from sensor
- Spike filtering
- Thread-safe dispatch queue
- Eccentric/concentric phase tracking
- Touch-and-go transition logic

#### Potentially Shared But Not Worth It
- CycleState enums (too different)
- Sample structures (different data types)
- Core detection logic (completely different)

---

## SUMMARY OF RECOMMENDATIONS

### HIGH PRIORITY (Easy wins)
1. **Extract Phase enum** to shared type
2. **Extract RefractoryValidator** utility
3. **Extract PhaseTracker** utility
4. **Create RepDetectorProtocol** with common interface
5. **Create DetectorConfig** struct for shared configuration

### MEDIUM PRIORITY (Good improvements)
6. Extract duration validation to shared helper method
7. Create ROM validation struct with unit conversion
8. Create shared sample protocol for type safety
9. Add thread safety protocol/mixin

### LOW PRIORITY (Not worth complexity)
10. Don't try to unify CycleState enums
11. Don't try to unify velocity calculation
12. Don't try to unify direction detection
13. Keep callback mechanisms separate (async vs sync)

---

## MIGRATION STRATEGY

1. Create shared protocol without touching existing code
2. Make both detectors conform to protocol (mostly no changes)
3. Extract utility types (RefractoryValidator, PhaseTracker)
4. Update both to use utilities
5. Create DetectorConfig for future consolidation
6. Add comprehensive tests
7. Optional: Create factory pattern for detector selection

