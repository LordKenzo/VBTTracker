# Appendici Tecniche

## Appendice A: Codice Arduino Completo

### A.1 Main Firmware (VBTTracker.ino)

```cpp
/**
 * VBT Tracker - Arduino Nano 33 BLE Firmware
 *
 * Hardware:
 * - Arduino Nano 33 BLE (nRF52840)
 * - VL53L0X Time-of-Flight laser sensor (I2C)
 * - LSM9DS1 IMU (onboard)
 *
 * Functionality:
 * - Reads distance from VL53L0X @ ~50Hz
 * - Detects movement state (IDLE, ECCENTRIC, CONCENTRIC)
 * - Reads acceleration from IMU
 * - Sends data via USB Serial
 *
 * Serial Protocol:
 * D:<distance_mm>,S:<state>,A:<ax>,<ay>,<az>\n
 * Example: D:523.5,S:IDLE,A:0.12,-0.05,9.81\n
 */

#include <Wire.h>
#include <VL53L0X.h>
#include <Arduino_LSM9DS1.h>

// VL53L0X laser sensor
VL53L0X sensor;

// Thresholds
#define VELOCITY_THRESHOLD 8.0      // mm/s minimum for movement
#define HOLD_ON_MS 60               // ms above threshold to confirm movement
#define HOLD_OFF_MS 120             // ms below threshold to confirm idle

// Movement states
enum State {
  IDLE,       // Barbell stationary
  RECEDING,   // Moving away (eccentric)
  APPROACHING // Moving closer (concentric)
};

State currentState = IDLE;

// Distance tracking
float previousDistance = 0;
float currentDistance = 0;
unsigned long lastReadTime = 0;
unsigned long lastStateChange = 0;

// Hold timers
unsigned long movingStartTime = 0;
unsigned long idleStartTime = 0;

void setup() {
  // Initialize Serial @ 115200 baud
  Serial.begin(115200);
  while (!Serial && millis() < 3000);  // Wait max 3s for serial

  // Initialize I2C
  Wire.begin();
  Wire.setClock(400000);  // 400kHz fast mode

  // Initialize VL53L0X
  sensor.setTimeout(500);
  if (!sensor.init()) {
    Serial.println("ERROR:VL53L0X_INIT_FAILED");
    while (1);  // Halt
  }

  // Set long range mode (max 2m)
  sensor.setSignalRateLimit(0.1);
  sensor.setVcselPulsePeriod(VL53L0X::VcselPeriodPreRange, 18);
  sensor.setVcselPulsePeriod(VL53L0X::VcselPeriodFinalRange, 14);

  // Continuous mode @ 50ms (20Hz, actual ~50Hz with processing)
  sensor.startContinuous(50);

  // Initialize IMU
  if (!IMU.begin()) {
    Serial.println("ERROR:IMU_INIT_FAILED");
    while (1);  // Halt
  }

  Serial.println("READY");
  lastReadTime = millis();
}

void loop() {
  // Read distance
  currentDistance = sensor.readRangeContinuousMillimeters();
  unsigned long now = millis();
  float dt = (now - lastReadTime) / 1000.0;  // seconds

  // Calculate velocity (mm/s)
  float velocity = 0;
  if (dt > 0 && !sensor.timeoutOccurred()) {
    velocity = (currentDistance - previousDistance) / dt;
  }

  // State machine
  updateState(velocity, now);

  // Read IMU (if available)
  float ax = 0, ay = 0, az = 0;
  if (IMU.accelerationAvailable()) {
    IMU.readAcceleration(ax, ay, az);  // g units
  }

  // Send data via serial
  sendData(currentDistance, currentState, ax, ay, az);

  // Update
  previousDistance = currentDistance;
  lastReadTime = now;

  // Rate limiting (target 50Hz = 20ms period)
  // Actual timing handled by VL53L0X continuous mode
}

void updateState(float velocity, unsigned long now) {
  float absVelocity = abs(velocity);

  // Detect movement start
  if (absVelocity > VELOCITY_THRESHOLD) {
    if (movingStartTime == 0) {
      movingStartTime = now;
    }

    // Confirm movement after HOLD_ON_MS
    if (now - movingStartTime >= HOLD_ON_MS) {
      idleStartTime = 0;  // Reset idle timer

      // Determine direction
      State newState = (velocity > 0) ? RECEDING : APPROACHING;

      if (newState != currentState) {
        currentState = newState;
        lastStateChange = now;
      }
    }
  }
  // Detect idle
  else {
    if (idleStartTime == 0) {
      idleStartTime = now;
    }

    // Confirm idle after HOLD_OFF_MS
    if (now - idleStartTime >= HOLD_OFF_MS) {
      movingStartTime = 0;  // Reset moving timer

      if (currentState != IDLE) {
        currentState = IDLE;
        lastStateChange = now;
      }
    }
  }
}

void sendData(float distance, State state, float ax, float ay, float az) {
  // Protocol: D:<distance>,S:<state>,A:<ax>,<ay>,<az>
  Serial.print("D:");
  Serial.print(distance, 1);  // 1 decimal
  Serial.print(",S:");

  switch (state) {
    case IDLE:        Serial.print("IDLE"); break;
    case RECEDING:    Serial.print("ECCENTRIC"); break;
    case APPROACHING: Serial.print("CONCENTRIC"); break;
  }

  Serial.print(",A:");
  Serial.print(ax, 2);  // 2 decimals
  Serial.print(",");
  Serial.print(ay, 2);
  Serial.print(",");
  Serial.println(az, 2);
}
```

### A.2 Calibration Sketch (Optional)

```cpp
/**
 * VL53L0X Calibration Utility
 *
 * Measures baseline distance and offset correction
 */

#include <Wire.h>
#include <VL53L0X.h>

VL53L0X sensor;

void setup() {
  Serial.begin(115200);
  while (!Serial);

  Wire.begin();
  sensor.setTimeout(500);

  if (!sensor.init()) {
    Serial.println("FAILED");
    while (1);
  }

  sensor.startContinuous(50);

  Serial.println("Calibration: Place sensor at known distance");
  Serial.println("Taking 100 samples...");

  float sum = 0;
  for (int i = 0; i < 100; i++) {
    float distance = sensor.readRangeContinuousMillimeters();
    sum += distance;
    Serial.print(".");
    delay(50);
  }

  float avg = sum / 100.0;
  Serial.println();
  Serial.print("Average distance: ");
  Serial.print(avg, 2);
  Serial.println(" mm");

  Serial.print("Enter actual distance (mm): ");
  while (!Serial.available());
  float actual = Serial.parseFloat();

  float offset = actual - avg;
  Serial.print("Offset correction: ");
  Serial.print(offset, 2);
  Serial.println(" mm");
  Serial.println("Add this to all readings.");
}

void loop() {}
```

---

## Appendice B: JSON Schema Examples

### B.1 Training Session

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TrainingSession",
  "type": "object",
  "required": ["id", "date", "exerciseId", "exerciseName", "reps"],
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "Unique session identifier"
    },
    "date": {
      "type": "string",
      "format": "date-time",
      "description": "Session timestamp"
    },
    "exerciseId": {
      "type": "string",
      "format": "uuid",
      "description": "Reference to Exercise"
    },
    "exerciseName": {
      "type": "string",
      "description": "Exercise name (denormalized)"
    },
    "reps": {
      "type": "array",
      "items": {
        "$ref": "#/definitions/RepData"
      },
      "minItems": 1
    },
    "notes": {
      "type": "string",
      "description": "Optional user notes"
    },
    "targetVelocity": {
      "type": "number",
      "minimum": 0,
      "description": "Target MPV in m/s"
    }
  },
  "definitions": {
    "RepData": {
      "type": "object",
      "required": ["id", "meanVelocity", "peakVelocity", "velocityLossFromFirst"],
      "properties": {
        "id": {
          "type": "string",
          "format": "uuid"
        },
        "meanVelocity": {
          "type": "number",
          "minimum": 0,
          "description": "MPV in m/s"
        },
        "peakVelocity": {
          "type": "number",
          "minimum": 0,
          "description": "PPV in m/s"
        },
        "velocityLossFromFirst": {
          "type": "number",
          "minimum": 0,
          "maximum": 100,
          "description": "% loss from first rep"
        }
      }
    }
  }
}
```

**Example instance**:

```json
{
  "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
  "date": "2024-12-15T10:30:00Z",
  "exerciseId": "BENCH-PRESS-UUID",
  "exerciseName": "Panca Piana",
  "targetVelocity": 0.75,
  "reps": [
    {
      "id": "REP-001",
      "meanVelocity": 0.78,
      "peakVelocity": 1.02,
      "velocityLossFromFirst": 0.0
    },
    {
      "id": "REP-002",
      "meanVelocity": 0.72,
      "peakVelocity": 0.95,
      "velocityLossFromFirst": 7.7
    },
    {
      "id": "REP-003",
      "meanVelocity": 0.68,
      "peakVelocity": 0.89,
      "velocityLossFromFirst": 12.8
    }
  ],
  "notes": "Felt strong, stopped at 15% VL"
}
```

### B.2 Pattern Sequence

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PatternSequence",
  "type": "object",
  "required": ["id", "date", "label", "exerciseId", "repCount", "samples"],
  "properties": {
    "id": {"type": "string", "format": "uuid"},
    "date": {"type": "string", "format": "date-time"},
    "label": {"type": "string"},
    "exerciseId": {"type": "string", "format": "uuid"},
    "repCount": {"type": "integer", "minimum": 1},
    "loadPercentage": {"type": "number", "minimum": 0, "maximum": 100},
    "avgMPV": {"type": "number", "minimum": 0},
    "avgPPV": {"type": "number", "minimum": 0},
    "samples": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["timestamp", "acceleration", "angularVelocity", "angles"],
        "properties": {
          "timestamp": {"type": "string", "format": "date-time"},
          "acceleration": {
            "type": "array",
            "items": {"type": "number"},
            "minItems": 3,
            "maxItems": 3,
            "description": "[ax, ay, az] in g"
          },
          "angularVelocity": {
            "type": "array",
            "items": {"type": "number"},
            "minItems": 3,
            "maxItems": 3,
            "description": "[gx, gy, gz] in deg/s"
          },
          "angles": {
            "type": "array",
            "items": {"type": "number"},
            "minItems": 3,
            "maxItems": 3,
            "description": "[roll, pitch, yaw] in deg"
          }
        }
      }
    }
  }
}
```

---

## Appendice C: Protocolli di Comunicazione

### C.1 Arduino USB Serial Protocol

**Format**: ASCII text, newline-terminated
**Baud Rate**: 115200
**Encoding**: UTF-8

**Message Structure**:
```
D:<distance>,S:<state>,A:<ax>,<ay>,<az>\n
```

**Fields**:
- `D`: Distance in millimeters (float, 1 decimal)
- `S`: State (IDLE | ECCENTRIC | CONCENTRIC)
- `A`: Acceleration X,Y,Z in g (float, 2 decimals)

**Examples**:
```
D:523.5,S:IDLE,A:0.12,-0.05,9.81
D:520.2,S:ECCENTRIC,A:0.15,-0.08,9.75
D:380.4,S:ECCENTRIC,A:0.22,-0.12,9.60
D:135.8,S:CONCENTRIC,A:-0.18,0.09,10.15
D:485.2,S:CONCENTRIC,A:-0.25,0.15,10.30
D:522.8,S:IDLE,A:0.08,-0.02,9.83
```

**Error Messages**:
```
ERROR:VL53L0X_INIT_FAILED
ERROR:IMU_INIT_FAILED
ERROR:TIMEOUT
```

**Startup Message**:
```
READY
```

**Parsing (Swift)**:
```swift
func parseArduinoPacket(_ line: String) {
    // D:523.5,S:IDLE,A:0.12,-0.05,9.81
    let components = line.split(separator: ",")

    guard components.count == 3 else { return }

    // Distance
    if let distStr = components[0].split(separator: ":").last,
       let distance = Double(distStr) {
        self.distance = distance
    }

    // State
    if let stateStr = components[1].split(separator: ":").last {
        self.movementState = MovementState(rawValue: String(stateStr)) ?? .idle
    }

    // Acceleration
    if let accelStr = components[2].split(separator: ":").last {
        let values = accelStr.split(separator: ",").compactMap { Double($0) }
        if values.count == 3 {
            self.acceleration = values
        }
    }
}
```

### C.2 WitMotion BLE Protocol

**Service UUID**: `0000FFE5-0000-1000-8000-00805F9A34FB` (WT901BLE)
**Notify Characteristic**: `0000FFE4-0000-1000-8000-00805F9A34FB`
**Write Characteristic**: `0000FFE9-0000-1000-8000-00805F9A34FB`

**Data Packet Format** (0x55 0x61 - Combined):
```
Byte 0-1:  Header (0x55 0x61)
Byte 2-3:  AxL, AxH (accel X, int16, little-endian)
Byte 4-5:  AyL, AyH (accel Y)
Byte 6-7:  AzL, AzH (accel Z)
Byte 8-9:  GxL, GxH (gyro X)
Byte 10-11: GyL, GyH (gyro Y)
Byte 12-13: GzL, GzH (gyro Z)
Byte 14-15: RollL, RollH (angle roll)
Byte 16-17: PitchL, PitchH (angle pitch)
Byte 18-19: YawL, YawH (angle yaw)
```

**Conversion**:
```swift
let ax = Double(Int16(bytes[3]) << 8 | Int16(bytes[2])) / 32768.0 * 16.0  // ±16g range
let gx = Double(Int16(bytes[9]) << 8 | Int16(bytes[8])) / 32768.0 * 2000.0  // ±2000°/s
let roll = Double(Int16(bytes[15]) << 8 | Int16(bytes[14])) / 32768.0 * 180.0  // ±180°
```

**Configuration Commands**:

| Command | Hex | Description |
|---------|-----|-------------|
| Unlock | `FF AA 69 88 B5` | Unlock configuration |
| Set Rate 200Hz | `FF AA 03 0B 00` | Output rate 200Hz |
| Set BW 256Hz | `FF AA 1F 00 00` | Bandwidth filter 256Hz |
| Save | `FF AA 00 00 00` | Save to EEPROM |
| Read Rate | `FF AA 27 03 00` | Read rate register |

**Rate Codes**:
- `0x06`: 10 Hz (default)
- `0x08`: 50 Hz
- `0x09`: 100 Hz
- `0x0B`: 200 Hz

---

## Appendice D: User Study Materials

### D.1 System Usability Scale (SUS) Questionnaire

**Instructions**: Rate each statement from 1 (Strongly Disagree) to 5 (Strongly Agree)

1. Penso che userei questo sistema frequentemente
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

2. Ho trovato il sistema inutilmente complesso
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

3. Ho trovato il sistema facile da usare
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

4. Penso di aver bisogno del supporto di un tecnico per usare questo sistema
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

5. Ho trovato le varie funzioni del sistema ben integrate
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

6. Ho trovato troppa inconsistenza in questo sistema
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

7. Immagino che la maggior parte delle persone imparerebbero a usare questo sistema velocemente
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

8. Ho trovato il sistema molto macchinoso da usare
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

9. Mi sono sentito molto sicuro nell'usare il sistema
   - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

10. Ho dovuto imparare molte cose prima di poter usare questo sistema
    - [ ] 1  [ ] 2  [ ] 3  [ ] 4  [ ] 5

**Scoring**:
- Items 1,3,5,7,9: Score = (response - 1)
- Items 2,4,6,8,10: Score = (5 - response)
- Sum all scores and multiply by 2.5
- Final SUS score: 0-100

**Interpretation**:
- 90-100: Grade A+ (Best Imaginable)
- 80-89: Grade A (Excellent)
- 70-79: Grade B (Good)
- 60-69: Grade C (OK)
- 50-59: Grade D (Poor)
- 0-49: Grade F (Awful)

### D.2 Feedback Questions

**Open-ended questions** (post-session):

1. Quali sono stati i 3 aspetti che hai apprezzato di più del sistema?

2. Quali sono stati i 3 aspetti che vorresti migliorare?

3. Hai riscontrato bug o comportamenti inaspettati? Se sì, descrivi.

4. Quanto è stato accurato il rilevamento delle ripetizioni? (1-10)

5. Useresti questo sistema per il tuo allenamento abituale? Perché?

6. Quale feature vorresti vedere aggiunta in futuro?

7. Confronto con altri sistemi VBT (se hai esperienza): come si posiziona VBT Tracker?

---

## Appendice E: Velocity Zones Reference Table

### E.1 Bench Press (González-Badillo & Sánchez-Medina, 2010)

| Zone | % 1RM | MPV Range (m/s) | Reps | Rest | Training Effect |
|------|-------|-----------------|------|------|-----------------|
| Forza Massima | 90-100% | 0.15-0.30 | 1-3 | 3-5 min | Max strength, neural |
| Forza | 80-90% | 0.30-0.50 | 3-6 | 2-4 min | Strength, hypertrophy |
| Forza-Velocità | 70-80% | 0.50-0.75 | 6-10 | 1-3 min | Power, mixed |
| Velocità | 60-70% | 0.75-1.00 | 8-12 | 1-2 min | Speed-strength |
| Velocità Massima | 40-60% | 1.00-2.00 | 12-20 | 30-90s | Explosive power |

### E.2 Back Squat

| Zone | % 1RM | MPV Range (m/s) | Notes |
|------|-------|-----------------|-------|
| Forza Massima | 90-100% | 0.25-0.40 | Lower than bench |
| Forza | 80-90% | 0.40-0.60 | Hypertrophy focus |
| Forza-Velocità | 70-80% | 0.60-0.85 | Power development |
| Velocità | 60-70% | 0.85-1.10 | Jump training |
| Velocità Massima | 40-60% | 1.10-1.50 | Ballistic |

### E.3 Velocity Loss Thresholds

| VL % | Training Goal | Study Reference |
|------|---------------|-----------------|
| 10% | Neuromuscular (explosive) | Pareja-Blanco et al., 2017 |
| 20% | Strength-hypertrophy (balanced) | Pareja-Blanco et al., 2017 |
| 30% | Hypertrophy (metabolic stress) | Weakley et al., 2021 |
| 40%+ | Endurance (not recommended VBT) | - |

**Recommendation**: VBT Tracker default 20% (optimal per letteratura)

---

## Appendice F: Hardware Schematics

### F.1 Arduino + VL53L0X Wiring

```
Arduino Nano 33 BLE          VL53L0X
┌────────────────┐          ┌─────────┐
│                │          │         │
│  3.3V      ────┼──────────┤ VIN     │
│  GND       ────┼──────────┤ GND     │
│  SCL (A5)  ────┼──────────┤ SCL     │
│  SDA (A4)  ────┼──────────┤ SDA     │
│                │          │         │
│  XSHUT (D2)────┼──────────┤ XSHUT   │ (optional, for reset)
│                │          │         │
└────────────────┘          └─────────┘

USB ──→ Computer (Serial communication)
```

**Notes**:
- VL53L0X operates at 3.3V (compatible with Nano 33 BLE)
- I2C pull-ups usually onboard VL53L0X module
- XSHUT optional for hard reset capability
- No external components needed (ready-to-use)

### F.2 WitMotion Mounting

**Recommended placement**:
```
    Bilanciere
    ═══════════════════════════
         │
         │ (motion direction)
         ▼
    ┌─────────┐
    │ WT901BLE│  ← Velcro strap attachment
    │  [↕]    │     X-axis = vertical
    └─────────┘
```

**Axis orientation**:
- X: Vertical (primary movement axis)
- Y: Lateral (bar path deviation)
- Z: Fore-aft (stability)

---

## Appendice G: Build Instructions

### G.1 Xcode Project Setup

```bash
# Clone repository
git clone https://github.com/[username]/VBTTracker.git
cd VBTTracker

# Install dependencies (if using CocoaPods)
pod install

# Open workspace
open VBTTracker.xcworkspace
```

### G.2 Required Capabilities

**Info.plist additions**:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>VBT Tracker needs Bluetooth to connect to WitMotion sensor</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>VBT Tracker uses Bluetooth LE for sensor communication</string>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

### G.3 Build Configurations

**Debug**:
```
SWIFT_OPTIMIZATION_LEVEL = -Onone
ENABLE_TESTABILITY = YES
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
GCC_PREPROCESSOR_DEFINITIONS = DEBUG=1
```

**Release**:
```
SWIFT_OPTIMIZATION_LEVEL = -O
ENABLE_TESTABILITY = NO
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
STRIP_INSTALLED_PRODUCT = YES
```

---

## Appendice H: Acronimi e Glossario

| Term | Full Name | Description |
|------|-----------|-------------|
| VBT | Velocity-Based Training | Training methodology using bar velocity |
| MPV | Mean Propulsive Velocity | Average velocity during concentric phase |
| PPV | Peak Propulsive Velocity | Maximum velocity during concentric |
| ROM | Range of Motion | Total displacement during rep (meters) |
| VL | Velocity Loss | % decrease from first rep velocity |
| 1RM | One Repetition Maximum | Maximum weight for single rep |
| DTW | Dynamic Time Warping | Algorithm for sequence similarity |
| BLE | Bluetooth Low Energy | Wireless protocol |
| IMU | Inertial Measurement Unit | Accelerometer + gyroscope + magnetometer |
| EMA | Exponential Moving Average | Smoothing filter |
| SUS | System Usability Scale | Usability questionnaire |
| MVVM | Model-View-ViewModel | Architecture pattern |
| GATT | Generic Attribute Profile | BLE data structure |
| UUID | Universally Unique Identifier | BLE characteristic ID |
| I2C | Inter-Integrated Circuit | Arduino communication protocol |
| UART | Universal Asynchronous Receiver-Transmitter | Serial protocol |

---

## Appendice I: File Structure Reference

```
VBTTracker/
├── VBTTracker/
│   ├── Models/
│   │   ├── Exercise.swift           (Exercise catalog, velocity ranges)
│   │   ├── TrainingSession.swift    (Session data model)
│   │   └── CalibrationData.swift    (Sensor calibration)
│   │
│   ├── Managers/
│   │   ├── SessionManager.swift         (Main session orchestration)
│   │   ├── BLEManager.swift             (WitMotion Bluetooth)
│   │   ├── USBManager.swift             (Arduino USB serial)
│   │   ├── ExerciseManager.swift        (Exercise catalog)
│   │   ├── SettingsManager.swift        (App settings)
│   │   ├── DistanceBasedRepDetector.swift  (Arduino algorithm)
│   │   └── VBTRepDetector.swift         (WitMotion DTW algorithm)
│   │
│   ├── Views/
│   │   ├── Training/
│   │   │   ├── TrainingSessionView.swift
│   │   │   ├── RepReviewView.swift
│   │   │   └── TrainingSummaryView.swift
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift
│   │   │   └── SensorConnectionView.swift
│   │   │
│   │   └── History/
│   │       └── HistoryView.swift
│   │
│   └── Utils/
│       ├── Extensions.swift
│       └── Constants.swift
│
├── Arduino/
│   └── VBTTracker/
│       └── VBTTracker.ino          (Firmware)
│
└── tesi/
    ├── README.md
    ├── 01-architettura.md
    ├── 02-algoritmi-rep-detection.md
    ├── 03-sfide-tecniche.md
    ├── 04-implementazione.md
    ├── 05-metriche.md
    ├── 06-conclusioni.md
    ├── 07-bibliografia.md
    └── 08-appendici.md             (this file)
```

**Total Files**: 40+ Swift, 1 C++, 8 Markdown

---

**Fine Appendici**
