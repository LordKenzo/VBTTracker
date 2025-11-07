/*
 * VBT SENSOR Rev5 — FIX NaN velocity
 *
 * FIX CRITICO: Inizializza lastDistance e lastDistanceTime in startTx()
 * per evitare velocità NaN nei primi campioni che si propagano in EMA/median.
 *
 * Novità vs Rev4:
 * - Median filter (finestra 5) + EMA sulla velocità
 * - Dead-zone temporale (hold) prima di cambiare stato
 * - All'avvio NESSUNA pubblicizzazione BLE; parte/stop con pulsante
 * - Se fermi, stop advertising e disconnect
 *
 * Packet BLE (11 byte): [0-1] dist mm (LE), [2-5] timestamp ms (LE),
 * [6-9] vel float mm/s (LE), [10] stato (0=IDLE, 1=CONC, 2=ECC)
 */

#include <ArduinoBLE.h>
#include <Wire.h>
#include <VL53L0X.h>
#include <string.h>

// ===== PIN =====
#define LED_RED_PIN    9    // Concentric
#define LED_BLUE_PIN   10   // Eccentric
#define BUTTON_PIN     6

// ===== BLE =====
#define SERVICE_UUID     "19B10000-E8F2-537E-4F6C-D104768A1214"
#define CHAR_SENSOR_UUID "19B10001-E8F2-537E-4F6C-D104768A1214"

BLEService vbtService(SERVICE_UUID);
BLECharacteristic sensorChar(CHAR_SENSOR_UUID, BLERead | BLENotify, 11);

// ===== SENSORI =====
VL53L0X distanceSensor;

// ===== TEMPI E FILTRI =====
const unsigned long SAMPLE_INTERVAL = 20; // 50 Hz
const float ALPHA  = 0.30f;               // EMA velocità
const int   MED_N  = 5;                   // median window
float vBuf[MED_N] = {0};
int   vIdx = 0;
bool  vFilled = false;

// ===== STATI =====
enum MovementState : uint8_t { IDLE = 0, CONCENTRIC = 1, ECCENTRIC = 2 };
MovementState currentState = IDLE;

// ===== SOGLIE E HOLD =====
const float TH_ON  = 120.0f;  // entra in stato oltre questa soglia
const float TH_OFF = 80.0f;   // esce dallo stato sotto questa soglia
const unsigned long HOLD_ON_MS  = 60;   // tempo minimo oltre TH_ON per entrare (≈3 campioni)
const unsigned long HOLD_OFF_MS = 120;  // tempo minimo in dead-zone per tornare a IDLE

// +1 se in concentrica la distanza AUMENTA (panca: sensore a terra o bilanciere->pavimento)
// -1 se in concentrica la distanza DIMINUISCE (sensore montato sopra che guarda in giù)
const int ORIENTATION_SIGN = +1;

// ===== VARIABILI =====
uint16_t currentDistance = 0, lastDistance = 0;
unsigned long lastDistanceTime = 0;
float currentVelocity = 0.0f;   // mm/s
float vEMA = 0.0f;

unsigned long lastSampleTime = 0;
unsigned long lastPrintTime  = 0;
const unsigned long PRINT_INTERVAL = 500;

bool lastButtonState = HIGH;
bool isSendingData = false;   // controlla pubblicizzazione/notify
bool isAdvertising = false;
bool isConnected = false;

byte dataPacket[11];

// ===== HOLD TIMERS =====
unsigned long sinceOverPos = 0;  // tempo cumulato oltre +TH_ON
unsigned long sinceOverNeg = 0;  // tempo cumulato sotto -TH_ON
unsigned long sinceInDead  = 0;  // tempo cumulato entro [-TH_OFF, +TH_OFF]

/* ---------- PROTOTIPI ---------- */
void checkButton();
void startTx();
void stopTx();
void readSensors();
void calculateVelocity();
float median5();
void updateStateFromVelocity();
void updateLEDs();
void bleTickAndSend();
void printDebugInfo();

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(LED_RED_PIN, OUTPUT);
  pinMode(LED_BLUE_PIN, OUTPUT);
  digitalWrite(LED_RED_PIN, LOW);
  digitalWrite(LED_BLUE_PIN, LOW);

  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // ToF
  Wire.begin();
  distanceSensor.setTimeout(500);
  if (!distanceSensor.init()) {
    Serial.println("Errore inizializzazione VL53L0X");
    while (1);
  }
  // Budget < intermeasurement (14ms < 20ms)
  distanceSensor.setMeasurementTimingBudget(14000);
  distanceSensor.startContinuous(20);

  currentDistance = distanceSensor.readRangeContinuousMillimeters();
  if (distanceSensor.timeoutOccurred()) currentDistance = 0;
  lastDistance = currentDistance;
  lastDistanceTime = millis();

  // BLE (NON pubblicizzo finché non premi)
  if (!BLE.begin()) {
    Serial.println("Errore inizializzazione BLE");
    while (1);
  }
  BLE.setLocalName("VBT-Sensor-Rev5");
  BLE.setDeviceName("VBT-Sensor-Rev5");
  BLE.setAdvertisedService(vbtService);
  vbtService.addCharacteristic(sensorChar);
  BLE.addService(vbtService);
  // niente BLE.advertise() qui

  Serial.println("===== VBT SENSOR Rev5 - NaN FIX =====");
  Serial.println("No-Advert finché non premi il pulsante");
  Serial.print("ORIENTATION_SIGN = ");
  Serial.println(ORIENTATION_SIGN);
}

void loop() {
  const unsigned long now = millis();

  checkButton();

  if ((now - lastSampleTime) >= SAMPLE_INTERVAL) {
    lastSampleTime = now;

    readSensors();
    calculateVelocity();
    updateStateFromVelocity();
    updateLEDs();
    bleTickAndSend(); // invia SOLO se avviato + connesso
  }

  if ((now - lastPrintTime) >= PRINT_INTERVAL) {
    lastPrintTime = now;
    printDebugInfo();
  }
}

/* ---------- BUTTON / TX CONTROL ---------- */
void checkButton() {
  bool curr = digitalRead(BUTTON_PIN);
  if (lastButtonState == HIGH && curr == LOW) {
    delay(50);
    if (digitalRead(BUTTON_PIN) == LOW) {
      if (!isSendingData) startTx();
      else                stopTx();
    }
  }
  lastButtonState = curr;
}

void startTx() {
  isSendingData = true;

  // ✅ FIX CRITICO: Leggi distanza corrente per inizializzare correttamente
  currentDistance = distanceSensor.readRangeContinuousMillimeters();
  if (distanceSensor.timeoutOccurred() || currentDistance >= 2000) {
    currentDistance = 300; // valore di default ragionevole
  }

  // ✅ Inizializza lastDistance e lastDistanceTime PRIMA del primo campione
  // Questo previene NaN nel calcolo della velocità al primo campione
  lastDistance = currentDistance;
  lastDistanceTime = millis();

  // reset filtri/hold per uno start pulito
  vEMA = 0.0f;
  for (int i=0;i<MED_N;i++) vBuf[i]=0.0f;
  vIdx=0;
  vFilled=false;
  sinceOverPos = sinceOverNeg = sinceInDead = 0;
  currentState = IDLE;
  currentVelocity = 0.0f;  // ✅ Reset anche la velocità

  if (!isAdvertising) {
    BLE.advertise();
    isAdvertising = true;
  }

  Serial.println(">>> TX START: advertising ON");
  Serial.print(">>> Distanza iniziale: ");
  Serial.print(currentDistance);
  Serial.println(" mm");
  digitalWrite(LED_BLUE_PIN, HIGH); delay(120); digitalWrite(LED_BLUE_PIN, LOW);
}

void stopTx() {
  isSendingData = false;

  // se connesso, forza disconnessione
  if (isConnected) {
    BLE.disconnect();
    isConnected = false;
  }
  // stop advertising
  if (isAdvertising) {
    BLE.stopAdvertise();
    isAdvertising = false;
  }

  Serial.println(">>> TX STOP: advertising OFF");
  digitalWrite(LED_RED_PIN, HIGH); delay(120); digitalWrite(LED_RED_PIN, LOW);
}

/* ---------- SENSORI / VELOCITÀ ---------- */
void readSensors() {
  uint16_t d = distanceSensor.readRangeContinuousMillimeters();
  if (distanceSensor.timeoutOccurred() || d >= 2000) d = lastDistance;
  currentDistance = d;
}

void calculateVelocity() {
  unsigned long tNow = millis();
  unsigned long dt = tNow - lastDistanceTime;

  float v = 0.0f;
  if (dt > 0) {
    int deltaD = (int)currentDistance - (int)lastDistance;
    v = (float)deltaD / (float)dt * 1000.0f; // mm/s
  }

  // ema
  vEMA = ALPHA * v + (1.0f - ALPHA) * vEMA;

  // median buffer (aggiorna dopo EMA, così mediana su segnale già pulito)
  vBuf[vIdx] = vEMA;
  vIdx = (vIdx + 1) % MED_N;
  if (vIdx == 0) vFilled = true;

  currentVelocity = median5(); // usa mediana come valore "decisionale"

  lastDistance = currentDistance;
  lastDistanceTime = tNow;
}

float median5() {
  float tmp[MED_N];
  int n = vFilled ? MED_N : vIdx; // primi campioni: usa quanti ce ne sono
  if (n == 0) return 0.0f;

  for (int i=0;i<n;i++) tmp[i]=vBuf[i];
  // selection sort parziale per trovare la mediana
  for (int i=0;i<=n/2;i++) {
    int minIdx = i;
    for (int j=i+1;j<n;j++) if (tmp[j] < tmp[minIdx]) minIdx=j;
    float sw = tmp[i]; tmp[i]=tmp[minIdx]; tmp[minIdx]=sw;
  }
  return tmp[n/2];
}

/* ---------- LOGICA STATI con HOLD ---------- */
void updateStateFromVelocity() {
  const unsigned long dt = SAMPLE_INTERVAL; // ~20 ms fisso
  const float v = ORIENTATION_SIGN * currentVelocity;

  const bool overPos = (v >  TH_ON);
  const bool overNeg = (v < -TH_ON);
  const bool inDead  = (v > -TH_OFF && v < TH_OFF);

  switch (currentState) {
    case IDLE:
      if (overPos) {
        sinceOverPos += dt;
        sinceOverNeg = 0;
        sinceInDead  = 0;
        if (sinceOverPos >= HOLD_ON_MS) {
          currentState = CONCENTRIC;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else if (overNeg) {
        sinceOverNeg += dt;
        sinceOverPos = 0;
        sinceInDead  = 0;
        if (sinceOverNeg >= HOLD_ON_MS) {
          currentState = ECCENTRIC;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else {
        // oscillazioni piccole restano IDLE
        sinceInDead += dt;
        sinceOverPos = sinceOverNeg = 0;
      }
      break;

    case CONCENTRIC:
      if (inDead) {
        sinceInDead += dt;
        if (sinceInDead >= HOLD_OFF_MS) {
          currentState = IDLE;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else if (overNeg) {
        // inversione netta: serve superare soglia opposta per un po'
        sinceOverNeg += dt;
        sinceOverPos = sinceInDead = 0;
        if (sinceOverNeg >= HOLD_ON_MS) {
          currentState = ECCENTRIC;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else {
        // ancora sopra soglia positiva -> reset contatori dead
        sinceOverPos += dt;
        sinceInDead = sinceOverNeg = 0;
      }
      break;

    case ECCENTRIC:
      if (inDead) {
        sinceInDead += dt;
        if (sinceInDead >= HOLD_OFF_MS) {
          currentState = IDLE;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else if (overPos) {
        sinceOverPos += dt;
        sinceOverNeg = sinceInDead = 0;
        if (sinceOverPos >= HOLD_ON_MS) {
          currentState = CONCENTRIC;
          sinceOverPos = sinceOverNeg = sinceInDead = 0;
        }
      } else {
        sinceOverNeg += dt;
        sinceInDead = sinceOverPos = 0;
      }
      break;
  }
}

/* ---------- LED ---------- */
void updateLEDs() {
  switch (currentState) {
    case CONCENTRIC: digitalWrite(LED_RED_PIN, HIGH);  digitalWrite(LED_BLUE_PIN, LOW);  break;
    case ECCENTRIC:  digitalWrite(LED_RED_PIN, LOW);   digitalWrite(LED_BLUE_PIN, HIGH); break;
    default:         digitalWrite(LED_RED_PIN, LOW);   digitalWrite(LED_BLUE_PIN, LOW);  break;
  }
}

/* ---------- BLE TICK & SEND ---------- */
void bleTickAndSend() {
  // Se non è stato avviato, non facciamo advertising né TX
  if (!isSendingData) return;

  BLEDevice central = BLE.central(); // valido solo se advertising
  if (central) {
    if (!isConnected) {
      isConnected = true;
      Serial.println(">>> Dispositivo connesso");
    }

    // 0-1: distanza
    dataPacket[0] = (currentDistance >> 0) & 0xFF;
    dataPacket[1] = (currentDistance >> 8) & 0xFF;

    // 2-5: timestamp
    unsigned long ts = millis();
    dataPacket[2] = (ts >> 0) & 0xFF;
    dataPacket[3] = (ts >> 8) & 0xFF;
    dataPacket[4] = (ts >> 16) & 0xFF;
    dataPacket[5] = (ts >> 24) & 0xFF;

    // 6-9: velocità
    float v = currentVelocity;
    memcpy(&dataPacket[6], &v, sizeof(float));

    // 10: stato
    dataPacket[10] = static_cast<uint8_t>(currentState);

    sensorChar.writeValue(dataPacket, 11);
  } else if (isConnected) {
    isConnected = false;
    Serial.println(">>> Dispositivo disconnesso");
  }
}

/* ---------- DEBUG ---------- */
void printDebugInfo() {
  Serial.print("D: ");
  Serial.print(currentDistance);
  Serial.print(" mm | V: ");
  Serial.print(currentVelocity, 1);
  Serial.print(" mm/s | Stato: ");
  switch (currentState) {
    case CONCENTRIC: Serial.print("Concentrica"); break;
    case ECCENTRIC:  Serial.print("Eccentrica");  break;
    default:         Serial.print("Idle");        break;
  }
  Serial.print(" | TX: ");
  Serial.print(isSendingData ? "ON" : "OFF");
  Serial.print(" | ADV: ");
  Serial.println(isAdvertising ? "ON" : "OFF");
}
