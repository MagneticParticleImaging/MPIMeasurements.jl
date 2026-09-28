// #include <cstdint>
/*
 * communicationWithTMAG5170.h - Bibliothek, um über einen Arduino
 * mit dem 3-achsigen Hallsensor TMAG5170 zu kommunizieren
 * 03/2024
 */

#ifndef communicationWithTMAG5170_h
#define communicationWithTMAG5170_h

#include "Arduino.h"
// #include <array>


#if false
  #define SERIAL SerialUSB
#else 
  #define SERIAL Serial
#endif

// Write helpers that prevent USB CDC buffer overflows on native ports.
void serialWriteChunked(const uint8_t *data, size_t len, size_t chunkSize = 32);
void serialWriteChunked(const void *data, size_t len, size_t chunkSize = 32);
void sendSyntheticDiagnosticFrame();

// Registernamen (0x0 -> Register schreiben; 0x8 -> Register auslesen)
#define X_REG 0x89
#define Y_REG 0x8A
#define Z_REG 0x8B
#define T_REG 0x8C
#define DEV_CONF_REG 0x00
#define SYS_CONF_REG 0x02
#define SENS_CONF_REG 0x01
#define TEST_CONF_REG 0x0F
#define AFE_STAT_REG 0x8D
#define SYS_STAT_REG 0x8E
#define CONV_STAT_REG 0x88
#define OSC_REG 0x90

// Definierte Fehlerausgaben 
#define SUCCESS "F1" //erfolgreich 
#define ERROR_NUMBER_OF_ARGS "F2" //falsche Anzahl an Argumenten in command
#define ERROR_WRITE "F3" //Fehler beim Prüfen der write-Funktion 
#define ERROR_INVALID_ARG "F4" //ungültiges Argument in command
#define ERROR_CHANNEL_DISABLED "F5" //gewünschter Kanal nicht freigeschaltet
#define ERROR_OSCI "F6" //Fehler beim Oszillator-Check 
// Fehler aus Statusregistern 
#define F7 "F7" //CONVERSION ERROR - Conversion data not valid
#define F8 "F8" //CONVERSION ERROR - Temperature data not current
#define F9 "F9" //CONVERSION ERROR - Z-Channel data not current 
#define F10 "F10" //CONVERSION ERROR - Y-Channel data not current
#define F11 "F11" //CONVERSION ERROR - X-Channel data not current
#define F12 "F12" //AFE ERROR - Power down or brown-out
#define F13 "F13" //AFE ERROR - sensor diagnostic test failed
#define F14 "F14" //AFE ERROR - temperature sensor diagnostic test failed 
#define F15 "F15" //AFE ERROR - z-axis sensor diagnostic test failed
#define F16 "F16" //AFE ERROR - y-axis sensor diagnostic test failed
#define F17 "F17" //AFE ERROR - x-axis sensor diagnostic test failed
#define F18 "F18" //AFE ERROR - trim data error
#define F19 "F19" //AFE ERROR - fault in internal LDO supplied power
#define F20 "F20" //SYSTEM ERROR - SDO drive error detected
#define F21 "F21" //SYSTEM ERROR - CRC Error
#define F22 "F22" //SYSTEM ERROR - Incorrect number of clocks detected for a SPI transaction
#define F23 "F23" //SYSTEM ERROR - VCC over-voltage
#define F24 "F24" //SYSTEM ERROR - VCC under-voltage
// einzelne Hinweise für Config Funktionen 
#define F25 "F25" //Modus nicht implementiert. Konfiguriere Single Device erneut mit operatingMode = 0x2
#define F26 "F26" //Die Range aller drei Achsen muss gleich sein
#define F27 "F27" //Mindestens ein Kanal muss freigeschaltet sein
#define F28 "F28" //die gewünschte Range passt nicht zur aktuellen Initialisierung, Sensoren müssen passend Initialisiert werden


// ====
// Hilfsfunktionen zum Verarbeiten der Befehle 
// ====

/*
 * @details Funktion um Argumente als Strings in Integer zu wandeln
 * @param[in] String str: Argument als String 
 * @return bool result: in Integer umgewandeltes Argument 
 */
int convertStringToInt(String str);
/*
 * @details Funktion zum Testen der convertStringToInt Funktion 
 * @return void 
 */
void TESTconvertStringToInt();
/*
 * @details Funktion sucht Position eines Chars/Zeichens in einem String
 * @param[in] char str[]: String, in dem nach Zeichen gesucht wird 
 * @param[in] char finde: Zeichen, was gesucht wird
 * @return int position: Position des Zeichens oder -1, wenn nicht vorhanden 
 */
int getCharsPosition(char str[], char finde);
/*
 * @details Funktion zum Testen der getCharsPosition Funktion 
 * @return void 
 */
void TESTgetCharsPosition();
/*
 * @details Funktion prüft, ob eine Zeichenkette mit einer anderen, kürzeren Zeichenkette beginnt 
 * @param[in] const char *str: String, dessen Anfang mit anderem String verglichen wird 
 * @param[in] const char *with: String, der mit Anfang von anderem String verglichen wird 
 * @return bool result: true, wenn str mit with beginnt; sonst false 
 */
bool commandBeginsWith(const char *str, const char *with);
/*
 * @details Funktion zum Testen der commandBeginsWith Funktion 
 * @return void 
 */
void TESTcommandBeginsWith();
/*
 * @details Funktion gibt Anzahl der Elemente in einem Kommando zurück
 * @param[in] const char *cmd: Kommando, dessen Elemente gezählt werden
 * @return int noOfArguments: Anzahl der Elemente im Kommando  
 */
int numberOfArgumentsInCommand(const char *cmd);
/*
 * @details Funktion zum Testen der numberOfArgumentsInCommand Funktion 
 * @return void 
 */
void TESTnumberOfArgumentsInCommand();
/*
 * @details Funktion trennt Befehl von Argumenten und splittet Argumente auf 
  * Aufruf vorzugsweise: 
  * if (numberOfArgumentsInCommand(command)> 0){
  *   String *args;
  *   args = splitCommand(command);
  * }
  * int x = convertStringToInt(args[0]); 
  * delete[] args;
 * @param[in] const char *cmd: Kommando, dessen Argumente extrahiert werden sollen
 * @return String[noOfArguments]: Vektor aus Strings mit den einzelnen Argumenten
 */
String * splitCommand(const char *cmd);
/*
 * @details Funktion zum Testen der splitCommand Funktion 
 * @return void 
 */
void TESTsplitCommand();

// ====
// Funktionen, zur Kommunikation mit TMAG5170
// ====

/*
 * @details Funktion zum Schreiben von Daten in ein Register 
 * @param[in] byte registerName: Index des Registers, in welches geschrieben wird
 * @param[in] int16_t data: Daten, die in Register geschrieben werden
 * @param[in] byte CMD_CRC: zuvor berechnete CRC Bits und Command Bits
 * @return bool test: true wenn kein Fehler beim schreiben; false wenn Fehler
 */
bool writeRegister(byte registerName, int16_t data, byte CMD_CRC);
/*
 * @details Funktion zum Lesen von Daten aus einem Register 
 * @param[in] byte registerName: Index des Registers, aus welchem gelesen wird
 * @param[in] int16_t data: Daten, die in Register geschrieben werden
 * @param[in] byte CMD_CRC: zuvor berechnete CRC Bits und Command Bits
 * @return void 
 */
int16_t readRegister(byte registerName, int16_t data, byte CMD_CRC);
/*
 * @details Funktion zum Testen der writeRegister und readRegister Funktionen
 * @return void 
 */
void TESTwriteRead();
/*
 * @details Funktion, um die 4 CRC Bits für die CRC Prüfung zu berechnen
 * @param[in] byte registerName: Index des Registers, wofür der CRC Wert berechnet wird
 * @param[in] int16_t data: Daten, die in Register geschrieben werden 
 * @param[in] byte CMD_CRC: CMD Byte, die ersten 4 sind Command Bits
 * @return uint8_t: 8 Bit Integer, bei welchem die letzten 4 Bits der CRC Wert sind und die ersten 4 Command Bits
 */
uint8_t calculateCRC(byte registerName, int16_t data, byte CMD_CRC);
/*
 * @details Funktion zum Testen der calculateCRC Funktion
 * @return void 
 */
void TESTCRC();
/*
 * @details Funktion, die je nach gewünschter Einstellung die entsprechenden Bits im Register setzt
 * @param[in] int16_t data: Variable, in der Bits gesetzt werden, um sie in Register zu schreiben
 * @param[in] byte begin: Index des ersten zu setzenden Bits (Bits werden von links nach rechts von 15 bis 0 runter gezählt)
 * @param[in] byte end: Index des letzten zu setzenden Bits  
 * @param[in] byte value: Wert, der in den Bits von begin bis end stehen soll
 * @return int16_t data: Datenvariable mit neu gesetzen Bits 
 */
int16_t setBits(int16_t data, byte begin, byte end, byte value);
/*
 * @details Funktion zum Testen der setBit Funktion
 * @return void 
 */
void TESTsetBits();
/*
 * @details Funktion, die alle Bits einer 16Int Variable ausliest und in Vektor speichert
 * @param[in] int16_t data: Variable, dessen Bits gelesen werden sollen
 * @return bool allBits[16]: Vektor mit 16 Einträgen (für jedes Bit ein Index)
 * @note Index wird von 15 bis 0 von links nach rechts gezählt
 * @note nach Verarbeitung der Bits zwingend delete[] allBits nötig 
 */
bool *getBits(int16_t data);
/*
 * @details Funktion zum Testen der getBits Funktion
 * @return void 
 */
void TESTgetBits();
/*
 * @details Funktion, um aus Messwert des Sensors die korrekte magnetische Flussdichte zu berechnen  
 * @param[in] int16_t messwert: Daten, die von Hallsensor gemessen wurden
 * @return float ergebnis: Ergbenis der magnetischen Flussdichte in mT 
 */
float flussdichte(int16_t messwert);
/*
 * @details Funktion zum Testen der flussdichte Funktion
 * @return void 
 */
void TESTflussdichte();
/*
 * @details Funktion zum Auslesen des Conversion Status Registers 
 * @return String: Fehler- oder Erfolgsmeldung 
 * @note F7 = CONVERSION ERROR - Conversion data not valid
 * @note F8 = CONVERSION ERROR - Temperature data not current
 * @note F9 = CONVERSION ERROR - Z-Channel data not current 
 * @note F10 = CONVERSION ERROR - Y-Channel data not current
 * @note F11 = CONVERSION ERROR - X-Channel data not current
 */
String convStat();
/*
 * @details Funktion zum Auslesen des AFE Status Registers 
 * @return String: Fehler- oder Erfolgsmeldung 
 * @note F12 = AFE ERROR - Power down or brown-out
 * @note F13 = AFE ERROR - sensor diagnostic test failed
 * @note F14 = AFE ERROR - temperature sensor diagnostic test failed 
 * @note F15 = AFE ERROR - z-axis sensor diagnostic test failed
 * @note F16 = AFE ERROR - y-axis sensor diagnostic test failed
 * @note F17 = AFE ERROR - x-axis sensor diagnostic test failed
 * @note F18 = AFE ERROR - trim data error
 * @note F19 = AFE ERROR - fault in internal LDO supplied power
 */
String afeStat();
/*
 * @details Funktion zum Auslesen des System Status Registers 
 * @return String: Fehler- oder Erfolgsmeldung 
 * @note F20 = SYSTEM ERROR - SDO drive error detected
 * @note F21 = SYSTEM ERROR - CRC Error
 * @note F22 = SYSTEM ERROR - Incorrect number of clocks detected for a SPI transaction
 * @note F23 = SYSTEM ERROR - VCC over-voltage
 * @note F24 = SYSTEM ERROR - VCC under-voltage
 */
String sysStat();

// ====
// Funktionen, die mit Julia aufgerufen werden können
// ====
// Funktionen die keine Ausgabe haben (also ein typisches return 0),
// müssen um die Kommunikationsstruktur zu erhalten trotzdem String mit \r am Ende ausgeben 
// Typische Funktionsdefinitionen
// void funktion(){
//   // führe Dinge aus 
//   Serial.write(SUCCESS"\r\n");
// }
// void funktion(){
//   // führe Dinge aus und gebe Information aus 
//   Serial.write("Daten\r\n");
// }
// ====

/*
 * @details Funktion gibt die als mit Leerzeichen getrennte HEX Identifikationsnummer des Boards zurück 
 * @return String uniqueID: ID des Boards als String 
 */
String returnUniqueID();

/*
 * @details Funktion, um Defaultkonfiguration einzurichten 
 * @param[in] char *data: leer
 * @return String: Erfolgs- oder Fehlermeldung 
 */
String defaultConfig(char *data);
/*
 * @details Funktion zur CRC Konfiguration 
 * @param[in] char *data: onoff          
 * @return String: Erfolgs- oder Fehlermeldung  
 * @note args[0] = onoff 
 * @note onoff = 0x0 / 0b0 -> CRC freischalten
 * @note onoff = 0x1 / 0b1 -> CRC ausschalten
 */  
String crc(char *data);
/*
 * @details Funktion zur Device Konfiguration 
 * @param[in] char *data: Konfigurationsargumente          
 * @return String: Erfolgs- oder Fehlermeldung  
 * @note args[0] = samplesPerConv -> Samples pro Conversion 
 * @note samplesPerConv = 0x0/0b0 -> 1x 
 * @note samplesPerConv = 0x1/0b1 -> 2x
 * @note samplesPerConv = 0x2/0b10 -> 4x
 * @note samplesPerConv= 0x3/0b11 -> 8x
 * @note samplesPerConv = 0x4/0b100 -> 16x
 * @note samplesPerConv = 0x5/0b101 -> 32x
 * @note args[1] = tempCoeff -> Temperaturkompensation je nach Typ des Magnets 
 * @note tempCoeff = 0x0/0b0 -> 0%/°C 
 * @note tempCoeff = 0x1/0b1 -> 0.12%/°C (NdBFe)
 * @note tempCoeff = 0x2/0b10 -> 0.03%/°C (SmCo)
 * @note tempCoeff = 0x3/0b11 -> 0.2%/°C (Ceramic)
 * @note args[2] = operatingMode -> Operating Mode 
 * @note operatingMode = 0x0/0b0 -> Configuration Mode 
 * @note operatingMode = 0x1/0b1 -> Stand-by Mode
 * @note operatingMode = 0x2/0b10 -> Active Measure Mode (continuous)
 * @note operatingMode = 0x3/0b11 -> Active trigger mode 
 * @note operatingMode = 0x4/0b100 -> Wake-up and sleep mode 
 * @note operatingMode = 0x5/0b101 -> Sleep Mode
 * @note operatingMode = 0x6/0b110 -> Deep Sleep Mode 
 * @note args[3] = tempChan -> Temperatur Kanal freischalten oder ausschalten 
 * @note tempChan = 0x0/0b0 -> Temperaturkanal ausgeschaltet
 * @note tempChan = 0x1/0b1 -> Temperaturkanal freigeschaltet
 * @note args[4] = tempRate -> Abtastrate für Temperatursensor 
 * @note tempRate = 0x0/0b0 -> Abtastrate entspricht Rate aus samplesPerConv
 * @note tempRate = 0x1/0b1 -> einmal pro Conversion 
 * @note args[5] = tempLimCheck -> Temperatur Limit Check  
 * @note tempLimCheck = 0x0/0b0 -> Limit Check Off
 * @note tempLimCheck = 0x1/0b1 -> Limit Check On 
 */ 
String singleDeviceConfig(char *data);
/*
 * @details Funktion zur Sensor Konfiguration 
 * @param[in] char *data: Konfigurationsargumente          
 * @return String: Erfolgs- oder Fehlermeldung   
 * @note args[0] = timeBetConvs-> Zeit zwischen den Conversions
 * @note timeBetConvs = 0x0/0b0 -> 1ms
 * @note timeBetConvs = 0x1/0b1 -> 5ms
 * @note timeBetConvs = 0x2/0b10 -> 10ms
 * @note timeBetConvs = 0x3/0b11 -> 15ms
 * @note timeBetConvs = 0x4/0b100-> 20ms
 * @note timeBetConvs = 0x5/0b101 -> 30ms
 * @note timeBetConvs = 0x6/0b110 -> 50ms
 * @note timeBetConvs = 0x7/0b111 -> 100ms
 * @note timeBetConvs = 0x8/0b1000 -> 500ms
 * @note timeBetConvs = 0x9/0b1001 -> 1000ms
 * @note args[1] = magChan -> Magnetfeldsensoren freischalten oder ausschalten 
 * @note magChan = 0x0/0b0 -> alle Achsen ausgeschaltet
 * @note magChan = 0x1/0b1 -> nur x-Achse frei 
 * @note magChan = 0x2/0b10 -> nur y-Achse frei
 * @note magChan = 0x3/0b11 -> x- und y-Achse frei 
 * @note magChan = 0x4/0b100 -> nur z-Achse frei 
 * @note magChan = 0x5/0b101 -> z- und x-Achse frei 
 * @note magChan = 0x6/0b110 -> z- und y-Achse frei 
 * @note magChan = 0x7/0b111 -> z- und x- und y-Achse frei 
 * @note args[2] = zRange -> z-Range 
 * @note zRange = 0x0/0b0 -> +/- 150mT
 * @note zRange = 0x1/0b1 -> +/- 75mT
 * @note zRange = 0x2/0b10 -> +/- 300mT
 * @note args[3] = yRange -> y-Range 
 * @note yRange = 0x0/0b0 -> +/- 150mT
 * @note yRange = 0x1/0b1 -> +/- 75mT
 * @note yRange = 0x2/0b10 -> +/- 300mT
 * @note args[4] = xRange -> x-Range
 * @note xRange = 0x0/0b0 -> +/- 150mT
 * @note xRange = 0x1/0b1 -> +/- 75mT
 * @note xRange = 0x2/0b10 -> +/- 300mT 
 */
String sensConfig(char *data);
/*
 * @details Funktion zur System Konfiguration 
 * @param[in] char *data: Konfigurationsargumente          
 * @return String: Erfolgs- oder Fehlermeldung 
 * @note args[0] = diagMode -> bestimmt Modus für Diagnostik-Tests
 * @note diagMode = 0x0/0b0 -> alle Diagnostiktest laufen gleichzeitig 
 * @note diagMode = 0x1/0b1 -> nur freigeschlatete Diagnostiktests laufen gleichzeitig 
 * @note diagMode = 0x2/0x10 -> alle Diagnostiktests laufen sequentiell 
 * @note diagMode = 0x3/0b11 -> nur freigeschaltete Diagnostiktests laufen sequentiell 
 * @note args[1] = convStart -> legt fest, wann Conversion startet
 * @note convStart = 0x0/0b0 -> Start at SPI command
 * @note convStart = 0x1/0b1 -> Start at ChipSelect pulse 
 * @note args[2] = zLimCheck -> z-Achsen Magnetfeld Limit Check 
 * @note zLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note zLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 * @note args[3] = yLimCheck -> y-Achsen Magnetfeld Limit Check 
 * @note yLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note yLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 * @note args[4] -> x-Achsen Magnetfeld Limit Check
 * @note xLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note xLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 */ 
String sysConfig(char *data);
/*
 * @details Funktion, um aus einem beliebigem Register alle Bits zu lesen 
 * @param[in] char *data: Index des Registers  
 * @return String: Bits im Register oder Fehlermeldung 
 */
String readReg(char *data);
/*
 * @details Funktion, um das Temperaturregister auszulesen 
 * @param[in] char *data: leer   
 * @return String: Temperatur in °C oder Fehlermeldung 
 */
String readTemp(char *data);
/*  
 * @details Funktion, um X-Achse des Sensors in mT auszulesen 
 * @param[in] char *data: leer  
 * @return String: Magnetische Flussdichte entlang der X-Achse in mT oder Fehlermeldung 
 */
String getFieldValueX(char *data);
/*  
 * @details Funktion, um Y-Achse des Sensors in mT auszulesen 
 * @param[in] char *data: leer  
 * @return String: Magnetische Flussdichte entlang der Y-Achse in mT oder Fehlermeldung 
 */
String getFieldValueY(char *data);
/*  
 * @details Funktion, um Z-Achse des Sensors in mT auszulesen 
 * @param[in] char *data: leer  
 * @return String: Magnetische Flussdichte entlang der Z-Achse in mT oder Fehlermeldung 
 */
String getFieldValueZ(char *data);
/*  
 * @details Funktion, um X-Achse des Sensors in mT auszulesen 
 * @param[in] char *data: leer  
 * @return String: Magnetische Flussdichte entlang der X-Achse in mT oder Fehlermeldung 
 */
String getFieldValueXYZ(char *data);
/*
  Ignore all error checks and just read the registers as fast as possible
*/
// std::array<int16_t, 3> getFieldValueXYZFast(char *data);
uint64_t getFieldValueXYZFast(char *data);
/*  
 * @details Funktion, um alle Sensoren zu initislisieren 
 * @param[in] char *data: range   
 * @return String: fehler- oder Erfolgsmeldung 
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 */
String initAllSensorsArduino(char *data);
/*  
 * @details Funktion, um zu prüfen, ob alle Sensoren mit korrekter Range initialisiert sind 
 * @param[in] char *data: range   
 * @return String: fehler- oder Erfolgsmeldung 
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 */
String checkInit(char *data);
/*  
 * @details Funktion mit Schleife, um alle Sensoren vollständig auszulesen
 * @param[in] char *data: range|init
 * @return String: Ergebnis aller Sensoren mit Auslesezeit am Ende oder Fehlermeldung 
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 * @note args[1] = init -> Sensoren initialisieren oder nicht 
 * @note init = 0 -> nicht initialisieren, alle Sensoren sind schon initialisiert 
 * @note init = 1 -> alle Sensoren initialisieren 
 */
String allSensorsArduino(char *data);
/*
 * @details Funktion, um aus dem Conversion Status Register den aktuellen Modus zu lesen 
 * @param[in] char *data: leer
 * @return String: aktueller operating mode oder Fehlermeldung 
 */ 
String operatingMode(char *data);
/*
 * @details Oscillator Integrity Check, um Funktion der integrierten Oszillatoren zu prüfen
 * @param[in] char *data: lowhigh
 * @return String: Erfolgs- oder Fehlermeldung
 * @note args[0] = lowHigh -> Hoch- oder Niedrigfrequenzoszillator wird geprüft
 * @note lowHigh = 0x0/0b0 -> Niedrigfrequenzoszillator
 * @note lowHigh = 0x1/0b1 -> Hochfrequenzoszillator 
 * @note ACHTUNG: nach Oscillator-Check gewünschte CRC Einstellung erneut vornehmen (CRC ON/OFF)
 */
String oscInCheck(char *data);
/*
 * @details Funktion, um aktuelle CRC Einstellungen auszugeben 
 * @param[in] char *data: leer   
 * @return void 
 * @note Name des Befehls: "*SHOWCRCCONFIGS?#"
 */ 
void showCRCConfigs(char *data);
/*
 * @details Funktion, um aktuelle Single Device Einstellungen auszugeben 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*SHOWSINGDEVCONFIGS?#"
 */ 
void showSingDevConfigs(char *data);
/*
 * @details Funktion, um aktuelle Sensor Einstellungen auszugeben 
 * @param[in] char *data: leer 
 * @return void
 * @note Name des Befehls: "*SHOWSENSCONFIGS?#"
 */ 
void showSensConfigs(char *data);
/*
 * @details Funktion, um aktuelle System Einstellungen auszugeben 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*SHOWSYSCONFIGS?#"
 */ 
void showSysConfigs(char *data);
/*
 * @details Funktion, um ChipSelect zu ändert und gewüschten Sensor auszuwählen 
 * @param[in] char *data: index            
 * @return String: Fehler- oder Erfolgsmeldung 
 * @note args[0] = index -> Pin als String in HEX an dem der gewünschte Sensor angeschlossen ist 
 */
String selectChip(char *data);
/*
 * @details Funktion, um Fehler aus vorherigem Durchgang in den Status Registern abzufangen 
 * @param[in] char *data: leer
 * @return String: Erfolgsmeldung nach Durchlauf
 */
String deleteErrors(char *data);
/*
 * @details Funktion, um aktuelle Range der Achsen auszulesen 
 * @param[in] char *data: leer 
 * @return String: range in mT oder Fehlermeldung 
 */
String range(char *data);


// ====
// Funktionen zur Ausgabe der Ergebnisse der vorherigen Funktionen, um Ausgabe mit Julia einzulesen 
// ====

/*
 * @details Funktion, um ID des Arduino Boards zu senden 
 * @param[in] char *data: leer
 * @return void 
 * @note Name des Befehls: "*IDN?#"
 */
void sendIdentification(char *data);
/*
 * @details Funktion, um defaultConfig aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: leer
 * @return void 
 * @note Name des Befehls: "*DEFAULTCONF!#"
 */
void sendDefaultConfig(char *data);
/*
 * @details Funktion, um crc aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: onoff
 * @return void
 * @note Name des Befehls: "*CRC!>ON/OFF#" 
 * @note args[0] = onoff 
 * @note onoff = 0x0 / 0b0 -> CRC freischalten
 * @note onoff = 0x1 / 0b1 -> CRC ausschalten
 */
void sendCRC(char *data);
/*
 * @details Funktion, um singleDeviceConfig aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: Konfigurationsargumente          
 * @return void  
 * @note Name des Befehls: "*SINGDEVCONF!>samplesPerConv|tempCoeff|operatingMode|tempChan|tempRate|tempLimCheck#"
 * @note args[0] = samplesPerConv -> Samples pro Conversion 
 * @note samplesPerConv = 0x0/0b0 -> 1x 
 * @note samplesPerConv = 0x1/0b1 -> 2x
 * @note samplesPerConv = 0x2/0b10 -> 4x
 * @note samplesPerConv= 0x3/0b11 -> 8x
 * @note samplesPerConv = 0x4/0b100 -> 16x
 * @note samplesPerConv = 0x5/0b101 -> 32x
 * @note args[1] = tempCoeff -> Temperaturkompensation je nach Typ des Magnets 
 * @note tempCoeff = 0x0/0b0 -> 0%/°C 
 * @note tempCoeff = 0x1/0b1 -> 0.12%/°C (NdBFe)
 * @note tempCoeff = 0x2/0b10 -> 0.03%/°C (SmCo)
 * @note tempCoeff = 0x3/0b11 -> 0.2%/°C (Ceramic)
 * @note args[2] = operatingMode -> Operating Mode 
 * @note operatingMode = 0x0/0b0 -> Configuration Mode 
 * @note operatingMode = 0x1/0b1 -> Stand-by Mode
 * @note operatingMode = 0x2/0b10 -> Active Measure Mode (continuous)
 * @note operatingMode = 0x3/0b11 -> Active trigger mode 
 * @note operatingMode = 0x4/0b100 -> Wake-up and sleep mode 
 * @note operatingMode = 0x5/0b101 -> Sleep Mode
 * @note operatingMode = 0x6/0b110 -> Deep Sleep Mode 
 * @note args[3] = tempChan -> Temperatur Kanal freischalten oder ausschalten 
 * @note tempChan = 0x0/0b0 -> Temperaturkanal ausgeschaltet
 * @note tempChan = 0x1/0b1 -> Temperaturkanal freigeschaltet
 * @note args[4] = tempRate -> Abtastrate für Temperatursensor 
 * @note tempRate = 0x0/0b0 -> Abtastrate entspricht Rate aus samplesPerConv
 * @note tempRate = 0x1/0b1 -> einmal pro Conversion 
 * @note args[5] = tempLimCheck -> Temperatur Limit Check  
 * @note tempLimCheck = 0x0/0b0 -> Limit Check Off
 * @note tempLimCheck = 0x1/0b1 -> Limit Check On 
 */ 
void sendSingleDeviceConfig(char *data);
/*
 * @details Funktion, um sensorConfig aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: Konfigurationsargumente          
 * @return void
 * @note Name des Befehls: "*SENSCONF!>timeBetConvs|magChan|zRange|yRange|xRange#"
 * @note args[0] = timeBetConvs-> Zeit zwischen den Conversions
 * @note timeBetConvs = 0x0/0b0 -> 1ms
 * @note timeBetConvs = 0x1/0b1 -> 5ms
 * @note timeBetConvs = 0x2/0b10 -> 10ms
 * @note timeBetConvs = 0x3/0b11 -> 15ms
 * @note timeBetConvs = 0x4/0b100-> 20ms
 * @note timeBetConvs = 0x5/0b101 -> 30ms
 * @note timeBetConvs = 0x6/0b110 -> 50ms
 * @note timeBetConvs = 0x7/0b111 -> 100ms
 * @note timeBetConvs = 0x8/0b1000 -> 500ms
 * @note timeBetConvs = 0x9/0b1001 -> 1000ms
 * @note args[1] = magChan -> Magnetfeldsensoren freischalten oder ausschalten 
 * @note magChan = 0x0/0b0 -> alle Achsen ausgeschaltet
 * @note magChan = 0x1/0b1 -> nur x-Achse frei 
 * @note magChan = 0x2/0b10 -> nur y-Achse frei
 * @note magChan = 0x3/0b11 -> x- und y-Achse frei 
 * @note magChan = 0x4/0b100 -> nur z-Achse frei 
 * @note magChan = 0x5/0b101 -> z- und x-Achse frei 
 * @note magChan = 0x6/0b110 -> z- und y-Achse frei 
 * @note magChan = 0x7/0b111 -> z- und x- und y-Achse frei 
 * @note args[2] = zRange -> z-Range 
 * @note zRange = 0x0/0b0 -> +/- 150mT
 * @note zRange = 0x1/0b1 -> +/- 75mT
 * @note zRange = 0x2/0b10 -> +/- 300mT
 * @note args[3] = yRange -> y-Range 
 * @note yRange = 0x0/0b0 -> +/- 150mT
 * @note yRange = 0x1/0b1 -> +/- 75mT
 * @note yRange = 0x2/0b10 -> +/- 300mT
 * @note args[4] = xRange -> x-Range
 * @note xRange = 0x0/0b0 -> +/- 150mT
 * @note xRange = 0x1/0b1 -> +/- 75mT
 * @note xRange = 0x2/0b10 -> +/- 300mT 
 */
void sendSensConfig(char *data);
/*
 * @details Funktion, um systemConfig aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: Konfigurationsargumente          
 * @return void
 * @note Name des Befehls: "*SYSCONF!>diagMode|convStart|zLimCheck|yLimCheck|xLimCheck#"
 * @note args[0] = diagMode -> bestimmt Modus für Diagnostik-Tests
 * @note diagMode = 0x0/0b0 -> alle Diagnostiktest laufen gleichzeitig 
 * @note diagMode = 0x1/0b1 -> nur freigeschlatete Diagnostiktests laufen gleichzeitig 
 * @note diagMode = 0x2/0x10 -> alle Diagnostiktests laufen sequentiell 
 * @note diagMode = 0x3/0b11 -> nur freigeschaltete Diagnostiktests laufen sequentiell 
 * @note args[1] = convStart -> legt fest, wann Conversion startet
 * @note convStart = 0x0/0b0 -> Start at SPI command
 * @note convStart = 0x1/0b1 -> Start at ChipSelect pulse 
 * @note args[2] = zLimCheck -> z-Achsen Magnetfeld Limit Check 
 * @note zLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note zLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 * @note args[3] = yLimCheck -> y-Achsen Magnetfeld Limit Check 
 * @note yLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note yLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 * @note args[4] -> x-Achsen Magnetfeld Limit Check
 * @note xLimCheck = 0x0/0b0 -> Limit Check ausgeschaltet
 * @note xLimCheck = 0x1/0b1 -> Limit Check freigeschaltet
 */ 
void sendSysConfig(char *data);
/*
 * @details Funktion, um readReg aufzurufen und Ergebnis zu senden  
 * @param[in] char *data: Index des Registers  
 * @return void
 * @note Name des Befehls: "*READREG?>register#"
 */
void sendReadReg(char *data);
/*
 * @details Funktion, um readTemp aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer   
 * @return void
 * @note Name des Befehls: "*TEMP?#"
 */
void sendReadTemp(char *data);
/*  
 * @details Funktion, um getFieldValueX aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*GETFIELDVALUEX?#"
 */
void sendGetFieldValueX(char *data);
/*  
 * @details Funktion, um getFieldValueY aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*GETFIELDVALUEY?#"
 */
void sendGetFieldValueY(char *data);
/*  
 * @details Funktion, um getFieldValueZ aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*GETFIELDVALUEZ?#"
 */
void sendGetFieldValueZ(char *data);
/*  
 * @details Funktion, um getFieldValueXYZ aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer  
 * @return void 
 * @note Name des Befehls: "*GETFIELDVALUEXYZ?#"
 * @note Ergebnisse der drei Achsen werden als ein zusammenhängender String ausgegeben 
 */
void sendGetFieldValueXYZ(char *data);
/*  
 * @details Funktion, um alle Sensoren zu initislisieren 
 * @param[in] char *data: range   
 * @return void
 * @note Name des Befehls: "*INITALLSENSORS!#" 
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 */
void sendInitAllSensorsArduino(char *data);
/*  
 * @details Funktion, um zu prüfen, ob alle Sensoren mit korrekter Range initialisiert sind 
 * @param[in] char *data: range   
 * @return void
 * @note Name des Befehls: "*CHECKINIT!>#"
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 */
void sendCheckInit(char *data);
/*  
 * @details Funktion, um allSensorsArduino aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: range|init
 * @return void
 * @note Name des Befehls: "*ALLSENSORSARDUINO?>range|init#"
 * @note args[0] = range -> Range zum Auslesen der Sensoren bestimmen
 * @note range = 0x0/0b0 -> +-150mT
 * @note range = 0x1/0b1 -> +-75mT
 * @note range = 0x2/0b10 -> +-300mT
 * @note args[1] = init -> Sensoren initialisieren oder nicht 
 * @note init = 0 -> nicht initialisieren, alle Sensoren sind schon initialisiert 
 * @note init = 1 -> alle Sensoren initialisieren 
 */
void sendAllSensorsArduino(char *data);
/*
 * @details Funktion, um operatingMode aufzurufen und Ergebnis zu senden 
 * @param[in] char *data: leer
 * @return void 
 * @note Name des Befehls: "*OPERMODE?#"
 */
void sendOperatingMode(char *data); 
/*
 * @details Funktion, um oscInCheck aufzurufen und Ergebnis zu senden
 * @param[in] char *data: lowhigh
 * @return void 
 * @note Name des Befehls: "*OSCIC?>LowHigh#"
 * @note args[0] = lowHigh -> Hoch- oder Niedrigfrequenzoszillator wird geprüft
 * @note lowHigh = 0x0/0b0 -> Niedrigfrequenzoszillator
 * @note lowHigh = 0x1/0b1 -> Hochfrequenzoszillator 
 * @note ACHTUNG: nach Oscillator-Check gewünschte CRC Einstellung erneut vornehmen (CRC ON/OFF)
 */
void sendOscInCheck(char *data);
/*
 * @details Funktion, um selectChip aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: Index 
 * @return void 
 * @note Name des Befehls: "*SELECTCHIP!>index#"
 * @note args[0] = index -> Pin als String in HEX an dem der gewünschte Sensor angeschlossen ist 
 */
void sendSelectChip(char *data);
/*
 * @details Funktion, um deleteErrors aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: leer
 * @return void 
 * @note Name des Befehls: "*DELETEERRORS!#" 
 */
void sendDeleteErrors(char *data); 
/*
 * @details Funktion, um range aufzurufen und Ergebnis der Funktion zu senden 
 * @param[in] char *data: leer 
 * @return String: range in mT oder Fehlermeldung 
 * @note Name des Befehls: "*RANGE?#"
 */
void sendRange(char *data);
void sendAllSensorsArduinoFast(char *data);
void sendAllSensorsArduinoFaster(char *data);
String allSensorsArduinoFast();
// std::array<std::array<int16_t, 3>, 37> allSensorsArduinoFaster();
uint64_t* allSensorsArduinoFaster();

#endif