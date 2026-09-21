#include <cstdint>
// #include <cstdint>
// #include "wiring.h"
#include "Arduino.h"
#include "communicationWithTMAG5170.h"
// ====
// Füge SPI Bibliothek hinzu, um über SPI zu kommunizieren
// ====
#include <SPI.h>
// ====
// Füge ArduinoUniqueID Bibliothek hinzu,
// um eine eindeutige Identifikation des verwendeten Boards zu bekommen
// ====
#include <ArduinoUniqueID.h>
// ====
// Füge limits.h hinzu, um INT_MIN zu nutzen
// ====
#include <limits.h>

void serialWriteChunked(const uint8_t *data, size_t len, size_t chunkSize){
  if (chunkSize == 0) {
    chunkSize = 32;
  }

  size_t offset = 0;
  while (offset < len){
    size_t chunk = min(chunkSize, len - offset);
    while (SERIAL.availableForWrite() < (int)chunk){
      yield();
    }
    SERIAL.write(data + offset, chunk);
    offset += chunk;
  }
}

void serialWriteChunked(const void *data, size_t len, size_t chunkSize){
  serialWriteChunked(reinterpret_cast<const uint8_t*>(data), len, chunkSize);
}

static void sendFramedPacket(const uint8_t *payload, size_t payloadLen, uint8_t readingCounter){
  // Use a longer sync word so a packet boundary is much less likely to be
  // confused with payload bytes when the host resynchronizes after a transient
  // serial glitch.
  const uint8_t sof[4] = {0xA5, 0x5A, 0xC3, 0x3C};
  uint8_t checksum = 0;

  for (size_t i = 0; i < payloadLen; i++) {
    checksum ^= payload[i];
  }
  checksum ^= readingCounter;

  serialWriteChunked(sof, sizeof(sof));
  serialWriteChunked(payload, payloadLen);
  serialWriteChunked(&readingCounter, 1);
  serialWriteChunked(&checksum, 1);
  SERIAL.flush();
}

void sendSyntheticDiagnosticFrame(){
  static uint8_t readingCounter = 0;
  uint64_t payloadWords[37];

  for (int sensorIdx = 0; sensorIdx < 37; sensorIdx++) {
    int16_t x = static_cast<int16_t>((readingCounter * 37 + sensorIdx) & 0x7FFF);
    int16_t y = static_cast<int16_t>(-(readingCounter * 17 + sensorIdx));
    int16_t z = static_cast<int16_t>((readingCounter * 9 + sensorIdx * 3) & 0x7FFF);

    uint64_t packed = 0;
    packed |= static_cast<uint64_t>(static_cast<uint16_t>(x));
    packed |= static_cast<uint64_t>(static_cast<uint16_t>(y)) << 16;
    packed |= static_cast<uint64_t>(static_cast<uint16_t>(z)) << 32;
    payloadWords[sensorIdx] = packed;
  }

  sendFramedPacket(reinterpret_cast<const uint8_t*>(payloadWords), sizeof(payloadWords), readingCounter);
  readingCounter++;
}

// ====
// globale Variablen mit extern deklarieren, aber keinen Wert zuweisen (Defintion mit Wert in .ino Datei)
// ====
extern int chipSelect; 
extern bool globalCRC;
extern int8_t globalChannel; 
extern int sensors[];
extern int globalRange; 
extern bool globalTemp; 
extern char commandBeginChar;
extern char commandEndChar;
extern char getDataChar;
extern char setDataChar;
extern char argumentExpansionChar;
extern char argumentDividerChar;

// ====
// Hilfsfunktionen zum Verarbeiten der Befehle (werden nie über Julia aufgerufen -> keine extra Ausgabe Funktion)
// ====
int convertStringToInt(String str){
  int result = INT_MIN;
  if (str.startsWith("0b")){    // Bit wise definition
    result = strtol((str.substring(2)).c_str(),NULL,2);
  } else if(str.startsWith("0x")){  // HEX definition
    result = strtol(str.c_str(),NULL,0);
  } else {
    SERIAL.print("ERROR. Konvertierung nicht möglich! Unbekanntes Format. \n");
    return NULL;
  }
  return result;
}

void TESTconvertStringToInt(){
  // Test 0x0A
  String str = "0x0A";
  SERIAL.print("convertStringToInt(): ");
  SERIAL.println((convertStringToInt(str) == 10) ? "OK" : "ERROR");
  // Test 0b00000010
  str = "0b00000010"; 
  SERIAL.print("convertStringToInt(): ");
  SERIAL.println((convertStringToInt(str) == 2) ? "OK" : "ERROR");
  // Test 0b01000101
  str = "0b01000101";
  SERIAL.print("convertStringToInt(): ");
  SERIAL.println((convertStringToInt(str) == 69) ? "OK" : "ERROR");
  // Falsches Format
  str = "0c01000101";
  SERIAL.print("convertStringToInt(): ");
  SERIAL.println((convertStringToInt(str) == -32768) ? "OK" : "ERROR");
}

int getCharsPosition(char str[], char finde){
  for (int i = 0; i < strlen(str); i++) {
    if (str[i] == finde) {
      return i;
    }
  }
  return -1;
}

void TESTgetCharsPosition(){
  char *str = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  char find = 'a';
  SERIAL.print("getCharsPosition(): ");
  SERIAL.println((getCharsPosition(str, find) == 0) ? "OK" : "ERROR");
  SERIAL.print("getCharsPosition(): ");
  SERIAL.println((getCharsPosition(str, 'A') == 26) ? "OK" : "ERROR");
  SERIAL.print("getCharsPosition(): ");
  SERIAL.println((getCharsPosition(str, 'ö') == -1) ? "OK" : "ERROR");
}

bool commandBeginsWith(const char *str, const char *with){
  int result = 0;
  // Anzahl Zeichen in str
  int strLen = strlen(str);
  // Anzahl Zeichen in with
  int withLen = strlen(with) - 1;
  for (int i = 0; i < withLen; i++) {
    if (str[i] != with[i]) {
      result++;
    }
  }
  if (result == 0) {
    return true;
  } else {
    return false;
  }
}

void TESTcommandBeginsWith(){
  // Testfall durch Argument erweiterter Befehl, aber gleicher Anfang
  char *str = "*IDN?>A|B|c#";
  char *with = "*IDN?#";
  SERIAL.print("commandBeginsWith(): ");
  SERIAL.println(commandBeginsWith(str, with) ? "OK" : "ERROR");
  // Testfall Identisch
  SERIAL.print("commandBeginsWith(): ");
  SERIAL.println(commandBeginsWith(str, str) ? "OK" : "ERROR");
  // Testfall unterschiedlich
  str = "*JDN?#";
  SERIAL.print("commandBeginsWith(): ");
  SERIAL.println(!commandBeginsWith(str, with) ? "OK" : "ERROR");
}

int numberOfArgumentsInCommand(const char *cmd){
  // Datenkonversion um mit String-Commands zu arbeiten
  String strCommand = cmd;
  // Länge der Eingabe
  int strCommandLen = strCommand.length();
  // Splitte in Commando und Argumente
  // Besorge Positino des argumentExpansionChar
  int argumentExpansionCharPosition = strCommand.indexOf(argumentExpansionChar);
  // Falls Befehl keine Argumente enthält.
  if (argumentExpansionCharPosition == -1){
    return 0;
  } 
  // Falls Befehl Argumente enthält, splitte diese
  else {
    // Besorge substring arguments ohne commandEndChar
    String args = strCommand.substring(argumentExpansionCharPosition + 1, strCommandLen - 1);
    // Erhalte die Argumentliste erweitert um das argumentExpansionCharPosition
    args += argumentDividerChar;  // ende mit Pipe, damit Auftrennen leichter geht
    // Zähle die Anzahl der übergebenen Argumente, um das Rückgabe Array anlegen zu können
    // (Weil das beklppte C ja standardmäßig keine Vektoren kennt; TODO: könnte man vielleicht erweitern um dynamisch zu halten)
    int noOfArguments = 0;
    for (int i = 0; i < args.length(); i++) {
      if (args[i] == argumentDividerChar) {
        noOfArguments++;
      }
    }
    return noOfArguments;
  }
}

void TESTnumberOfArgumentsInCommand(){
  // Test 0
  char *command = "*IDN?#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 0 ? "OK" : "ERROR");
  // Test1
  command = "*IDN?>A#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 1 ? "OK" : "ERROR");
  // Test1
  command = "*IDN?>MPi#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 1 ? "OK" : "ERROR");
  // Test2
  command = "*IDN?>A|B#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 2 ? "OK" : "ERROR");
  // Test2
  command = "*IDN?>MPi|eaderhold#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 2 ? "OK" : "ERROR");
  // Test 
  command = "*IDN?>MPi|eaderhold|A|B|0x00000010|0xA#";
  SERIAL.print("numberOfArgumentsInCommand(): ");
  SERIAL.println(numberOfArgumentsInCommand(command) == 6 ? "OK" : "ERROR");
}

String * splitCommand(const char *cmd){
  // Datenkonversion, um mit String-Commands zu arbeiten
  String strCommand = cmd;
  // Länge der Eingabe
  int strCommandLen = strCommand.length();
  // Splitte in Commando und Argumente
  // Besorge Position des argumentExpansionChar
  int argumentExpansionCharPosition = strCommand.indexOf(argumentExpansionChar);
  // Falls Befehl keine Argumente enthält.
  if (argumentExpansionCharPosition == -1){
    return NULL;
  } 
  // Falls Befehl Argumente enthält, splitte diese
  else {
    // Besorge substring command und erweitere um das commandEndChar
    String command = strCommand.substring(0, argumentExpansionCharPosition);
    // Erhalte den reinen Befehl mit Erweiterung um das commandEndChar
    command += commandEndChar;
    // Besorge subsring arguments ohne commandEndChar
    String args = strCommand.substring(argumentExpansionCharPosition + 1, strCommandLen - 1);
    // Erhalte die Argumentliste Erweitert um das argumentExpansionCharPosition
    args += argumentDividerChar;  // ende mit Pipe, damit Auftrennen leichter geht
    // Zähle die Anzahl der übergebenen Argumente, um das Rückgabe Array anlegen zu können
    // (Weil das beklppte C ja standardmäßig keine Vektoren kennt; TODO: könnte man vielleicht erweitern um dynamisch zu halten)
    int noOfArguments = 0;
    for (int i = 0; i < args.length(); i++) {
      if (args[i] == argumentDividerChar) {
        noOfArguments++;
      }
    }
    // Falls es keine Arguemte gibt, breche ab
    if (noOfArguments == 0) return NULL;
    // Definiere Rückgabeelemtent mit passender Länge
    String *arguments = new String[noOfArguments];

    // Lege Iteratoren an, um die Trennung zu vollziehen
    int iterator = 0;
    // Position ab der die Argumente nach Pipes zum Trennen durchsucht werdne
    int searchFrom = 0;
    // Solange es im nachfolgenden String noch eine Pipe gibt:
    while (args.indexOf(argumentDividerChar, searchFrom) != -1) {
      // Finde die nächste Pipe
      int searchTo = args.indexOf(argumentDividerChar, searchFrom + 1);
      // Das folgende if ist auskommentiert, weil es eigentlich (?) immer automatisch gelten solte
      // if (searchTo > searchFrom) {
        // neuer String, der nur das x-te Argument enthält
        String arg = args.substring(searchFrom, searchTo);
        // Schreibe das extrahierte Argument in das Rückgabearray und erhöhe den iterator auf die nächste freie Position
        arguments[iterator++] = arg;
      // }
      // Setze die Startpositoin der Suche rechts neben den aktuellen suchwert
      searchFrom = searchTo + 1;
    }
    return arguments;
  }
}

void TESTsplitCommand(){
  // Test No Argument
  char *command = "*IDN?#";
  String *args;
  if (numberOfArgumentsInCommand(command)> 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");  
  SERIAL.print(numberOfArgumentsInCommand(command) == 0 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste ein Argument
  command = "*IDN?>A#";
  if (numberOfArgumentsInCommand(command)> 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("A") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste ein Argument mit mehreren Zeichen
  command = "*IDN?>eaderhold#";
  if (numberOfArgumentsInCommand(command)> 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("eaderhold") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste wiederholt ein Argument mit mehreren Zeichen
  command = "*IDN?>eaderhold#";
  if (numberOfArgumentsInCommand(command)> 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("eaderhold") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste ein Argument mit GroßKlein
  char * command1 = "*IDN?>MPi#";
  if (numberOfArgumentsInCommand(command1)> 0){
    args = splitCommand(command1);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("MPi") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste ein Argument mit HEX
  command = "*IDN?>0x000A#";
  if (numberOfArgumentsInCommand(command) > 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("0x000A") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste ein Argument mit Byte
  command = "*IDN?>0b01010101#";
  if (numberOfArgumentsInCommand(command) > 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("0b01010101") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 1 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");

  // Teste mehrere
  command = "*IDN?>MPi|0x000A|0b01010101#";
  if (numberOfArgumentsInCommand(command)> 0){
    args = splitCommand(command);
  }
  SERIAL.print("splitCommand(): ");
  SERIAL.print(args[0].compareTo("MPi") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(args[1].compareTo("0x000A") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(args[2].compareTo("0b01010101") == 0 ? "OK, " : "ERROR, ");
  SERIAL.print(numberOfArgumentsInCommand(command) == 3 ? "(OK)" : "(ERROR)");
  SERIAL.print("\n");
  
  delete[] args;
}



// ====
// Funktionen zur Kommunikation mit TMAG5170 (werden nie über Julia aufgerufen -> keine extra Ausgabe Funktion)
// ====

bool writeRegister(byte registerName, int16_t data, byte CMD_CRC){  
  digitalWrite(chipSelect, LOW); 
  SPI.transfer(registerName); //SPI.transfer sendet 8 Bits und empfängt 8 Bits 
  SPI.transfer16(data); //bei SPI.transfer16 sind es 16 Bits 
  SPI.transfer(CMD_CRC); 
  digitalWrite(chipSelect, HIGH);

  byte registerRead = registerName + 0x80; //um aus Register zu lesen, muss erstes der 8 Bits 1 sein -> +0x80 
  byte CC_Read = calculateCRC(registerRead, 0x0000, 0x00);
  int16_t result = readRegister(registerRead, 0x0000, CC_Read);
  bool test = false; //Test, ob Daten, die in Register stehen, mit dem übereinstimmen, was rein geschrieben wurde 
  if(result == data) test = true;
  else test = false; 
  return test;
}

int16_t readRegister(byte registerName, int16_t data, byte CMD_CRC){ 
  byte status1 = 0; 
  uint16_t result = 0; 
  byte status2_CRC = 0; 
  digitalWrite(chipSelect, LOW); 
  status1 = SPI.transfer(registerName); //die ersten 8 Status Bits
  result = SPI.transfer16(data); //die 16 Daten Bits
  status2_CRC = SPI.transfer(CMD_CRC); //noch 4 Status Bits und 4 CRC Bits 
  digitalWrite(chipSelect, HIGH); 
  if (globalCRC == true){ //globalCRC wird auf true gesetezt, wenn CRC über Test-Register aktiviert wird 
    byte CRC_Cal = calculateCRC(status1, result, status2_CRC);
    if((CRC_Cal & 0x0F) != (status2_CRC & 0x0F)){ //berechneten CRC Wert mit CRC Wert aus Register vergleichen 
      SERIAL.print("CRC ERROR IN SDO FRAME \n");
    }
  }
  return result; 
}

void TESTwriteRead(){
  byte registerWrite = 0x07; //T_THRX_CONFIG Register (Offset h7) nutzen, da dies sonst nicht genutzt wird und so keine Probleme entstehen 
  byte registerRead = 0x87;
  int16_t dataWrite = 0xA937;
  int16_t dataRead = 0x0000; 
  byte CC_Write = calculateCRC(registerWrite, dataWrite, 0x00); // bei Test CMD 0x0
  writeRegister(registerWrite, dataWrite, CC_Write); 
  byte CC_Read = calculateCRC(registerRead, dataRead, 0x00);
  int16_t result = readRegister(registerRead, dataRead, CC_Read);
  SERIAL.print("writeRegister() and readRegister()): ");
  SERIAL.println(result == dataWrite ? "OK" : "ERROR");
}

uint8_t calculateCRC(byte registerName, int16_t data, byte CMD_CRC){
  uint8_t frame[32] = {0};
  CMD_CRC = CMD_CRC & 0xF0; //die ersen vier Bits sind CMD Bits, die letzten 4 sind Null, weil 4 Nullen an Frame angehängt werden müssen, wegen Polynom von Grad 4 
  byte CMD_CRC_Copy = CMD_CRC; //am Ende werden die originalen CMD Bits benötigt, werden aber zwischendurch geändert 
  for (int i = 0; i <= 7; i++) { //32 Bits Frame mit Daten beschreiben, dabei jedes Bit ein eigener Eintrag im Array 
    int16_t vergleich = registerName & 0x80; //0x80 = 1000 0000 //prüfen, ob erstes Bit 1 oder 0 ist 
    if (vergleich == 0){
    frame[i] = 0;
    }
    else {
      frame[i] = 1;
    }
    registerName = registerName << 1; // Wert wird um eins nach links geshiftet, sodass jetzt nächstes Bit an erster Stelle 
  }
  for (int i = 8; i <= 23; i++) { 
    int16_t vergleich = data & 0x8000; //0x8000 = 1000 0000 0000 0000
    if (vergleich == 0){
    frame[i] = 0;
    }
    else {
      frame[i] = 1;
    }
    data = data << 1;
  }
  for (int i = 24; i <= 31; i++) { 
    int16_t vergleich = CMD_CRC & 0x80; //0x80 = 1000 0000
    if (vergleich == 0){
    frame[i] = 0;
    }
    else {
      frame[i] = 1;
    }
    CMD_CRC = CMD_CRC << 1;  
  }  
  uint8_t crc[4] = {1, 1, 1, 1}; //Initial Value laut Datasheet
  int inv; 
  for (int i = 0; i <= 31; i++){ //Berechnung des CRC laut Datasheet 
   inv = frame[i] ^ crc[3];
   crc[3] = crc[2]; 
   crc[2] = crc[1];
   crc[1] = crc[0] ^ inv; 
   crc[0] = inv; 
  }

  uint8_t crcResult = 0; //Einträge aus dem Array in einen Integer schreiben 
  for (int i = 3; i >= 0; i--){
    crcResult += crc[i]; 
    if(i > 0) crcResult = crcResult << 1; //das letzte Mal nicht shiften, sonst ab 5 letztem Bit CRC
  }

  crcResult = crcResult & 0x0F; //nur die letzten 4 Bits sind CRC
  return (CMD_CRC_Copy | crcResult); 
}

void TESTCRC(){ //Testvariable 0b 0000 0000 0000 0011 0000 0000 0101 0000
  byte test1 = 0x00; 
  int16_t test2 = 0x0300; 
  byte test3 = 0x50; 
  uint8_t result = calculateCRC(test1, test2, test3);
  SERIAL.print("calculateCRC(): ");
  SERIAL.println(result == 0x51 ? "OK" : "ERROR"); // //Ergebnis für CRC ist [0, 0, 0, 1], aber CMD Bits müssen wieder vorgehängt werden
}

int16_t setBits(int16_t data, byte begin, byte end, byte value){ 
  uint8_t anzahlBits = (begin - end + 1); //Anzahl der zu setzenden Bits bestimmen 
  uint8_t *bitsToSet = new uint8_t[anzahlBits]; //Array für zu setzende Bits 
  uint8_t NewDataBits[16] = {0}; //Array für neue Daten mit gesetztem Value

  if(begin == end){ //wenn nur 1 Bit gesetzt werden soll
    uint8_t dataBits[16] = {0}; 
    for (int i = 15; i>= 0; i--){ //16 Datenbits in einen Array schreiben 
      int16_t vergleich = data & 0x8000; 
      if(vergleich == 0) dataBits[i] = 0; 
      else dataBits[i] = 1; 
      data = data << 1; 
    }
    for(int i = 0; i <= 15; i++){
      if(i == begin) NewDataBits[i] = value; //an gewünschter Stelle, neuen Wert einsetzen 
      else NewDataBits[i] = dataBits[i]; 
    }
  }
  else{ //wenn 2 bis 8 Bits gesetzt werden sollen
    for (int i = 0; i < anzahlBits; i++){
      int8_t vergleich = value & 0x01; //zu setzenden Wert als einzelne Bits in Array schreiben 
      if(vergleich == 0) bitsToSet[i] = 0; 
      else bitsToSet[i] = 1; 
      value = value >> 1; 
    }

    uint8_t dataBits[16] = {0}; 
    for (int i = 15; i>= 0; i--){ //16 Datenbits in einen Array schreiben 
      int16_t vergleich = data & 0x8000; 
      if(vergleich == 0) dataBits[i] = 0; 
      else dataBits[i] = 1; 
      data = data << 1; 
    }
    int n = anzahlBits - 1; 

    if(begin == 15){ //wenn erstes zu setzendes Bit das Bit 15 ist 
      for (int i = begin; i >= end; i--){
        NewDataBits[i] = bitsToSet[n]; //neue Bits setzen 
        n = n - 1;
      }
      for (int i = (end - 1); i >= 0 ; i--){
        NewDataBits[i] = dataBits[i]; //die Bits, die bestehen bleiben  
      }
    }

    if(end == 0){ ///wenn letztes zu setzendes Bit das Bit 0 ist 
      for (int i = 15; i > begin; i--){
        NewDataBits[i] = dataBits[i]; //die Bits, die bestehen bleiben  
      }  
      for (int i = begin; i >= end; i--){
        NewDataBits[i] = bitsToSet[n]; //neue Bits setzen 
        n = n - 1;
      }
    }

    if(begin != 15 && end != 0){ //mehrere Bits in der Mitte werden gesetzt 
      for (int i = 15; i > begin; i--){
        NewDataBits[i] = dataBits[i]; //die Bits, die bestehen bleiben   
      } 
      for (int i = begin; i >= end; i--){
        NewDataBits[i] = bitsToSet[n]; //neue Bits setzen 
        n = n - 1;
      }
      for (int i = (end - 1); i >= 0 ; i--){
        NewDataBits[i] = dataBits[i]; //die Bits, die bestehen bleiben  
      }
    }
  }

  int16_t newData = 0; 
  for (int i = 15; i >= 0; i--){ //Bits aus Array in einen Integer schreiben 
    newData += NewDataBits[i]; 
    if(i > 0) newData = newData << 1; //das letzte Mal nicht shiften
  }
  delete[] bitsToSet; 
  return newData;
}

void TESTsetBits(){
  int16_t data1 = 0b1011000000000001;
  int16_t test1 = setBits(data1, 12, 11, 1);
  int16_t result1 = 0b1010100000000001;
  SERIAL.print("setBits(): ");
  SERIAL.println(test1 == result1? "OK" : "ERROR");

  int16_t data2 = 0b1011110000110101;
  int16_t test2 = setBits(data2, 3, 0, 15);
  int16_t result2 = 0b1011110000111111;
  SERIAL.print("setBits(): ");
  SERIAL.println(test2 == result2? "OK" : "ERROR");

  int16_t data3 = 0b1110000110000001;
  int16_t test3 = setBits(data3, 15, 9, 85);  
  int16_t result3 = 0b1010101110000001;
  SERIAL.print("setBits(): ");
  SERIAL.println(test3 == result3? "OK" : "ERROR");

  int16_t data4 = 0b1110000110000111;
  int16_t test4 = setBits(data4, 9, 9, 1);
  int16_t result4 = 0b1110001110000111;
  SERIAL.print("setBits(): ");
  SERIAL.println(test4 == result4? "OK" : "ERROR");

  int16_t data5 = 0b1001010100111110;
  int16_t test5 = setBits(data5, 15, 15, 0);
  int16_t result5 = 0b0001010100111110;
  SERIAL.print("setBits(): ");
  SERIAL.println(test5 == result5? "OK" : "ERROR");

  int16_t data6 = 0b1001101010101110;
  int16_t test6 = setBits(data6, 0, 0, 1);
  int16_t result6 = 0b1001101010101111;
  SERIAL.print("setBits(): ");
  SERIAL.println(test6 == result6 ? "OK" : "ERROR");
}

bool *getBits(int16_t data){ 

  bool *allBits = new bool[16]; //alle Bits hintereinander in ein Array schreiben 
  for (int i = 15; i >= 0; i--) {
    int16_t vergleich = data & 0x8000; //0x8000 = 1000000000000000 --> nur erstes Bit (15. Bit) ist relevant; wenn erstes Bit = 1, dann vergleich = 1; wenn erstes Bit = 0, dann vergleich = 0
    if (vergleich == 0){
    allBits[i] = 0;
    }
    else {
      allBits[i] = 1;
    }
    data = data << 1; // Wert wird um eins nach links geshiftet, sodass jetzt nächstes Bit an erster Stelle 
  }

  return allBits; 
}

void TESTgetBits(){
  int16_t data1 = 0b1011000000000001;
  bool *bits1;
  bits1 = getBits(data1);
  SERIAL.print("getBits(): ");
  SERIAL.println(bits1[5] == 0 ? "OK" : "ERROR");
  delete[] bits1;

  int16_t data2 = 0b1011000000000001;
  bool *bits2;
  bits2 = getBits(data2);
  SERIAL.print("getBits(): ");
  SERIAL.println(bits2[15] == 1 ? "OK" : "ERROR");
  delete[] bits2;

  int16_t data3 = 0b1011000000000001;
  bool *bits3;
  bits3 = getBits(data3);
  SERIAL.print("getBits(): ");
  SERIAL.println(bits3[0] == 1 ? "OK" : "ERROR");
  delete[] bits3;
}

// float flussdichte(int16_t messwert){
//   return messwert;
// }
float flussdichte(int16_t messwert){
  float ergebnis = 0; //nach Formel aus Datasheet, um die Flussdichte in mT zu berechnen  
  bool *bits;
  bits = getBits(messwert);

  //1 << 14 == pow(2,14) --> bitshift
  long zwischenSumme =  bits[14]*(1 << 14) + bits[13]*(1 << 13) + bits[12]*(1 << 12)
                      + bits[11]*(1 << 11) + bits[10]*(1 << 10) + bits[9]*(1 << 9) 
                      + bits[8]*(1 << 8) + bits[7]*(1 << 7) + bits[6]*(1 << 6)
                      + bits[5]*(1 << 5) + bits[4]*(1 << 4) + bits[3]*(1 << 3) 
                      + bits[2]*(1 << 2) + bits[1]*(1 << 1) + bits[0]*(1 << 0);                   
  if (globalRange == 150){ //Range von +-150mT
    ergebnis = ( ( -(bits[15] * pow(2, 15) ) + zwischenSumme )  /  pow(2, 16) ) * 2 * 150; 
  }
  else if (globalRange == 75){ //Range von +-75mT
    ergebnis = ( ( -(bits[15] * pow(2, 15) ) + zwischenSumme )  /  pow(2, 16) ) * 2 * 75;
  }
  else if (globalRange == 300){ //Range von +-300mT
    ergebnis = ( ( -(bits[15] * pow(2, 15) ) + zwischenSumme )  /  pow(2, 16) ) * 2 * 300;
  }

  delete[] bits; //Arrays mit new[] erstellt, müssen immer gelöscht werden 
  return(ergebnis);
}

void TESTflussdichte(){ 
  int16_t testVar = 0b0110100101101010;
  globalRange = 300;
  float result = flussdichte(testVar);
  SERIAL.print("flussdichte(): ");
  SERIAL.println(round(result * 1000) == round(247.064 * 1000) ? "OK" : "ERROR");//247.064208984375 // auf drei Nachkommastellen runden 
}

String convStat(){ 
  byte CC_CONV = calculateCRC(CONV_STAT_REG, 0x0000, 0x00); 
  int16_t CONVstat = readRegister(CONV_STAT_REG, 0x0000, CC_CONV);
  //int16_t CONVstat = 0b0011111000000000; //Test der Funktion (Fehler: Conversion Data not valid; X-Channel not current)
  bool *bits;
  bits = getBits(CONVstat);
  if(bits[13] == 0){
    delete[] bits;
    return F7; //CONVERSION ERROR - Conversion data not valid
  }
  if(globalTemp == true){ //nur Temp.sensor prüfen, wenn Temperatur auch ausgelesen werden soll 
      if(bits[11] == 0){
        delete[] bits;
        return F8; //CONVERSION ERROR - Temperature data not current
      }
  }
  
  if(globalChannel == 7){ //je nach freigeschalteten/gewünschten Kanälen auch nur diese prüfen 
      if(bits[10] == 0){
        delete[] bits;
        return F9;//CONVERSION ERROR - Z-Channel data not current 
      }
      if(bits[9] == 0){
        delete[] bits;
        return F10; //CONVERSION ERROR - Y-Channel data not current
      }
      if(bits[8] == 0){
        delete[] bits;
        return F11;//CONVERSION ERROR - X-Channel data not current 
      } 
      else{
        delete[] bits;
        return SUCCESS;  
      }
  }
  
  if(globalChannel == 6){
    if(bits[10] == 0){
      delete[] bits;
      return F9;//CONVERSION ERROR - Z-Channel data not current 
    }
    if(bits[9] == 0){
      delete[] bits;
      return F10; //CONVERSION ERROR - Y-Channel data not current
    }
    else{
      delete[] bits;
      return SUCCESS; 
    }
  }

  if(globalChannel == 5){
    if(bits[10] == 0){
      delete[] bits;
      return F9;//CONVERSION ERROR - Z-Channel data not current 
    } 
    if(bits[8] == 0){
        delete[] bits;
        return F11;//CONVERSION ERROR - X-Channel data not current 
    } 
    else{      
      delete[] bits;
      return SUCCESS; 
    }
  }

  if(globalChannel == 4){
    if(bits[10] == 0){
      delete[] bits;
      return F9;//CONVERSION ERROR - Z-Channel data not current 
    }
    else{
      delete[] bits;
      return SUCCESS;
    }
  }

  if(globalChannel == 3){
    if(bits[9] == 0){
        delete[] bits;
        return F10; //CONVERSION ERROR - Y-Channel data not current
      }
    if(bits[8] == 0){
      delete[] bits;
      return F11;//CONVERSION ERROR - X-Channel data not current 
    } 
    else{
      delete[] bits;
      return SUCCESS; 
    }
  }

  if(globalChannel == 2){
    if(bits[9] == 0){
        delete[] bits;
        return F10; //CONVERSION ERROR - Y-Channel data not current
      }
    else{
      delete[] bits;
      return SUCCESS; 
    }
  }

  if(globalChannel == 1){
    if(bits[8] == 0){
      delete[] bits;
      return F11;//CONVERSION ERROR - X-Channel data not current 
    } 
    else{
      delete[] bits;
      return SUCCESS;
    }
  }
}

String afeStat(){ 
  byte CC_AFE = calculateCRC(AFE_STAT_REG, 0x0000, 0x00); // bei Test CMD immer 0x00 ; 
  int16_t AFEstat = readRegister(AFE_STAT_REG, 0x0000, CC_AFE);
  //int16_t AFEstat = 0b0000010000000010; //Test der Funktion (Fehler: z-axis test failed; trim data error)
  if(AFEstat == 0){
    return SUCCESS;
  }
  else{
    bool *bits;
    bits = getBits(AFEstat);
    if(bits[15] == 1){
      delete[] bits; 
      return F12; //AFE ERROR - Power down or brown-out
    } 
    if(bits[12] == 1){
      delete[] bits; 
      return F13; //AFE ERROR - sensor diagnostic test failed
    }
    if(globalTemp == true){
      if(bits[11] == 1){
        delete[] bits; 
        return F14; //AFE ERROR - temperature sensor diagnostic test failed 
      }
    }
    if(globalChannel == 4 || globalChannel == 5 || globalChannel == 6 || globalChannel == 7){
      if(bits[10] == 1){
      delete[] bits; 
      return F15; //AFE ERROR - z-axis sensor diagnostic test failed
      }
    }
    if(globalChannel == 2 || globalChannel == 3 || globalChannel == 6 || globalChannel == 7){
      if(bits[9] == 1){
      delete[] bits; 
      return F16; //AFE ERROR - y-axis sensor diagnostic test failed
      }
    }
    if(globalChannel == 1 || globalChannel == 3 || globalChannel == 5 || globalChannel == 7){
      if(bits[8] == 1){
      delete[] bits; 
      return F17; //AFE ERROR - x-axis sensor diagnostic test failed
      } 
    }
    if(bits[1] == 1){
      delete[] bits; 
      return F18; //AFE ERROR - trim data error
    } 
    if(bits[0] == 1){
      delete[] bits; 
      return F19; //AFE ERROR - fault in internal LDO supplied power
    } 
  }  
}

String sysStat(){ 
  byte CC_SYS = calculateCRC(SYS_STAT_REG, 0x0000, 0x00); 
  int16_t SYSstat = readRegister(SYS_STAT_REG, 0x0000, CC_SYS);
  //int16_t SYSstat = 0b0010100000000000; //Test der Funktion (Fehler: SDO drive error; incorrect number of clocks)
  bool *bits;
  bits = getBits(SYSstat);
  if(bits[13] == 0 && bits[12] == 0 && bits[11] == 0 && bits[5] == 0 && bits[4] == 0){
    delete[] bits;
    return SUCCESS;
  }
  if(bits[13] == 1){
    delete[] bits;
    return F20; //SYSTEM ERROR - SDO drive error detected
  } 
  if(bits[12] == 1){
    delete[] bits;
    return F21; //SYSTEM ERROR - CRC Error
  } 
  if(bits[11] == 1){
    delete[] bits;
    return F22; //SYSTEM ERROR - Incorrect number of clocks detected for a SPI transaction
  } 
  if(bits[5] == 1){
    delete[] bits;
    return F23; //SYSTEM ERROR - VCC over-voltage
  } 
  if(bits[4] == 1){
    delete[] bits;
    return F24; //SYSTEM ERROR - VCC under-voltage
  } 
  
}



// ====
// Funktionen zur Kommunikation mit TMAG5170, die mit Julia aufgerufen werden können (es folgen Ausgabefunktionen)
// ====

//Kommunikation mit Arduino 
String returnUniqueID(){
  String uniqueID = "";
  for (size_t i = 0; i < UniqueIDsize; i++) {
    if (UniqueID[i] < 0x10) {
      uniqueID += "0";
    }
    uniqueID += String(UniqueID[i], HEX);
    uniqueID += " ";
  }
  uniqueID.trim(); //Entferne Leerzeichen vorne und hinten
  return uniqueID;
}

String defaultConfig(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben 
    globalCRC = true; //CRC in Default immer aktiv 
    globalChannel = 7; //in Default immer alle Kanäle frei 
    globalTemp = true; //in Default Temperaturmessung freigeschaltet
    globalRange = 300; //in Default immer +-300mT

    int16_t dataCRC = 0b0000000001010000; //Default Bits für TEST_CONFIG Register
    int16_t dataSingDev = 0b0101000000101110; //Default Bits für DEV_CONFIG Register
    int16_t dataSens = 0b0000000111101010; //Default Bits für SENS_CONFIG Register
    int16_t dataSys = 0b0001000000100111; //Default Bits für SYS_CONFIG Register

    byte CRC = calculateCRC(TEST_CONF_REG, dataCRC, 0x00);
    bool write = writeRegister(TEST_CONF_REG, dataCRC, CRC);
    if (!write) return ERROR_WRITE;
    status = sysStat(); //System Status Register nach jedem writeRegister() auslesen zum Prüfen der Fehlerfreiheit des Prozess
    if (status != "F1") return status; 

    byte CRC_SingDev = calculateCRC(DEV_CONF_REG, dataSingDev, 0x00);
    write = writeRegister(DEV_CONF_REG, dataSingDev, CRC_SingDev);
    if (!write) return ERROR_WRITE;
    status = sysStat();
    if (status != "F1") return status; 

    byte CRC_Sens = calculateCRC(SENS_CONF_REG, dataSens, 0x00);
    write = writeRegister(SENS_CONF_REG, dataSens, CRC_Sens);
    if (!write) return ERROR_WRITE;
    status = sysStat();
    if (status != "F1") return status; 

    byte CRC_Sys = calculateCRC(SYS_CONF_REG, dataSys, 0x00);
    write = writeRegister(SYS_CONF_REG, dataSys, CRC_Sys);
    if (!write) return ERROR_WRITE;
    status = sysStat();
    if (status != "F1") return status; 

    status = afeStat(); //AFE Register einmal am Ende auslesen zu Prüfen der einzelnen Sensoreinheiten
    if(status != "F1"){
      return status;  
    }
    else {
      return SUCCESS;
    }
  }
}

String crc(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 1){
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    String *args;
    args = splitCommand(data);
    int ONOFF = convertStringToInt(args[0]);
    delete[] args;
    String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben   

    if(ONOFF == 0){ //DEFAULT: CRC freischalten
      globalCRC = true;
      byte CRC = calculateCRC(TEST_CONF_REG, 0x0050, 0x00);
      bool write = writeRegister(TEST_CONF_REG, 0x0050, CRC);  
      if (!write) return ERROR_WRITE;
      status = afeStat();
      if (status != "F1") return status; 
      status = sysStat();
      if (status != "F1") return status;
      return SUCCESS;
    }

    if(ONOFF == 1){ //CRC ausschalten
      globalCRC = false;
      byte CRC = calculateCRC(TEST_CONF_REG, 0x0054, 0x00);
      bool write = writeRegister(TEST_CONF_REG, 0x0054, CRC);
      if (!write) return ERROR_WRITE;
      status = afeStat();
      if (status != "F1") return status; 
      status = sysStat();
      if (status != "F1") return status;
      return SUCCESS;
    }

    else{
      return ERROR_INVALID_ARG;
    }
  }
}

String singleDeviceConfig(char *data){
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 6){  
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int samplesPerConv = convertStringToInt(args[0]); //Argumente des Benutzer auslesen 
    int tempCoeff = convertStringToInt(args[1]);
    int operatingMode = convertStringToInt(args[2]);
    int tempChan = convertStringToInt(args[3]);
    int tempRate = convertStringToInt(args[4]);
    int tempLimCheck = convertStringToInt(args[5]);
    delete[] args;
    uint16_t writeData = 0; //Variable für Daten die in Register geschrieben werden sollen 
    String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben 
   
    switch(samplesPerConv){
      case 0: 
        writeData = setBits(writeData, 14, 12, 0);
        break;
      case 1: 
        writeData = setBits(writeData, 14, 12, 1);
        break; 
      case 2: 
        writeData = setBits(writeData, 14, 12, 2);
        break; 
      case 3: 
        writeData = setBits(writeData, 14, 12, 3);
        break; 
      case 4: 
        writeData = setBits(writeData, 14, 12, 4);
        break; 
      case 5: 
        writeData = setBits(writeData, 14, 12, 5); //DEFAULT
        break; 
      default:
        return ERROR_INVALID_ARG;
    }

    switch(tempCoeff){
      case 0: 
        writeData = setBits(writeData, 9, 8, 0); //DEFAULT
        break;
      case 1: 
        writeData = setBits(writeData, 9, 8, 1); 
        break; 
      case 2: 
        writeData = setBits(writeData, 9, 8, 2);
        break; 
      case 3: 
        writeData = setBits(writeData, 9, 8, 3);
        break;   
      default:
        return ERROR_INVALID_ARG;
    }

    if(operatingMode == 0 || operatingMode == 1 || operatingMode == 3 || operatingMode == 4 || operatingMode == 5 || operatingMode == 6){
      return F25;//Modus nicht implementiert. Konfiguriere Single Device erneut mit operatingMode = 0x2"
    }
    else if(operatingMode == 2){
      writeData = setBits(writeData, 6, 4, 2); //DEFAULT
    }
    else{
      return ERROR_INVALID_ARG;
    }

    switch(tempChan){
      case 0: 
        globalTemp = false;
        writeData = setBits(writeData, 3, 3, 0);
        break;
      case 1: 
        globalTemp = true;
        writeData = setBits(writeData, 3, 3, 1); //DEFAULT
        break; 
      default:
        return ERROR_INVALID_ARG;
    }

    switch(tempRate){
      case 0: 
        writeData = setBits(writeData, 2, 2, 0);
        break;
      case 1: 
        writeData = setBits(writeData, 2, 2, 1); //DEFAULT
        break; 
      default:
        return ERROR_INVALID_ARG;
    }

    switch(tempLimCheck){
      case 0: 
        writeData = setBits(writeData, 1, 1, 0);
        break;
      case 1: 
        writeData = setBits(writeData, 1, 1, 1); //DEFAULT
        break; 
      default:
        return ERROR_INVALID_ARG;
    }

    //alle anderen Bits werden immer gleich gesetzt/ sind nicht von Benutzer beeinflussbar 
    writeData = setBits(writeData, 15, 15, 0); //Reserved Bit 
    writeData = setBits(writeData, 11, 10, 0); //Reserved Bits
    writeData = setBits(writeData, 7, 7, 0); //Reserved Bit 
    writeData = setBits(writeData, 0, 0, 0); //Reserved Bit 
    
    byte CRC = calculateCRC(DEV_CONF_REG, writeData, 0x00); 
    bool write = writeRegister(DEV_CONF_REG, writeData, CRC);
    if (!write) return ERROR_WRITE;
    status = afeStat();
    if (status != "F1") return status; 
    status = sysStat();
    if (status != "F1") return status;
    return SUCCESS;
  }
}

String sensConfig(char *data){
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 5){  
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int timeBetConvs = convertStringToInt(args[0]);
    int magChan = convertStringToInt(args[1]);
    int zRange = convertStringToInt(args[2]);
    int yRange = convertStringToInt(args[3]);
    int xRange = convertStringToInt(args[4]);
    delete[] args;

    if(zRange != yRange || zRange != xRange || xRange != yRange ){
      return F26; //Die Range aller drei Achsen muss gleich sein
    }
    else{
      if(zRange == 0) globalRange = 150; //+-150mT 
      if(zRange == 1) globalRange = 75; //+-75mT
      if(zRange == 2) globalRange = 300; //+-300mT 
      uint16_t writeData = 0; 
      String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben 

      switch(timeBetConvs){
        case 0:
          writeData = setBits(writeData, 13, 10, 0) ; //DEFAULT
          break;
        case 1: 
          writeData = setBits(writeData, 13, 10, 1);
          break;
        case 2: 
          writeData = setBits(writeData, 13, 10, 2);
          break; 
        case 3: 
          writeData = setBits(writeData, 13, 10, 3);
          break; 
        case 4: 
          writeData = setBits(writeData, 13, 10, 4);
          break;     
        case 5: 
          writeData = setBits(writeData, 13, 10, 5);
          break; 
        case 6: 
          writeData = setBits(writeData, 13, 10, 6);
          break; 
        case 7: 
          writeData = setBits(writeData, 13, 10, 7);
          break; 
        case 8: 
          writeData = setBits(writeData, 13, 10, 8);
          break; 
        case 9: 
          writeData = setBits(writeData, 13, 10, 9);
          break; 
        default:
          return ERROR_INVALID_ARG;
      }

      switch(magChan){
        case 0:
          return F27; //Mindestens ein Kanal muss freigeschaltet sein, sonst treten Fehler mit der Temperaturmessung auf 
        case 1: 
          globalChannel = 1; 
          writeData = setBits(writeData, 9, 6, 1);
          break;
        case 2: 
          globalChannel = 2;
          writeData = setBits(writeData, 9, 6, 2);
          break; 
        case 3: 
          globalChannel = 3;
          writeData = setBits(writeData, 9, 6, 3);
          break; 
        case 4: 
          globalChannel = 4;
          writeData = setBits(writeData, 9, 6, 4);
          break;     
        case 5: 
          globalChannel = 5;
          writeData = setBits(writeData, 9, 6, 5);
          break; 
        case 6: 
          globalChannel = 6;
          writeData = setBits(writeData, 9, 6, 6);
          break; 
        case 7: 
          globalChannel = 7;
          writeData = setBits(writeData, 9, 6, 7); //DEFAULT
          break; 
        default:
          return ERROR_INVALID_ARG; 
      }

      switch(zRange){
        case 0:
          writeData = setBits(writeData, 5, 4, 0) ;
          break;
        case 1: 
          writeData = setBits(writeData, 5, 4, 1);
          break;
        case 2: 
          writeData = setBits(writeData, 5, 4, 2); //DEFAULT
          break; 
        default:
          return ERROR_INVALID_ARG;
      }

      switch(yRange){
        case 0:
          writeData = setBits(writeData, 3, 2, 0) ;
          break;
        case 1: 
          writeData = setBits(writeData, 3, 2, 1);
          break;
        case 2: 
          writeData = setBits(writeData, 3, 2, 2); //DEFAULT
          break; 
        default:
          return ERROR_INVALID_ARG;
      }

      switch(xRange){
        case 0:
          writeData = setBits(writeData, 1, 0, 0) ;
          break;
        case 1: 
          writeData = setBits(writeData, 1, 0, 1);
          break;
        case 2: 
          writeData = setBits(writeData, 1, 0, 2); //DEFAULT
          break; 
        default:
          return ERROR_INVALID_ARG; 
      }

      //Keine Winkelmessung möglich, da die nötigen Funktionen dafür nicht implementiert sind
      writeData = setBits(writeData, 15, 14, 0);
      byte CRC = calculateCRC(SENS_CONF_REG, writeData, 0x00); 
      bool write = writeRegister(SENS_CONF_REG, writeData, CRC);
      if (!write) return ERROR_WRITE;
      status = afeStat();
      if (status != "F1") return status;
      status = sysStat();
      if (status != "F1") return status;
      return SUCCESS;
    }
  }
}

String sysConfig(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 5){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int diagMode = convertStringToInt(args[0]);
    int convStart = convertStringToInt(args[1]);
    int zLimCheck = convertStringToInt(args[2]);
    int yLimCheck = convertStringToInt(args[3]);
    int xLimCheck = convertStringToInt(args[4]);
    delete[] args;
    uint16_t writeData = 0; 
    String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben 

    switch(diagMode){
      case 0:
        writeData = setBits(writeData, 13, 12, 0);
        break;
      case 1: 
        writeData = setBits(writeData, 13, 12, 1); //DEFAULT
        break;
      case 2:
        writeData = setBits(writeData, 13, 12, 2);
        break;
      case 3: 
        writeData = setBits(writeData, 13, 12, 3);
        break;
      default:
        return ERROR_INVALID_ARG;
    }

    switch(convStart){
      case 0:
        writeData = setBits(writeData, 10, 9, 0); //DEFAULT
        break;
      case 1: 
        writeData = setBits(writeData, 10, 9, 1);
        break;
      default:
        return ERROR_INVALID_ARG;
    }

    switch(zLimCheck){
      case 0:
        writeData = setBits(writeData, 2, 2, 0) ;
        break;
      case 1: 
        writeData = setBits(writeData, 2, 2, 1); //DEFAULT
        break;
      default:
        return ERROR_INVALID_ARG; 
    }

    switch(yLimCheck){
      case 0:
        writeData = setBits(writeData, 1, 1, 0) ;
        break;
      case 1: 
        writeData = setBits(writeData, 1, 1, 1); //DEFAULT
        break;
      default:
        return ERROR_INVALID_ARG;;
    }

    switch(xLimCheck){
      case 0:
        writeData = setBits(writeData, 0, 0, 0) ;
        break;
      case 1: 
        writeData = setBits(writeData, 0, 0, 1); //DEFAULT
        break;
      default:
        return ERROR_INVALID_ARG;
    }

    //alle anderen Bits werden immer gleich gesetzt/ nicht von Benutzer beeinflussbar 
    writeData = setBits(writeData, 15, 14, 0); //Reserved Bits
    writeData = setBits(writeData, 11, 11, 0); // Reserved Bit 
    writeData = setBits(writeData, 8, 6, 0); //DATA_TYPE -> muss 0 sein, damit read und write fehlerfrei laufen 
    writeData = setBits(writeData, 5, 5, 1); //AFE Tests werden immer durchgeführt 
    writeData = setBits(writeData, 4, 3, 0); //Reserved Bits
    byte CRC = calculateCRC(SYS_CONF_REG, writeData, 0x00); 
    bool write = writeRegister(SYS_CONF_REG, writeData, CRC);
    if (!write) return ERROR_WRITE;
    status = afeStat();
    if (status != "F1") return status; 
    status = sysStat();
    if (status != "F1") return status;
    return SUCCESS;
  }
}
    
String readReg(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 1){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int reg = convertStringToInt(args[0]);
    delete[] args;

    if(reg!=DEV_CONF_REG+0x80 && reg!=SENS_CONF_REG+0x80 && reg!=SYS_CONF_REG+0x80 && reg!=CONV_STAT_REG && reg!=X_REG && reg!=Y_REG && reg!=Z_REG && reg!=T_REG && reg!=AFE_STAT_REG && reg!=SYS_STAT_REG && reg!=TEST_CONF_REG+0x80 && reg!=OSC_REG){
      return ERROR_INVALID_ARG;
    }

    else{
      //Kopien der aktuellen globalen Variablen, da sie in Funktion geändert werden, 
      //aber am Ende wieder Ist-Zustand hergestellt werden muss 
      int globalChannelcopy = globalChannel; 
      int globalTempcopy = globalTemp;
      String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben

      if(reg == X_REG){
        if(globalChannel == 2 || globalChannel == 4 || globalChannel == 6 || globalChannel == 0){
          return ERROR_CHANNEL_DISABLED;
        }
        else{
          globalTemp = false; //X_REG ist X-Kanal, dann muss Temperatursensor nicht geprüft werden
          globalChannel = 1; //1 = nur x-Kanal, damit nur x-Kanal Sensor bei conv_stat geprüft wird 
        }
      }
      if(reg == Y_REG){
        if(globalChannel == 1 || globalChannel == 4 || globalChannel == 5 || globalChannel == 0){
          return ERROR_CHANNEL_DISABLED;
        }
        else{
          globalTemp = false; 
          globalChannel = 2; 
        }
      }
      if(reg == Z_REG){
        if(globalChannel == 1 || globalChannel == 2 || globalChannel == 3 || globalChannel == 0){
          return ERROR_CHANNEL_DISABLED;
        }
        else{
          globalTemp = false; 
          globalChannel = 4; 
        }
      }
      if(reg == T_REG){
        if(globalTemp == false){
          return ERROR_CHANNEL_DISABLED;
        }
        else{
          globalTemp = true; 
          globalChannel = 0;      
        }   
      }
  
      byte CRC = calculateCRC(reg, 0x0000, 0x00);
      uint16_t registerBits = readRegister(reg, 0x0000, CRC);   
      bool *bits;
      bits = getBits(registerBits); 
      status = convStat(); 
      if (status != "F1"){
        delete[] bits;
        globalTemp = globalTempcopy; //Ist-Zustand wieder herstellen 
        globalChannel = globalChannelcopy;
        return status;
      }
      status = afeStat();
      if (status != "F1"){
        delete[] bits;
        globalTemp = globalTempcopy; //Ist-Zustand wieder herstellen 
        globalChannel = globalChannelcopy;
        return status;
      } 
      status = sysStat();
      if (status != "F1"){
        delete[] bits;
        globalTemp = globalTempcopy; //Ist-Zustand wieder herstellen 
        globalChannel = globalChannelcopy;
        return status;
      }
      
      String ergebnis = "";
      for(int i = 15; i>=0; i--){
        ergebnis += bits[i];
      }
      delete[] bits;
      globalTemp = globalTempcopy; //Ist-Zustand wieder herstellen 
      globalChannel = globalChannelcopy;
      return ergebnis; 
    }    
  }
}

String readTemp(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    if(globalTemp == true){
      int globalChannelcopy = globalChannel; 
      globalChannel = 0; //wenn Temperatur ausgelesen wird, müssen Magnetfeldsensoren nicht geprüft werden 
      byte CRC = calculateCRC(T_REG, 0x0000, 0x00);
      int16_t tempBits = readRegister(T_REG, 0x0000, CRC);
      int16_t tempResult = 25 + (tempBits - 17522)/60; //Formel aus Datasheet
      String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben
      
      // wenn Temperatur ausgelesen wird kein ConvStat nötig (weggelassen da sonst Fehler)
      status = afeStat();
      if (status != "F1"){
        globalChannel = globalChannelcopy;
        return status;
      } 
      status = sysStat();
      if (status != "F1"){
        globalChannel = globalChannelcopy;
        return status;
      }
     
      globalChannel = globalChannelcopy;
      return String(tempResult);
    }
    else{
      return ERROR_CHANNEL_DISABLED; 
    }
  }
}

String getFieldValueX(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    if(globalChannel == 1 || globalChannel == 3 || globalChannel == 5 || globalChannel == 7){
      int globalChannelcopy = globalChannel; 
      int globalTempcopy = globalTemp;
      globalTemp = false;
      globalChannel = 1; 
      byte CRC = calculateCRC(X_REG, 0x0000, 0x00);
      int16_t xAchse = readRegister(X_REG, 0x0000, CRC);
      float ergebnisX = flussdichte(xAchse);
      String conv = convStat();
      String afe = afeStat(); 
      String sys = sysStat();
      globalChannel = globalChannelcopy;
      globalTemp = globalTempcopy;
      if(conv == "F1" && afe == "F1" && sys == "F1"){
        return String(ergebnisX);
      }
      else{
        if(conv != "F1") return conv; 
        if(afe != "F1") return afe;
        if(sys != "F1") return sys;
      }
    }
    else{
      return ERROR_CHANNEL_DISABLED;
    }
  }
}

String getFieldValueY(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    if(globalChannel == 2 || globalChannel == 3 || globalChannel == 6 || globalChannel == 7){
      int globalChannelcopy = globalChannel; 
      int globalTempcopy = globalTemp;
      globalTemp = false;
      globalChannel = 2; 
      byte CRC = calculateCRC(Y_REG, 0x0000, 0x00);
      int16_t yAchse = readRegister(Y_REG, 0x0000, CRC);
      float ergebnisY = flussdichte(yAchse);
      String conv = convStat();
      String afe = afeStat(); 
      String sys = sysStat();
      globalChannel = globalChannelcopy;
      globalTemp = globalTempcopy;
      if(conv == "F1" && afe == "F1" && sys == "F1"){
        return String(ergebnisY);
      }
      else{
        if(conv != "F1") return conv; 
        if(afe != "F1") return afe;
        if(sys != "F1") return sys;
      }
    } 
    else{
      return ERROR_CHANNEL_DISABLED;
    }
  }
}

String getFieldValueZ(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    if(globalChannel == 4 || globalChannel == 5 || globalChannel == 6 || globalChannel == 7){
      int globalChannelcopy = globalChannel; 
      int globalTempcopy = globalTemp;
      globalTemp = false;
      globalChannel = 4; 
      byte CRC = calculateCRC(Z_REG, 0x0000, 0x00);
      int16_t zAchse = readRegister(Z_REG, 0x0000, CRC);
      float ergebnisZ = flussdichte(zAchse);
      String conv = convStat();
      String afe = afeStat(); 
      String sys = sysStat();
      globalChannel = globalChannelcopy;
      globalTemp = globalTempcopy;
      if(conv == "F1" && afe == "F1" && sys == "F1"){
        return String(ergebnisZ);
      }
      else{
        if(conv != "F1") return conv; 
        if(afe != "F1") return afe;
        if(sys != "F1") return sys;
      }
    }
    else{
      return ERROR_CHANNEL_DISABLED;
    }
  }
}

String getFieldValueXYZ(char *data){ 
  unsigned long start; 
  unsigned long zeit;  

  bool status = true;
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    return ERROR_NUMBER_OF_ARGS;  
  }
  else{
    if(!(globalChannel == 7)){
      return ERROR_CHANNEL_DISABLED;
    }
    else{
      String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben 
      int globalTempcopy = globalTemp;
      int globalChannelcopy = globalChannel;
      globalTemp = false;
      globalChannel = 1;
      byte CC_X = calculateCRC(X_REG, 0x0000, 0x00);
      int16_t xAchse = readRegister(X_REG, 0x0000, CC_X);
      float ergebnisX = flussdichte(xAchse);
      status = convStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = afeStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = sysStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      globalChannel = 2;  
      byte CC_Y = calculateCRC(Y_REG, 0x0000, 0x00);
      int16_t yAchse = readRegister(Y_REG, 0x0000, CC_Y);
      float ergebnisY = flussdichte(yAchse);
      status = convStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = afeStat();
      if (status != "F1"){
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = sysStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      globalChannel = 4;
      byte CC_Z = calculateCRC(Z_REG, 0x0000, 0x00);
      int16_t zAchse = readRegister(Z_REG, 0x0000, CC_Z);
      float ergebnisZ = flussdichte(zAchse);

      status = convStat();
      if (status != "F1"){
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = afeStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
      status = sysStat();
      if (status != "F1"){ 
        globalChannel = globalChannelcopy;
        globalTemp = globalTempcopy;
        return status;}
  
      globalTemp = globalTempcopy;
      globalChannel = globalChannelcopy;
      String result = "*" + String(ergebnisX, 9) + "<" + String(ergebnisY, 9) + ">" + String(ergebnisZ, 9) + "#";

      return result;
    }
  }
}

// std::array<int16_t, 3> getFieldValueXYZFast(char *data){ 
uint64_t getFieldValueXYZFast(char *data){ 
  // unsigned long start; 
  // unsigned long zeit;  

  // start = millis(); 
  // auto start_test = micros();
  // bool status = true;  
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    SERIAL.println("noOfArgs");
    // return ERROR_NUMBER_OF_ARGS;
    // return {0,0,0};  
    return 0;
  }
  else{
    if(!(globalChannel == 7)){
      SERIAL.println("globalChannel");
      // return ERROR_CHANNEL_DISABLED;
      // return {0,0,0};
      return 0;
    }
    else{
      // String status = "F1"; //"F1" bedeutet kein Fehler, bei Fehler wird F1 überschrieben
      int globalTempcopy = globalTemp;
      int globalChannelcopy = globalChannel;
      globalTemp = false;

      // CONV_STAT/AFE_STAT/SYS_STAT are "read to clear" registers (see the
      // comment in selectChip()). getFieldValueXYZ() reads them after every
      // axis and that path returns fresh data; this function used to skip
      // them entirely, which left the X/Y/Z registers latched on whatever
      // was last read during the one-time setup() init and made every
      // triggered frame return that identical stale reading. Read (and
      // discard, for speed) the same status registers here so the chip
      // actually latches a new conversion each time.
      globalChannel = 1;
      byte CC_X = calculateCRC(X_REG, 0x0000, 0x00);
      uint16_t xAchse = readRegister(X_REG, 0x0000, CC_X);
      readRegister(CONV_STAT_REG, 0x0000, calculateCRC(CONV_STAT_REG, 0x0000, 0x00));
      readRegister(AFE_STAT_REG, 0x0000, calculateCRC(AFE_STAT_REG, 0x0000, 0x00));
      readRegister(SYS_STAT_REG, 0x0000, calculateCRC(SYS_STAT_REG, 0x0000, 0x00));

      globalChannel = 2;
      byte CC_Y = calculateCRC(Y_REG, 0x0000, 0x00);
      uint16_t yAchse = readRegister(Y_REG, 0x0000, CC_Y);
      readRegister(CONV_STAT_REG, 0x0000, calculateCRC(CONV_STAT_REG, 0x0000, 0x00));
      readRegister(AFE_STAT_REG, 0x0000, calculateCRC(AFE_STAT_REG, 0x0000, 0x00));
      readRegister(SYS_STAT_REG, 0x0000, calculateCRC(SYS_STAT_REG, 0x0000, 0x00));

      globalChannel = 4;
      byte CC_Z = calculateCRC(Z_REG, 0x0000, 0x00);
      uint16_t zAchse = readRegister(Z_REG, 0x0000, CC_Z);
      readRegister(CONV_STAT_REG, 0x0000, calculateCRC(CONV_STAT_REG, 0x0000, 0x00));
      readRegister(AFE_STAT_REG, 0x0000, calculateCRC(AFE_STAT_REG, 0x0000, 0x00));
      readRegister(SYS_STAT_REG, 0x0000, calculateCRC(SYS_STAT_REG, 0x0000, 0x00));

      globalTemp = globalTempcopy;
      globalChannel = globalChannelcopy;

      return ((uint64_t)xAchse) | ((uint64_t)yAchse << 16) | ((uint64_t)zAchse << 32);
    }
  }
}


String initAllSensorsArduino(char *data){
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 1){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int range = convertStringToInt(args[0]);
    delete[] args;
    String message = "";

    //Initialisieren aller Sensoren 
    for(int i = 0; i < 37; i++){  
      String index = String(sensors[i], HEX);
      String befehl = "*SELECTCHIP!>0x" + index + "#"; //bei jeder Iteration neuer Sensorindex
      char befehl_c[befehl.length() + 1]; //Buffer der entsprechenden Größe für befehl als char-Array 
      befehl.toCharArray(befehl_c, sizeof(befehl_c));
      message = selectChip(befehl_c);
      if (message != "F1") return message;
      message = deleteErrors("*DELETEERRORS!#");
      if (message != "F1") return message;
      message = oscInCheck("*OSCIC?>0x0#");
      if (message != "F1") return message;
      message = oscInCheck("*OSCIC?>0x1#");
      if (message != "F1") return message; 
      //Defaultkonfiguration 
      message = defaultConfig("*DEFAULTCONF!#");
      if (message != "F1") return message;
        //ggf. Messbereichanpassen 
      if (range == 0){ //Range +-150mT
        message = sensConfig("*SENSCONF!>0x0|0x7|0x0|0x0|0x0#");
        if (message != "F1") return ("Fehler SENSCONF: " + message);
      }
      else if (range == 1){ //Range +-75mT
        message = sensConfig("*SENSCONF!>0x0|0x7|0x1|0x1|0x1#");
        if (message != "F1") return ("Fehler SENSCONF: " + message);
      }
      else if (range == 2){ //Range +-300T
        //300mT ist schon eingestellt, nichts ändern
      }
      else{
        return ERROR_INVALID_ARG; 
      }
    }
    return SUCCESS; 
  }
}

String checkInit(char *data){
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 1){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int rangeSoll = convertStringToInt(args[0]);
    delete[] args;
    String message = "";

    for(int i = 0; i < 37; i++){  
      String index = String(sensors[i], HEX);
      String befehl = "*SELECTCHIP!>0x" + index + "#"; //bei jeder Iteration neuer Sensorindex
      char befehl_c[befehl.length() + 1]; //Buffer der entsprechenden Größe für befehl als char-Array 
      befehl.toCharArray(befehl_c, sizeof(befehl_c));
      message = selectChip(befehl_c);
      if (message != "F1") return message;
      String rangeIst = range("*RANGE?#");
      if (rangeIst == "150" && rangeSoll != 0) return F28;
      else if (rangeIst == "75" && rangeSoll != 1) return F28;
      else if (rangeIst == "300" && rangeSoll != 2) return F28;
      else return SUCCESS;
    }
  }
}

String allSensorsArduino(char *data){ 
  unsigned long startGes; 
  unsigned long zeitGes;
  unsigned long startAus; 
  unsigned long zeitAus;
  startGes = millis();

  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 2){ 
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    String *args;
    args = splitCommand(data);
    int range = convertStringToInt(args[0]);
    bool init = convertStringToInt(args[1]);
    delete[] args;

    String message = "";
    String ergebnis = "\n\n"; 

    if (init == 1){
      String rangeStr = String(range, HEX);
      String befehl = "INITALLSENSORS!>0x" + rangeStr + "#";
      char befehl_c[befehl.length() + 1]; 
      befehl.toCharArray(befehl_c, sizeof(befehl_c));
      message = initAllSensorsArduino(befehl_c);
      if (message != "F1") return message;
    }
    else if (init == 0){ 
      String rangeStr = String(range, HEX);
      String befehl = "CHECKINIT!>0x" + rangeStr + "#";
      char befehl_c[befehl.length() + 1]; 
      befehl.toCharArray(befehl_c, sizeof(befehl_c));
      message = checkInit(befehl_c);
      if (message != "F1") return message;
      //sonst direkt auslesen 
    }
    else {
      return ERROR_INVALID_ARG; 
    }


    //Auslesen aller Sensoren
    startAus = millis();

    for(int i = 0; i < 37; i++){ 
      String index = String(sensors[i], HEX);
      String befehl = "*SELECTCHIP!>0x" + index + "#";
      char befehl_c[befehl.length() + 1]; 
      befehl.toCharArray(befehl_c, sizeof(befehl_c));
      message = selectChip(befehl_c);
      if (message != "F1") return message;
      String magnetfeld = getFieldValueXYZ("*GETFIELDVALUEXYZ?#");
      if (magnetfeld.indexOf("F") != -1){ //wenn "F" in magnetfeld vorhanden, ist es eine Fehlermeldung 
        return magnetfeld; 
      }
      ergebnis += magnetfeld;
      ergebnis += "\n";
    }
    zeitAus = millis() - startAus; 
    ergebnis += "\nZeit Auslesen(IDE):" + String(zeitAus) + "ms";
    zeitGes = millis() - startGes; 
    ergebnis += "\nZeit gesamt(IDE):" + String(zeitGes) + "ms";  
    return ergebnis; 
  } 
}

String operatingMode(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){
    return ERROR_NUMBER_OF_ARGS;
  }
  else{
    byte CC_SYS = calculateCRC(SYS_STAT_REG, 0x0000, 0x00); 
    int16_t SYSstat = readRegister(SYS_STAT_REG, 0x0000, CC_SYS);
    //int16_t SYSstat = 0b0010100000000000; //Test der Funktion (Fehler: SDO drive error; incorrect number of clocks)
    bool *bits;
    bits = getBits(SYSstat);
    
    String afe = afeStat(); 
    String sys = sysStat();
    if(afe == "F1" && sys == "F1"){
      if(bits[10] == 0 && bits[9] == 0 && bits[8] == 0){
        delete[] bits;
        return "Achtung Config state";
      }
      if(bits[10] == 0 && bits[9] == 0 && bits[8] == 1){
        delete[] bits;
        return "Achtung Standby state";
      }
      if(bits[10] == 0 && bits[9] == 1 && bits[8] == 0){
        delete[] bits;
        return  SUCCESS; //nur active measure state implementiert, also ist dieser Modus der richtige -> Erfolgsmeldung 
      }
      if(bits[10] == 0 && bits[9] == 1 && bits[8] == 1){
        delete[] bits;
        return "Achtung Active triggered mode state";
      }
      if(bits[10] == 1 && bits[9] == 0 && bits[8] == 0){
        delete[] bits;
        return "Achtung DCM active state";
      }
      if(bits[10] == 1 && bits[9] == 0 && bits[8] == 1){
        delete[] bits;
        return "Achtung DCM sleep state";
      }
      if(bits[10] == 1 && bits[9] == 1 && bits[8] == 0){
        delete[] bits;
        return "Achtung Sleep state";
      }
    }
    else{
      delete[] bits;
      if(afe != "F1") return afe;
      if(sys != "F1") return sys;
    }
  }
}

String oscInCheck(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs != 1){ 
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    String *args;
    args = splitCommand(data);
    int lowHigh = convertStringToInt(args[0]);

    delete[] args;

    unsigned long f_high_max_ms = 3500000; //HFOSC f_max = 3,5 MHz = 3500000 1/ms
    float f_low_max_ms = 19.5; //LFOSC f_max = 19,5 KHz = 19.5 1/ms
    unsigned long timer = 0; //timer Variable, um Zeit für Counter zu stoppen

    byte CRC = calculateCRC(TEST_CONF_REG, 0b0000000001010000, 0x00);
    bool write = writeRegister(TEST_CONF_REG, 0b0000000001010000, CRC); //reset Counter
    if (!write) return ERROR_WRITE;

    if(lowHigh == 0){
      byte CCstart = calculateCRC(TEST_CONF_REG, 0b0000000001010010, 0x00);
      timer = millis(); //Anzahl der Millisekunden seit Programmstart 
      write = writeRegister(TEST_CONF_REG, 0b0000000001010010, CCstart); //startet Counter für LFOSC    
      if (!write) return ERROR_WRITE;

      byte CCstopp = calculateCRC(TEST_CONF_REG, 0b0000000001010011, 0x00);
      //wenn bestimmte Zeit abgelaufen, wird Counter gestoppt 
      if(millis() == timer + 1){ //Zeit für LFOSC 1 ms
        write = writeRegister(TEST_CONF_REG, 0b0000000001010011, CCstopp); //stoppt Counter 
        if (!write) return ERROR_WRITE;
      }
      
      byte CCRead = calculateCRC(OSC_REG, 0b0000000001010000, 0x00);
      uint16_t counts = readRegister(OSC_REG, 0b0000000001010000, CCRead);
      //uint16_t counts = 0b000000000010100; //Testbedingung: Zeit = 1ms --> weniger als 19.5 counts, um unter 19,5 KHz zu bleiben; hier Test mit 20 Counts

      float frequenz = counts/1; //Zeit in ms (1 ms) also Frequenz in 1/ms 
      String afe = afeStat(); 
      String sys = sysStat();
      if(afe == "F1" && sys == "F1"){
        if(frequenz > f_low_max_ms){ 
          return ERROR_OSCI; 
        }
        else{
          return SUCCESS; 
        }
      }
      else{
        if(afe != "F1") return afe;
        if(sys != "F1") return sys; 
      }
    }

    if(lowHigh == 1){
      byte CCstart = calculateCRC(TEST_CONF_REG, 0b0000000001010001, 0x00);
      timer = millis(); 
      bool write = writeRegister(TEST_CONF_REG, 0b0000000001010001, CCstart); //startet Counter für HFOSC  
      if (!write) return ERROR_WRITE;

      byte CCstopp = calculateCRC(TEST_CONF_REG, 0b0000000001010011, 0x00);
      if(millis() == timer + 0.01){ //Zeit für HFOSC 0.01 ms
        bool write = writeRegister(TEST_CONF_REG, 0b0000000001010011, CCstopp); //stoppt Counter 
        if (!write) return ERROR_WRITE;
      }

      byte CCRead = calculateCRC(OSC_REG, 0b0000000001010000, 0x00);
      uint16_t counts = readRegister(OSC_REG, 0b0000000001010000, CCRead);
      //uint16_t counts = 0b1000100010111001; //Testbedingung: Zeit = 0.01 ms --> weniger als 35000 counts um unter 3,5MHz zu bleiben; hier Test mit 35001 Counts

      double frequenz = counts/0.01; //Zeit in ms  
      String afe = afeStat(); 
      String sys = sysStat();
      if(afe == "F1" && sys == "F1"){
        if(frequenz > f_high_max_ms){
          return ERROR_OSCI; 
        }
        else{
          return SUCCESS;  
        }
      }
      else{
        if(afe != "F1") return afe;
        if(sys != "F1") return sys;  
      }
    }

    else{
      return ERROR_INVALID_ARG; 
    }
  }
}

void showCRCConfigs(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
    SERIAL.println(ERROR_NUMBER_OF_ARGS);
  }
  else{
    String configs = "";
    configs += "Die folgenden CRC Einstellungen sind aktuell: \n \n";

    byte CRC_Test = calculateCRC(TEST_CONF_REG+0x80, 0x0000, 0x00);
    int16_t test = readRegister(TEST_CONF_REG+0x80, 0x0000, CRC_Test);
    bool *bits;
    bits = getBits(test);

    if(bits[2] == 0) configs += "\t ON/OFF = CRC freigeschaltet \n";
    else configs += "\t ON/OFF = CRC ausgeschaltet \n";

    delete[] bits;

    String afe = afeStat(); 
    String sys = sysStat();
    if(afe == "F1" && sys == "F1"){
      SERIAL.println(configs);
    }
    else{
      if(afe != "F1") SERIAL.println(afe);
      if(sys != "F1") SERIAL.println(sys); 
    }
  }
}

void showSingDevConfigs(char *data){  
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
     SERIAL.println(ERROR_NUMBER_OF_ARGS);
  }
  else{
    String configs = "";
    configs += "Die folgenden Single Device Einstellungen sind aktuell: \n \n";

    byte CRC_SingDev = calculateCRC(DEV_CONF_REG+0x80, 0x0000, 0x00);
    int16_t SingDev = readRegister(DEV_CONF_REG+0x80, 0x0000, CRC_SingDev);
    bool *bits;
    bits = getBits(SingDev);

    if(bits[14] == 0 && bits[13] == 0 && bits[12] == 0) configs += "\t samplesPerConv = 1 Abtastung/Conv\n";
    if(bits[14] == 0 && bits[13] == 0 && bits[12] == 1) configs += "\t samplesPerConv = 2 Abtastungen/Conv\n"; 
    if(bits[14] == 0 && bits[13] == 1 && bits[12] == 0) configs += "\t samplesPerConv = 4 Abtastungen/Conv\n"; 
    if(bits[14] == 0 && bits[13] == 1 && bits[12] == 1) configs += "\t samplesPerConv = 8 Abtastungen/Conv\n"; 
    if(bits[14] == 1 && bits[13] == 0 && bits[12] == 0) configs += "\t samplesPerConv = 16 Abtastungen/Conv\n"; 
    if(bits[14] == 1 && bits[13] == 0 && bits[12] == 1) configs += "\t samplesPerConv = 32 Abtastungen/Conv\n"; 
    if(bits[9] == 0 && bits[8] == 0) configs += "\t tempCoeff = 0%/°C\n";
    if(bits[9] == 0 && bits[8] == 1) configs += "\t tempCoeff = 0.12%/°C (NdBFe)\n";
    if(bits[9] == 1 && bits[8] == 0) configs += "\t tempCoeff = 0.03%/°C (SmCo)\n";
    if(bits[9] == 1 && bits[8] == 1) configs += "\t tempCoeff = 0.2%/°C (Ceramics)\n";
    if(bits[6] == 0 && bits[5] == 0 && bits[4] == 0) configs += "\t operMode = Configuration mode\n";
    if(bits[6] == 0 && bits[5] == 0 && bits[4] == 1) configs += "\t operMode = Stand-by mode\n";
    if(bits[6] == 0 && bits[5] == 1 && bits[4] == 0) configs += "\t operMode = Active measure mode\n";
    if(bits[6] == 0 && bits[5] == 1 && bits[4] == 1) configs += "\t operMode = Active trigger mode\n";
    if(bits[6] == 1 && bits[5] == 0 && bits[4] == 0) configs += "\t operMode = Wake up and sleep mode\n";
    if(bits[6] == 1 && bits[5] == 0 && bits[4] == 1) configs += "\t operMode = Sleep mode\n";
    if(bits[6] == 1 && bits[5] == 1 && bits[4] == 0) configs += "\t operMode = Deep sleep mode\n";
    if(bits[3] == 0) configs += "\t tempChan = Temperaturkanal aus\n";
    if(bits[3] == 1) configs += "\t tempChan = Temperaturkanal frei\n";
    if(bits[2] == 0) configs += "\t tempRate = Temperaturabtastrate entspricht Abtastrate der Magnetfeldachsen\n";
    if(bits[2] == 1) configs += "\t tempRate = 1 Temperaturmessung/Conversion\n";
    if(bits[1] == 0) configs += "\t tempLimCheck = Temperatur Limit Check aus\n";
    if(bits[1] == 1) configs +=  "\t tempLimCheck = Temperatur Limit Check frei\n";

    delete[] bits;

    String afe = afeStat(); 
    String sys = sysStat();
    if(afe == "F1" && sys == "F1"){
      SERIAL.println(configs); 
    }
    else{
      if(afe != "F1") SERIAL.println(afe);
      if(sys != "F1") SERIAL.println(sys); 
    }
  }
}

void showSensConfigs(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){  
     SERIAL.println(ERROR_NUMBER_OF_ARGS);
  }
  else{
    String configs = "";
    configs += "Die folgenden Sensor Einstellungen sind aktuell: \n \n";

    byte CRC_Sens = calculateCRC(SENS_CONF_REG+0x80, 0x0000, 0x00);
    int16_t Sens = readRegister(SENS_CONF_REG+0x80, 0x0000, CRC_Sens);
    bool *bits;
    bits = getBits(Sens);

    if(bits[13] == 0 && bits[12] == 0 && bits[11] == 0 && bits[10] == 0) configs += "\t timeBetConvs = 1ms \n";
    if(bits[13] == 0 && bits[12] == 0 && bits[11] == 0 && bits[10] == 1) configs += "\t timeBetConvs = 5ms \n";
    if(bits[13] == 0 && bits[12] == 0 && bits[11] == 1 && bits[10] == 0) configs += "\t timeBetConvs = 10ms \n";
    if(bits[13] == 0 && bits[12] == 0 && bits[11] == 1 && bits[10] == 1) configs += "\t timeBetConvs = 15ms \n";
    if(bits[13] == 0 && bits[12] == 1 && bits[11] == 0 && bits[10] == 0) configs += "\t timeBetConvs = 20ms \n";
    if(bits[13] == 0 && bits[12] == 1 && bits[11] == 0 && bits[10] == 1) configs += "\t timeBetConvs = 30ms \n";   
    if(bits[13] == 0 && bits[12] == 1 && bits[11] == 1 && bits[10] == 0) configs += "\t timeBetConvs = 50ms \n";
    if(bits[13] == 0 && bits[12] == 1 && bits[11] == 1 && bits[10] == 1) configs += "\t timeBetConvs = 100ms \n";
    if(bits[13] == 1 && bits[12] == 0 && bits[11] == 0 && bits[10] == 0) configs += "\t timeBetConvs = 500ms \n";
    if(bits[13] == 1 && bits[12] == 0 && bits[11] == 0 && bits[10] == 1) configs += "\t timeBetConvs = 1000ms \n";
    if(bits[9] == 0 && bits[8] == 0 && bits[7] == 0 && bits[6] == 0) configs += "\t magChan = keine Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 0 && bits[7] == 0 && bits[6] == 1) configs += "\t magChan = x-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 0 && bits[7] == 1 && bits[6] == 0) configs += "\t magChan = y-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 0 && bits[7] == 1 && bits[6] == 1) configs += "\t magChan = x- und y-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 1 && bits[7] == 0 && bits[6] == 0) configs += "\t magChan = z-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 1 && bits[7] == 0 && bits[6] == 1) configs += "\t magChan = x- und z-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 1 && bits[7] == 1 && bits[6] == 0) configs += "\t magChan = y- und z-Achse freigeschaltet \n";
    if(bits[9] == 0 && bits[8] == 1 && bits[7] == 1 && bits[6] == 1) configs += "\t magChan = x- und y- und z-Achse freigeschaltet \n";
    if(bits[5] == 0 && bits[4] == 0) configs += "\t zRange = +/- 150mT \n";
    if(bits[5] == 0 && bits[4] == 1) configs += "\t zRange = +/- 75mT \n";
    if(bits[5] == 1 && bits[4] == 0) configs += "\t zRange = +/- 300mT \n";
    if(bits[3] == 0 && bits[2] == 0) configs += "\t yRange = +/- 150mT \n";
    if(bits[3] == 0 && bits[2] == 1) configs += "\t yRange = +/- 75mT \n";
    if(bits[3] == 1 && bits[2] == 0) configs += "\t yRange = +/- 300mT \n";
    if(bits[1] == 0 && bits[0] == 0) configs += "\t xRange = +/- 150mT \n";
    if(bits[1] == 0 && bits[0] == 1) configs += "\t xRange = +/- 75mT \n";
    if(bits[1] == 1 && bits[0] == 0) configs += "\t xRange = +/- 300mT \n";

    delete[] bits;

    String afe = afeStat(); 
    String sys = sysStat();
    if(afe == "F1" && sys == "F1"){
      SERIAL.println(configs); 
    }
    else{
      if(afe != "F1") SERIAL.println(afe);
      if(sys != "F1") SERIAL.println(sys); 
    }
  }
}

void showSysConfigs(char *data){ 
  int noOfArgs = numberOfArgumentsInCommand(data);
  if (noOfArgs > 0){ 
    SERIAL.println(ERROR_NUMBER_OF_ARGS);
  }
  else{
    String configs = "";
    configs += "Die folgenden System Einstellungen sind aktuell: \n \n";

    byte CRC_Sys = calculateCRC(SYS_CONF_REG+0x80, 0x0000, 0x00);
    int16_t Sys = readRegister(SYS_CONF_REG+0x80, 0x0000, CRC_Sys);
    bool *bits;
    bits = getBits(Sys);

    if(bits[13] == 0 && bits[12] == 0) configs += "\t diagMode = Alle Diagnostiktests gleichzeitig\n";
    if(bits[13] == 0 && bits[12] == 1) configs += "\t diagMode = Freigeschaltete Diagnostiktests gleichzeitig\n";
    if(bits[13] == 1 && bits[12] == 0) configs += "\t diagMode = Alle Diagnostiktests sequentiell\n";
    if(bits[13] == 1 && bits[12] == 1) configs += "\t diagMode = Freigeschaltete Diagnostiktests sequentiell\n";
    if(bits[10] == 0 && bits[9] == 0) configs += "\t convStart = Conversion Start bei SPI command\n";
    if(bits[10] == 0 && bits[9] == 1) configs += "\t convStart = Conversion Start bei ChipSelect Puls\n";
    if(bits[10] == 1 && bits[9] == 0) configs += "\t convStart = Conversion Start bei Alert Puls\n";
    if(bits[2] == 0) configs += "\t zLimCheck = Z-Achsen Limit Check aus\n";
    if(bits[2] == 1) configs += "\t zLimCheck = Z-Achsen Limit Check frei\n";
    if(bits[1] == 0) configs += "\t yLimCheck = Y-Achsen Limit Check aus\n";
    if(bits[1] == 1) configs += "\t yLimCheck = Y-Achsen Limit Check frei\n";
    if(bits[0] == 0) configs += "\t xLimCheck = X-Achsen Limit Check aus\n";
    if(bits[0] == 1) configs += "\t xLimCheck = X-Achsen Limit Check frei\n";

    delete[] bits;

    String afe = afeStat(); 
    String sys = sysStat();
    if(afe == "F1" && sys == "F1"){
      SERIAL.println(configs);
    }
    else{
      if(afe != "F1") SERIAL.println(afe);
      if(sys != "F1") SERIAL.println(sys); 
    }
  }
}

String selectChip(char *data){
  int noOfArgs = numberOfArgumentsInCommand(data);
  if(noOfArgs != 1){
    return ERROR_NUMBER_OF_ARGS; 
  }
  else{
    String *args; 
    args = splitCommand(data);
    chipSelect = convertStringToInt(args[0]);
    delete[] args;
    return SUCCESS;   
  }
}

String deleteErrors(char *data){ 
  byte CRC = calculateCRC(TEST_CONF_REG, 0x0054, 0x00);
  writeRegister(TEST_CONF_REG, 0x0054, CRC); //CRC dafür ausschalten
  //zuerst einmal alle Status Register auslesen, um mögliche vorhandene Fehler nicht falsch zu deuten 
  //Status Register sind "Read to Clear - Register" -> einmal auslesen damit Fehler weg und nicht bestehen bleibt, obwohl er alt ist  
  readRegister(CONV_STAT_REG, 0x0000, 0x00); //CONV_STAT
  readRegister(AFE_STAT_REG, 0x0000, 0x00); //AFE_STAT
  readRegister(SYS_STAT_REG, 0x0000, 0x00); //SYS_STAT 
  return SUCCESS; 
}

String range(char *data){ 
  byte CRC_Sens = calculateCRC(SENS_CONF_REG+0x80, 0x0000, 0x00);
  int16_t Sens = readRegister(SENS_CONF_REG+0x80, 0x0000, CRC_Sens);
  bool *bits;
  bits = getBits(Sens);
  
  //zRange auslesen reicht, da alle Achsen gleiche Range haben
  if(bits[5] == 0 && bits[4] == 0) globalRange = 150; //+-150mT
  if(bits[5] == 0 && bits[4] == 1) globalRange = 75; //+-75mT
  if(bits[5] == 1 && bits[4] == 0) globalRange = 300; //+-300mT
  delete[] bits;

  String afe = afeStat(); 
  String sys = sysStat();
  if(afe == "F1" && sys == "F1"){ 
      String range = String(globalRange);
      return range;
  }
  else{
    if(afe != "F1") return afe;
    if(sys != "F1") return sys;
  }
}



// ====
// Funktionen zur Ausgabe der Ergebnisse der vorherigen Funktionen, um Ausgabe mit Julia einzulesen 
// ====

void sendIdentification(char *data){ 
  String id = returnUniqueID() + "\r\n";
  SERIAL.print(id);
  //SERIAL.write(id.c_str(), id.length());
}

void sendDefaultConfig(char *data){ 
  String ausgabe = defaultConfig(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendCRC(char *data){ 
  String ausgabe = crc(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendSingleDeviceConfig(char *data){ 
  String ausgabe = singleDeviceConfig(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendSensConfig(char *data){ 
  String ausgabe = sensConfig(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendSysConfig(char *data){ 
  String ausgabe = sysConfig(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendReadReg(char *data){ 
  String bits = readReg(data) + "\r\n";
  SERIAL.print(bits);
  //SERIAL.write(bits.c_str(), bits.length());
}

void sendReadTemp(char *data){ 
  String temp = readTemp(data) + "\r\n";
  SERIAL.print(temp);
  //SERIAL.write(temp.c_str(), temp.length());
}

void sendGetFieldValueX(char *data){
  String ergebnisX = getFieldValueX(data) + "\r\n";
  SERIAL.print(ergebnisX);
  //SERIAL.write(ergebnisX.c_str(), ergebnisX.length());
}

void sendGetFieldValueY(char *data){
  String ergebnisY = getFieldValueY(data) + "\r\n";
  SERIAL.print(ergebnisY);
  //SERIAL.write(ergebnisY.c_str(), ergebnisY.length());
}

void sendGetFieldValueZ(char *data){
  String ergebnisZ = getFieldValueZ(data) + "\r\n";
  SERIAL.print(ergebnisZ);
  //SERIAL.write(ergebnisZ.c_str(), ergebnisZ.length());
}

void sendGetFieldValueXYZ(char *data){
  String ergebnisXYZ = getFieldValueXYZ(data) + "\r\n";
  SERIAL.print(ergebnisXYZ);
  //SERIAL.write(ergebnisXYZ.c_str(), ergebnisXYZ.length());
}

void sendInitAllSensorsArduino(char *data){
  String ausgabe = initAllSensorsArduino(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length())
} 

void sendCheckInit(char *data){
  String ausgabe = checkInit(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length())
}

void sendAllSensorsArduino(char *data){
  String ausgabe = allSensorsArduino(data) + "\r\n\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendOperatingMode(char *data){
  String modus = operatingMode(data) + "\r\n";
  SERIAL.print(modus);
  //SERIAL.write(modus.c_str(), modus.length());
}

void sendOscInCheck(char *data){
  String ausgabe = oscInCheck(data) + "\r\n"; 
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendSelectChip(char *data){
  String ausgabe = selectChip(data) + "\r\n"; 
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendDeleteErrors(char *data){ 
  String ausgabe = deleteErrors(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

void sendRange(char *data){ 
  String ausgabe = range(data) + "\r\n";
  SERIAL.print(ausgabe);
  //SERIAL.write(ausgabe.c_str(), ausgabe.length());
}

String allSensorsArduinoFast(){ 
  unsigned long startGes; 
  unsigned long zeitGes;
  unsigned long startAus; 
  unsigned long zeitAus;
  startGes = millis();

    String ergebnis = "\n\n"; 

    //Auslesen aller Sensoren
    //startAus = millis();

    for(int i = 0; i < 37; i++){ 
      //String index = String(sensors[i], HEX);
      //String befehl = "*SELECTCHIP!>0x" + index + "#";
      //char befehl_c[befehl.length() + 1]; 
      //befehl.toCharArray(befehl_c, sizeof(befehl_c));
      //message = selectChip(befehl_c);
      chipSelect = sensors[i];
      // if (message != "F1") return message;
      String magnetfeld = getFieldValueXYZ("*GETFIELDVALUEXYZ?#");
      if (magnetfeld.indexOf("F") != -1){ //wenn "F" in magnetfeld vorhanden, ist es eine Fehlermeldung 
        return magnetfeld; 
      }
      ergebnis += magnetfeld;
      ergebnis += "\n";
    }
    //zeitAus = millis() - startAus; 
    //ergebnis += "\nZeit Auslesen(IDE):" + String(zeitAus) + "ms";
    zeitGes = millis() - startGes; 
    ergebnis += "\nZeit gesamt(IDE):" + String(zeitGes) + "ms";  
    return ergebnis; 
}

// std::array<std::array<int16_t, 3>, 37> allSensorsArduinoFaster(){ 
uint64_t* allSensorsArduinoFaster(){ 
  // auto startGes = micros();
    uint64_t result[37];

    for(int i = 0; i < 37; i++){ 
      chipSelect = sensors[i];
      // SERIAL.println(i);
      result[i] = getFieldValueXYZFast("*GETFIELDVALUEXYZ?#");
    }
    // SERIAL.println(String(micros()-startGes) + " us\n\n"); 
    return result; 
}

void sendAllSensorsArduinoFast(char *data){
  String ausgabe = allSensorsArduinoFast() + "\r\n\n";
  SERIAL.print(ausgabe);
  //SerialUSB.write(ausgabe.c_str(), ausgabe.length());
}

void sendAllSensorsArduinoFaster(char *data){
  static uint8_t readingCounter = 0;
  uint64_t ausgabe[37];

  for(int i = 0; i < 37; i++){ 
    chipSelect = sensors[i];
    // SERIAL.println(i);
    ausgabe[i] = getFieldValueXYZFast("*GETFIELDVALUEXYZ?#");
  }

  // SERIAL.print(ausgabe);
  // for (int row = 0; row < 37; row++){
  //   for (int col = 0; col < 3; col++){
  //     SERIAL.print(ausgabe[row][col]);
  //     SERIAL.print("\t");
  //   }
  //   SERIAL.print("\n");
  // }
  sendFramedPacket(reinterpret_cast<const uint8_t*>(ausgabe), sizeof(ausgabe), readingCounter);

  readingCounter++;
  //SERIAL.println("\r" + String(micros()-start) + " us Total");
  //SerialUSB.write(ausgabe.c_str(), ausgabe.length());
}