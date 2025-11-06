/*
 * VBT SENSOR Rev3 — SEMPLIFICATO (Calcolo stato dalla velocità)
 *
 * MODIFICHE RISPETTO A Rev2:
 * ✅ Rimosso sistema di campioni consecutivi (causava stato=IDLE sempre)
 * ✅ Stato calcolato DIRETTAMENTE dalla velocità (soglia 100mm/s)
 * ✅ Rimossa caratteristica BLE configChar (non serve più)
 * ✅ Codice più semplice e affidabile
 *
 * Trasmissione: distanza (2 byte), timestamp (4 byte), velocità (4 byte float), stato (1 byte)
 * Pulsante per avviare/fermare l'invio dei dati
 */

// ===== LIBRERIE =====
#include <ArduinoBLE.h>
#include <Wire.h>
#include <VL53L0X.h>

// ===== PIN =====
#define LED_RED_PIN    9   // Avvicinamento (concentrica)
#define LED_BLUE_PIN   10  // Allontanamento (eccentrica)
#define BUTTON_PIN     6   // Pulsante per avviare/fermare l'invio dei dati

// ===== BLE =====
#define SERVICE_UUID        "19B10000-E8F2-537E-4F6C-D104768A1214"
#define CHAR_SENSOR_UUID    "19B10001-E8F2-537E-4F6C-D104768A1214"

BLEService vbtService(SERVICE_UUID);
BLECharacteristic sensorChar(CHAR_SENSOR_UUID, BLERead | BLENotify, 11);  // 11 byte: no config byte

// ===== SENSORI =====
VL53L0X distanceSensor;

// ===== VARIABILI GLOBALI =====
uint16_t currentDistance = 0, lastDistance = 0;
unsigned long lastDistanceTime = 0;
float currentVelocity = 0.0;
const unsigned long SAMPLE_INTERVAL = 20;   // 50Hz
unsigned long lastSampleTime = 0;
bool isConnected = false, vl53l0xReady = false;
byte dataPacket[11];  // Ridotto a 11 byte (no config)
bool isSendingData = false;  // Flag per controllare se inviare i dati
bool lastButtonState = HIGH; // Stato precedente del pulsante
unsigned long lastPrintTime = 0;
const unsigned long PRINT_INTERVAL = 500;   // Intervallo di stampa sul monitor seriale (ms)

// ===== STATI =====
enum MovementState { APPROACHING, RECEDING, IDLE };
MovementState currentState = IDLE;

// ===== SOGLIA VELOCITÀ =====
const float VELOCITY_THRESHOLD = 100.0;  // mm/s - deve corrispondere all'app Swift!

// ===== SETUP =====
void setup() {
    Serial.begin(115200);
    delay(200);

    // Configurazione pin LED
    pinMode(LED_RED_PIN, OUTPUT);
    pinMode(LED_BLUE_PIN, OUTPUT);
    digitalWrite(LED_RED_PIN, LOW);
    digitalWrite(LED_BLUE_PIN, LOW);

    // Configurazione pin pulsante
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    // ToF
    Wire.begin();
    distanceSensor.setTimeout(500);
    if (!distanceSensor.init()) {
        Serial.println("Errore inizializzazione VL53L0X");
        while (1);
    }
    distanceSensor.setMeasurementTimingBudget(20000);
    currentDistance = distanceSensor.readRangeSingleMillimeters();
    lastDistance = currentDistance;
    lastDistanceTime = millis();
    vl53l0xReady = true;

    // BLE
    if (!BLE.begin()) {
        Serial.println("Errore inizializzazione BLE");
        while (1);
    }
    BLE.setLocalName("VBT-Sensor-Rev3");
    BLE.setDeviceName("VBT-Sensor-Rev3");
    BLE.setAdvertisedService(vbtService);
    vbtService.addCharacteristic(sensorChar);
    BLE.addService(vbtService);

    BLE.advertise();

    Serial.println("===== VBT SENSOR Rev3 - SEMPLIFICATO =====");
    Serial.println("Stato calcolato dalla velocità (soglia 100mm/s)");
    Serial.println("Sensore pronto");
}

// ===== LOOP =====
void loop() {
    const unsigned long now = millis();

    // Controlla il pulsante
    checkButton();

    if (isSendingData) {
        if (now - lastSampleTime >= SAMPLE_INTERVAL) {
            lastSampleTime = now;
            readSensors();
            calculateVelocity();
            updateStateFromVelocity();  // ✅ Nuovo metodo semplificato!
            updateLEDs();
            sendDataViaBLE();
        }
    }

    // Stampa i dati sul monitor seriale
    if (now - lastPrintTime >= PRINT_INTERVAL) {
        lastPrintTime = now;
        printDebugInfo();
    }
}

// ===== STAMPA DATI SUL MONITOR SERIALE =====
void printDebugInfo() {
    Serial.print("Distanza: ");
    Serial.print(currentDistance);
    Serial.print(" mm | Velocità: ");
    Serial.print(currentVelocity, 1);
    Serial.print(" mm/s | Stato: ");

    switch (currentState) {
        case APPROACHING:
            Serial.print("Concentrica (approaching)");
            break;
        case RECEDING:
            Serial.print("Eccentrica (receding)");
            break;
        default:
            Serial.print("Idle");
    }

    Serial.print(" | Invio: ");
    Serial.println(isSendingData ? "ATTIVO" : "DISATTIVO");
}

// ===== CONTROLLO PULSANTE =====
void checkButton() {
    bool currentButtonState = digitalRead(BUTTON_PIN);

    // Rileva il fronte di discesa (premuto)
    if (lastButtonState == HIGH && currentButtonState == LOW) {
        delay(50); // Debounce
        if (digitalRead(BUTTON_PIN) == LOW) {
            isSendingData = !isSendingData;  // Cambia lo stato
            if (isSendingData) {
                Serial.println(">>> Invio dati AVVIATO");
                // Lampeggia blu per conferma
                digitalWrite(LED_BLUE_PIN, HIGH);
                delay(200);
                digitalWrite(LED_BLUE_PIN, LOW);
            } else {
                Serial.println(">>> Invio dati FERMATO");
                // Lampeggia rosso per conferma
                digitalWrite(LED_RED_PIN, HIGH);
                delay(200);
                digitalWrite(LED_RED_PIN, LOW);
            }
        }
    }
    lastButtonState = currentButtonState;
}

// ===== LETTURA SENSORI =====
void readSensors() {
    if (vl53l0xReady) {
        uint16_t d = distanceSensor.readRangeSingleMillimeters();
        if (distanceSensor.timeoutOccurred() || d >= 2000) {
            d = lastDistance;  // Mantieni ultimo valore valido
        }
        currentDistance = d;
    }
}

// ===== CALCOLO VELOCITÀ =====
void calculateVelocity() {
    unsigned long currentTime = millis();
    unsigned long deltaTime = currentTime - lastDistanceTime;

    if (deltaTime > 0) {
        int deltaDistance = currentDistance - lastDistance;
        currentVelocity = (float)deltaDistance / (float)deltaTime; // Velocità in mm/ms
        currentVelocity *= 1000.0; // Converti in mm/s
    } else {
        currentVelocity = 0.0;
    }

    lastDistance = currentDistance;
    lastDistanceTime = currentTime;
}

// ===== CALCOLO STATO DALLA VELOCITÀ (SEMPLIFICATO!) =====
void updateStateFromVelocity() {
    // ✅ LOGICA SEMPLICE: usa solo la velocità, niente campioni consecutivi!

    if (currentVelocity < -VELOCITY_THRESHOLD) {
        // Velocità negativa = si avvicina al sensore = CONCENTRICA
        currentState = APPROACHING;
    }
    else if (currentVelocity > VELOCITY_THRESHOLD) {
        // Velocità positiva = si allontana dal sensore = ECCENTRICA
        currentState = RECEDING;
    }
    else {
        // Velocità bassa = FERMO
        currentState = IDLE;
    }
}

// ===== AGGIORNAMENTO LED =====
void updateLEDs() {
    // Aggiorna i LED in base allo stato corrente
    switch (currentState) {
        case APPROACHING:
            digitalWrite(LED_RED_PIN, HIGH);   // Rosso = concentrica
            digitalWrite(LED_BLUE_PIN, LOW);
            break;
        case RECEDING:
            digitalWrite(LED_RED_PIN, LOW);
            digitalWrite(LED_BLUE_PIN, HIGH);  // Blu = eccentrica
            break;
        case IDLE:
            digitalWrite(LED_RED_PIN, LOW);
            digitalWrite(LED_BLUE_PIN, LOW);   // Nessun LED = idle
            break;
    }
}

// ===== INVIO DATI VIA BLE =====
void sendDataViaBLE() {
    BLEDevice central = BLE.central();
    if (central) {
        if (!isConnected) {
            isConnected = true;
            Serial.println(">>> Dispositivo connesso");
        }

        // Byte 0-1: Distanza (2 byte, little-endian)
        dataPacket[0] = (currentDistance >> 0) & 0xFF;
        dataPacket[1] = (currentDistance >> 8) & 0xFF;

        // Byte 2-5: Timestamp (4 byte, little-endian)
        unsigned long timestamp = millis();
        dataPacket[2] = (timestamp >> 0) & 0xFF;
        dataPacket[3] = (timestamp >> 8) & 0xFF;
        dataPacket[4] = (timestamp >> 16) & 0xFF;
        dataPacket[5] = (timestamp >> 24) & 0xFF;

        // Byte 6-9: Velocità (4 byte float, little-endian)
        float velocity = currentVelocity;
        memcpy(&dataPacket[6], &velocity, sizeof(float));

        // Byte 10: Stato del movimento (1 byte)
        dataPacket[10] = static_cast<uint8_t>(currentState);

        // ✅ NO CONFIG BYTE - non serve più!

        // Invia i dati (11 byte totali)
        sensorChar.writeValue(dataPacket, 11);
    } else if (isConnected) {
        isConnected = false;
        Serial.println(">>> Dispositivo disconnesso");
    }
}
