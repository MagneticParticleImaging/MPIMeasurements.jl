// ====
// Arduino Code, um Nachrichten über die serielle Schnittstelle zu empfangen und zu verarbeiten.
// ====

// Setze Flag um DEBUGGING und Test zu aktivieren.
#define DEBUG false

// 0 = normal full path (trigger + sensor read + USB stream)
// 1 = USB stream only (synthetic frames, no trigger, no SPI sensor read)
// 2 = trigger + USB stream (synthetic frames, no SPI sensor read)
#define STREAM_DIAGNOSTIC_MODE 0
#define STREAM_DIAGNOSTIC_INTERVAL_US 20000

// true  = answer on-demand serial commands (polling, e.g. *ALLSENSORSARDUINO?>...#)
//         only for interactive/dev scripts (messungSensorarray.jl, useDeviceExample.jl, ...)
// false = stream one frame per hardware trigger on the interrupt pin -- REQUIRED for any
//         RedPitaya/PorridgeFieldMeasurement run (MPIMeasurementsPorridge's FieldCameraAdapter
//         only ever reads the triggered binary stream; it never sends polling commands, so
//         leaving this true silently starves that pipeline of data and every frame ends up
//         NaN-filled as "missing"). Flip to true only for a temporary interactive-testing
//         flash, then flash this (false) back before the next real measurement.
#define POLLING_MODE false
// #define SERIAL Serial
// ====
// Füge Bibliothek hinzu, um zwischen Arduino und TMAG5170 zu kommunizieren 
// ====
#include "communicationWithTMAG5170.h" 

// ====
// Füge SPI Bibliothek hinzu, um über SPI zu kommunizieren
// ====
#include <SPI.h>

// Globale Variablen 
bool globalCRC = 0; //true = CRC On; false = CRC Off
int8_t globalChannel = 0; //0 kein Kanal zur Messung des Magnetfelds freigeschaltet
                    //1 = nur x
                    //2 = nur y
                    //3 = x und y
                    //4 = z
                    //5 = x und z 
                    //6 = y und z 
                    //7 alle  
bool globalTemp = 0; //true = Temperatur frei; false = Temperaturkanal ausgeschaltet
int globalRange = 0; //150 = +-150mT
                     //75 = +-75mT
                     //300 = +-300mT
// ====
// ChipSelect bestimmt, über welchen Pin Sensor und Board kommunizieren
// ====
int chipSelect = 0; 

// ====
// Sensoren 
// ====
int sensors[37] = {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 22, 23, 24, 25, 26, 27, 28, 29, 30,
            31, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 34}; 


// aus irgendeinem Grund muss hier mindestens eine Funktion stehen, sonst Fehler availableCommands nicht bekannt
// noch versuchen zu ändern 
void nofunction(){
}

// ====
// Definiere den Aufbau von Befehlen (commands), die der Chip erhalten und auswerten soll.
// Dabei wird folgender Aufbau festgelegt:
// (Dies ist eine Idee von eaderhold und sollte u.U. durch einen genormten Standard ersetzt werden)
// * Befehle beginnen mit dem commandBeginChar = '*'
// * Befehle enden mit dem commandEndChar = '#'
// * Befehle die Informationen/Daten senden (vom Bord weg) und damit eine Abfrage darstellen, enden mit dem getDataChar = '?'
// * Befehle die Informationen/Daten empfangen (von außen zum Bord) und damit eine Änderung erzeugen, enden mit dem setDataChar = '!'
// * Befehle die zusätzliche Argumente für die aufzurufende C-Funktion enthalten, werden mit dem argumentExpansionChar = '>' erweitert
// * Mehrere zusätzliche Argumente einer aufzurufenden C-Funktion werden mit argumentDividerChar = '|' getrennt.
// Allgemeines Befehlsschema (String oder char*): "*<Name des Befehls><get oder set>#"
// Allgemeines Befehlsschema (String oder char*) bei erweiterten Argumenten: "*<Name des Befehls><get oder set><Argument Erweiterungsbezeichnung = '>'><Argument1>|<Argument2>|<...>#"
// Beispiele für mögliche Befehle:
// 1. "*IDN?#" - Fragt die Identifikation des Boards ab.
// ====
char commandBeginChar = '*';
char commandEndChar = '#';
char getDataChar = '?';
char setDataChar = '!';
char argumentExpansionChar = '>';
char argumentDividerChar = '|';


// ====
// Definiere Konstanten der Verbindung
// ====
int baudrate = 250000; // 74880; 
char messageDelimiter = '\r';

// ====
// Definiere Speicherplatz und zugehörigen Positionswert, um kontinuierlich den seriellen Port zu lesen
// ====
#define inputBuffer_SIZE 256
char inputBuffer[inputBuffer_SIZE];
unsigned int input_pos = 0;

// ====
// Definiere einen Datentyp, der den String-Bezeichner eines Befehls enthält und dazu passend einen Handler (Pointer) zu eben dieser Funktion
// Damit dient dieser Datentyp gewissermaßen als Funktionshandler
// ====
typedef struct {
  char *command;           // Name bzw. Darstellung eines Befehls (im oben definierten Format)
  void (*handler)(char *);  // Pointer/Handler auf die Funktion, die aufgerufen werden soll, wenn dieser Name (Befehl) empfangen wird.
  char *args;
} commandHandler;

// ====
// Erstellen (basierend auf dem obigen Datentyp) einer Liste mit zur Verfügung stehenden Befehlen,
// die auf bestehende Funktionen verweisen.
// Es können einfach die definierten Strings als Befehle eingetragen werden
// Es können einfach die Funktionsnamen angegeben werden
//   Funktionen ohne Übergabeparameter können einfach angegeben werden (z.B.: void funktion(){} wird eingetragen als {*<Befehl>#, funktion})
//   Funktionen, die als Argumente den gesamten Befehl empfangen sollen, und damit als Argument immer char* haben,
//   müssen mit & dereferenziert werden (z.B. void funktionMitArgument(char* daten){} wird eingetragen als {*<Befehl>#, &funktion})
// ====
commandHandler availableCommands[] = {
  { "*IDN?#", sendIdentification },
  { "*pCMD?#", sendAvailableCommands},
  { "*DEFAULTCONF!#", sendDefaultConfig},
  { "*CRC!>#", &sendCRC, "ON/OFF"},
  { "*SINGDEVCONF!>#", &sendSingleDeviceConfig, "samplesPerConv|tempCoeff|operatingMode|tempChan|tempRate|tempLimCheck"},
  { "*SENSCONF!>#", &sendSensConfig, "BetConvs|magChan|zRange|yRange|xRange"}, 
  { "*SYSCONF!>#", &sendSysConfig, "diagMode|convStart|zLimCheck|yLimCheck|xLimCheck"},
  { "*READREG?>#", &sendReadReg, "register"},
  { "*TEMP?#", sendReadTemp},
  { "*GETFIELDVALUEX?#", sendGetFieldValueX},
  { "*GETFIELDVALUEY?#", sendGetFieldValueY},
  { "*GETFIELDVALUEZ?#", sendGetFieldValueZ},
  { "*GETFIELDVALUEXYZ?#", sendGetFieldValueXYZ},
  { "*INITALLSENSORS!>#", &sendInitAllSensorsArduino, "range"},
  { "*CHECKINIT!>#", &sendCheckInit, "range"},
  { "*ALLSENSORSARDUINO?>#", &sendAllSensorsArduino, "range|init"},
  { "*OPERMODE?#", &sendOperatingMode}, 
  { "*OSCIC?>#", &sendOscInCheck, "LowHigh"},
  { "*SHOWCRCCONFIGS?#", showCRCConfigs},
  { "*SHOWSINGDEVCONFIGS?#", showSingDevConfigs},
  { "*SHOWSENSCONFIGS?#", showSensConfigs},
  { "*SHOWSYSCONFIGS?#", showSysConfigs},
  { "*SELECTCHIP!>#", &sendSelectChip, "index"},
  { "*DELETEERRORS!#", sendDeleteErrors},
  { "*RANGE?#", sendRange},
  { "*ALLSENSORSARDUINOFAST?#", &sendAllSensorsArduinoFast},
  { "*DUMMY?#", sendDummy},
};

#define BYTES 1934
void sendDummy(char* data) {
  byte dummyArray[BYTES];
  for (int i = 0; i < BYTES; i++) {
    dummyArray[i] = 49;
  }
  serialWriteChunked(dummyArray, BYTES);
  SERIAL.flush();
  SERIAL.println();
}

/*  
 * @details Funktion, die bekannte Befehle sendet
 * @param[in] char *data: leer 
 * @return void 
 * @note Muss hier definiert werden, da sonst das availableCommands struct nicht bekannt ist.
 */
void sendAvailableCommands(char *data){
  String sendString = "";
  sendString += "Dem Messmittel sind folgende Befehle bekannt: \n\n";
  for (int i = 0; i < sizeof(availableCommands) / sizeof(*availableCommands) ; i++) { 
    if(availableCommands[i].command == "*CHECKINIT!>#" ||
    availableCommands[i].command == "*DELETEERRORS!#" ||
    availableCommands[i].command == "*SELECTCHIP!>#" ||
    availableCommands[i].command == "*RANGE?#" ){
      continue; //die drei Befehle sollen nicht von Nutzer aufgerufen werden, sondern 
                //sind automatisch in anderen Julia-Befehlen integriert 
    }
    else{
      sendString += "\t\"";
      sendString += availableCommands[i].command;
      sendString += availableCommands[i].args;
      sendString += "\", \n";
    }
  }
  sendString += "\n";
  SERIAL.println(sendString);
}

const int interruptPin = A0;
// volatile bool doMeas = false;

uint8_t i = 0;

// void interruptCallback() {
//   if(!doMeas){
//     doMeas = true;
//   }
// }

// ====
// Basisfunktionen des Arduino
// Richte den Chip ein
// ====
void setup() {
  // Definiere, dass es eine serielle Verbindung geben soll und warte, bis diese vorhanden ist
  SERIAL.begin(baudrate, SERIAL_8N1);  // Initialisiere serielle Verbindung, Baudrate, Serial_<no of data bits><Parity|N=None|Even|Odd><no of stopp bits>
  pinMode(interruptPin, INPUT_PULLUP);
  while (!SERIAL) {
    ;  // Warte, bis serielle Verbindung steht
  }

  for(int i = 0; i < 37; i++){ //Pin 2 bis 13 und 22 bis 46 sind an Sensorarray angeschlossen müssen ausgelesen werden 
      pinMode(sensors[i], OUTPUT);       
      digitalWrite(sensors[i],HIGH); // zuerst alle auf HIGH (HIGH = keine Kommunikation)
    }

  //beginne mit serieller Kommunikation zwischen Sensor und Board
  SPI.begin(); //initialisiert SPI Bus
  SPI.beginTransaction(SPISettings(5900000,MSBFIRST,SPI_MODE0)); //konfiguriert SPI Port //MODE0 = Clock Polarity 0 und Clock Phase 0 

  // Falls Flag gesetzt, führe Test durch
  if (DEBUG) {
    chipSelect = 2; //Beliebiger Sensor für Test. Hier wird Sensor an Pin 2 genutzt.
    SERIAL.println("\n\nDEBUG bzw. Test-Modus. Echtes Programm wird nicht ausgeführt.");
    TESTcommandBeginsWith();
    TESTgetCharsPosition();
    TESTsplitCommand();
    TESTconvertStringToInt();
    TESTsetBits();
    TESTgetBits();
    TESTwriteRead();
    TESTCRC();
    TESTflussdichte();
  }

  String message = "";
  if (STREAM_DIAGNOSTIC_MODE == 0) {
    message = allSensorsArduino("*ALLSENSORSARDUINO?>0x0|0x1#");
  }
  //delay(1000); // otherwise does not seem to catch up with serial monitor 
  //SERIAL.println(message);
  // delay(1000);
  // String message2 = allSensorsArduinoFast();
  // SERIAL.println(message2);
  //delay(2000);
  // attachInterrupt(digitalPinToInterrupt(interruptPin), interruptCallback, RISING);
}

// ====
// Basisfunktionen des Arduino
// Warte auf Befehle (Steuerbefehle) von außen
// ====
bool onceHigh = false;
uint32_t nextSyntheticSendUs = 0;

void loop() {
  if (STREAM_DIAGNOSTIC_MODE == 1) {
    uint32_t nowUs = micros();
    if (nextSyntheticSendUs == 0 || static_cast<int32_t>(nowUs - nextSyntheticSendUs) >= 0) {
      sendSyntheticDiagnosticFrame();
      nextSyntheticSendUs = nowUs + STREAM_DIAGNOSTIC_INTERVAL_US;
    }
    return;
  }

  // Polling: read the field on demand whenever Julia sends a command
  // (e.g. *ALLSENSORSARDUINO?>...#) and reply over serial.
  if (POLLING_MODE) {
    receiveCommandMessage();
    return;
  }

  // Trigger mode: stream one binary frame each time the interrupt pin goes high.
  if ((analogRead(interruptPin) >= 1023 / 10) && !onceHigh) {
    onceHigh = true;
    if (STREAM_DIAGNOSTIC_MODE == 2) {
      sendSyntheticDiagnosticFrame();
    } else {
      sendAllSensorsArduinoFaster("");
    }
    i++;
  }
  else if (analogRead(interruptPin) < 1023 / 10) {
    onceHigh = false;
  }
}

//====
//Funktionen, die nicht in .h/.cpp Datei ausgelagert werden können (da sonst availableCommands etc. nicht bekannt)
//Funktionen, zum Empfangen von externen Nachrichten (Julia-Befehle) und Ausführen der gewünschten Befehle
//====
 
/*
 * @details Funktion, um Buffer zu füllen 
 * Wenn ein Byte vorhanden ist, lese dieses char und schreibe es in den Speicher.
 * Solange, bis das commandEndChar empfangen wird.
 * Dann schreibe auch das commandBeginChar und beende das charArray mit dem \0 Ende und gebe true zurück, da eine Nachricht empfangen wurde.
 * @return bool: falls kein Byte vorhanden ist, gebe false zurück; sonst true
 */
bool fillBufferUntilDelim() {
  char nextReceiveChar;
  while (SERIAL.available() > 0) {
    nextReceiveChar = SERIAL.read();
    if (nextReceiveChar == commandEndChar) {
      inputBuffer[input_pos % (inputBuffer_SIZE - 1)] = nextReceiveChar;  // Size - 1 to always leave room for \n
      input_pos++;
      inputBuffer[input_pos] = '\0';
      input_pos = 0;
      return true;
    } else {
      inputBuffer[input_pos % (inputBuffer_SIZE - 1)] = nextReceiveChar;  // Size - 1 to always leave room for \n
      input_pos++;
    }
  }
  return false;
}
/*
 * @details Funktion zum Empfangen von Befehlen basierend auf dem Buffer 
 * Empfange Befehle basierend auf dem Buffer
 * Funktion wird im Loop des Chip unendlich wiederholt
 * Warte bis Befehl erkannt (durch fillBufferUntilDelim)
 * Trenne Befehl aus den möglicherweise längeren, empfangenen Daten im Buffer
 * Setze Buffer zurück
 * Führe Befehl aus
 * @return void
 */
void receiveCommandMessage() {
  // Definiere, dass bisher kein Befehl empfangen wurde
  bool gotCommand = false;
  // Falls über den Seriellen Port Daten empfangen werden, fülle Buffer und warte auf einen Befehl
  if (SERIAL.available() > 0) {
    gotCommand = fillBufferUntilDelim();
  }
  // Sobald Befehl empfangen wurde
  if (gotCommand) {
    // Warte das alles gesendet wurde, falls vorher noch etwas zu senden war
    SERIAL.flush();
    // Finde Anfang und Ende des Befehls
    int commandStartSymbolPosition = getCharsPosition(inputBuffer, commandBeginChar);
    int commandEndSymbolPosition = getCharsPosition(inputBuffer, commandEndChar);
    // Definiere erweiterbaren Speicher um gesammten Befehl zu speichern
    String command = "";
    // Speichere Befehl aus eventuell mit mehr Bytes gefülltem Buffer
    for (int i = commandStartSymbolPosition; i <= commandEndSymbolPosition; i++) {
      command += inputBuffer[i];
    }
    // Da Befehl nun gespeichert ist, leere Buffer
    inputBuffer[0] = '\0';
    // Führe den Befehl aus, dazu vorher Konvertierung in char-array
    char *charcommand = new char[command.length() + 1];
    strcpy(charcommand, command.c_str());
    executeCommand(charcommand);
    delete[] charcommand; 
  }
  return;
}
/*
 * @details Funktion zum Ausführen eines definierten Befehls
 * @param[in] char command[]: auszuführender Befehl
 * @return void
 */
void executeCommand(char command[]) {
  // Iteriere über alle im Array availableCommands hinterlegten möglichen Befehle
  for (int i = 0; i < sizeof(availableCommands) / sizeof(*availableCommands); i++) {
    // // Falls Kommando in möglichen Befehlen enthalten (Gleichheit), führe dieses aus
    // if ((possibleCommands[i].command).compareTo(command) == 0) {
    //   possibleCommands[i].handler(command);
    // }
    // Falls Befehl mit einem bekannten Befehl beginnt
    if (commandBeginsWith(command, availableCommands[i].command)) {
      availableCommands[i].handler(command);
      return;
    }
  }
  //Falls command nicht bekannt:
  SERIAL.print("*ERROR:UNKNOWN COMMAND# \n");
  return;
}
