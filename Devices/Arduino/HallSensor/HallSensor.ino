#define ARDUINO_TYPE "HALLSENS"
#define VERSION "1"
#define POSITION 1
#define BAUDRATE 9600
#include <Tle493d_w2b6.h>

// Tlv493d Opject
Tle493d_w2b6 sensor = Tle493d_w2b6(Tle493d::MASTERCONTROLLEDMODE);
int sample_size= 30;
// Communication
#define INPUT_BUFFER_SIZE 3000
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
  uint16_t measDelay = 10;
  unsigned long start, end;
  
  
  // TODO perform measurement
  
  int32_t mX=0,mY=0,mZ=0,sX=0,sY=0,sZ=0,x=0,y=0,z=0;
  for (int i =0 ;i< sample_size ; i++){
    sensor.updateData(); 
    start = millis();
    
    x = sensor.getRawX();
    y = sensor.getRawY();
    z = sensor.getRawZ();
    
    mX+=x;
    mY+=y;
    mZ+=z;

    Serial.print(x);
    Serial.print(",");
    
    sX += x*x;
    sY += y*y;
    sZ += z*z;

    end = millis();
    if (end - start < measDelay) {
      delay(measDelay-(end - start));
    }
  }

 
  //sX -= mX*mX/sample_size;
  sY -= mY*mY/sample_size;
  sZ -= mZ*mZ/sample_size;
 
  mX = mX/sample_size;
  mY = mY/sample_size;
  mZ = mZ/sample_size;

  Serial.print(mX);
  //Serial.print(",");
  //Serial.print(mY);
  //Serial.print(",");
  //Serial.print(mZ);
  Serial.print(",");
  Serial.print(sX);
  //Serial.print(",");
  //Serial.print(sY);
  //Serial.print(",");
  //Serial.print(sZ);
  //Serial.print(",");
  Serial.print("#");
  Serial.flush();
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
