#define ARDUINO_TYPE "HALLSENS"
#define VERSION "1"
#define POSITION 1
#define size 1024
#define BAUDRATE 9600
#include <Tle493d_w2b6.h>

// Tlv493d Opject
Tle493d_w2b6 sensor = Tle493d_w2b6(Tle493d::MASTERCONTROLLEDMODE);
int called = 0;
// Communication
#define INPUT_BUFFER_SIZE 256
char input_buffer[INPUT_BUFFER_SIZE];
unsigned int input_pos = 0;

int getData(char*);
int getPosition(char*);
int getTemp(char*);
int getVersion(char*);
int getCommands(char*);
//int setFoo(char*)

typedef struct {
  const char * id;
  int (*handler)(char*);
} commandHandler_t;

commandHandler_t cmdHandler[] = {
  {"DATA", getData},
  {"POS", getPosition},
  {"TEMP", getTemp},
  {"VERSION", getVersion},
  {"COMMANDS", getCommands},
  //{"FOO", setFoo}
};

int getCommands(char*) {
  Serial.print("Valid Commands (without quotes):");
  Serial.print("'!DATA*#' ");
  Serial.print("'!POS*#' ");
  Serial.print("'!VERSION*#' ");
  Serial.print("'!COMMANDS*#' ");
  Serial.println("#");
}

bool updateBufferUntilDelim(char delim) {
  char nextChar;
  while (Serial.available() > 0) {
      nextChar = Serial.read();
      if (nextChar == delim) {
        input_buffer[input_pos] = '\0';
        input_pos = 0;
        return true;
      } else if (nextChar != '\n') {
        input_buffer[input_pos % (INPUT_BUFFER_SIZE - 1)] = nextChar; // Size - 1 to always leave room for \0
        input_pos++;
      }
  }
  return false;
}

void serialCommand() {
  int s=-1;
  int e=-1;
  char beginDelim='!';
  char *beginCmd;
  char endDelim='*';
  char *endCmd;
  char *command;
  bool done = false;
  bool unknown = false;
  
  // determin substring
  if(Serial.available()>0) {
    done = updateBufferUntilDelim('#');   
  }

  if (done) {
    s = -1;
    if ((beginCmd = strchr(input_buffer, beginDelim)) != NULL) {
      s = beginCmd - input_buffer;
    }

    e = -1;
    if ((endCmd = strchr(input_buffer, endDelim)) != NULL) {
      e = endCmd - input_buffer;
    }   

    unknown = true;
    //check if valid command
    if (e!=-1 && s!=-1) {
      command = beginCmd + 1;
      *endCmd = '\0';
      Serial.flush();

      //check for known commands
      for (int i = 0; i < sizeof(cmdHandler)/sizeof(*cmdHandler); i++) {
        if (strncmp(cmdHandler[i].id, command, strlen(cmdHandler[i].id)) == 0) {
          cmdHandler[i].handler(command);
          unknown = false;
          input_buffer[0] = '\0'; // "Empty" input buffer
          break;
        }
      }
    }
    
    if (unknown) {
      Serial.println("UNKNOWN");
      Serial.println("#");
      Serial.flush();  
    }

  }

}
////////////////////////////////////////////////////////////////////////////////

void setup() {
  Serial.begin(BAUDRATE);
  while(!Serial);
 
  //If using the MS2Go-Kit: Enable following lines to switch on the sensor
  // ***
  pinMode(LED2, OUTPUT);
  digitalWrite(LED2, HIGH);
  delay(50);
  // ***
  
  sensor.begin();
}


int getData(char*) {
  // updateData reads values from sensor and reading triggers next measurement
  int ret = sensor.updateData(); // Throw away first old data
  delay(10);
  ret = sensor.updateData(); // Could check ret after each measurement 
  uint16_t measDelay = 10;
  unsigned long start = millis();
  
  
  // TODO perform measurement

  int16_t mX = 1;
  int16_t mY = 4352;
  int16_t mZ = 3;

  int16_t sX=0,sY=0,sZ =0;
  Serial.print(mX);
  Serial.print(",");
  Serial.print(mY);
  Serial.print(",");
  Serial.print(mZ);
  //Serial.write((byte *)&sX,2);
  //Serial.write((byte *)&sY,2);
  //Serial.write((byte *)&sZ,2);
  Serial.print("#");
  Serial.flush();
  
  unsigned long end = millis();
  if (end - start < measDelay) {
    delay(measDelay-(end - start));
  }
}


int getPosition(char*) {
  Serial.print(POSITION);
  Serial.println("#");
}

int getTemp(char*) {
  // Enable Temp, measure, then disable again
}

int getVersion(char*) {
  Serial.print(ARDUINO_TYPE);
  Serial.print(":");
  Serial.print(VERSION);
  Serial.print(":");
  Serial.print(POSITION);
  Serial.print("#");
  Serial.flush(); 
}



void loop() {
  serialCommand();
}
