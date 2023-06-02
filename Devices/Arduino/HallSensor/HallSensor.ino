#define ARDUINO_TYPE "HALLSENS"
#define VERSION "5.0"
#define BAUDRATE 9600
#define MEASDELAY 1
#define INPUT_BUFFER_SIZE 3000
#define MAX_SAMPLE_SIZE 10000

#include <Tle493d_w2b6.h>

// Tlv493d Opject
Tle493d_w2b6 sensor = Tle493d_w2b6(Tle493d::MASTERCONTROLLEDMODE);

// Communication
char input_buffer[INPUT_BUFFER_SIZE];
unsigned int input_pos = 0;

int sample_size = 1000;

int getDelay(char *);
int getData(char *);
int getPosition(char *);
int getTemp(char *);
int getVersion(char *);
int getCommands(char *);
int setSampleSize(char *);

typedef struct
{
  const char *id;
  int (*handler)(char *);
} commandHandler_t;

commandHandler_t cmdHandler[] = {
    {"DELAY", getDelay},
    {"DATA", getData},
    {"TEMP", getTemp},
    {"VERSION", getVersion},
    {"COMMANDS", getCommands},
    {"SAMPLES", setSampleSize}};

int getCommands(char *)
{
  Serial.print("Valid Commands (without quotes):");
  Serial.print("'!DATA*#' ");
  Serial.print("'!DELAY*#' ");
  Serial.print("'!VERSION*#' ");
  Serial.print("'!TEMP*#' ");
  Serial.print("'!COMMANDS*#' ");
  Serial.print("'!SAMPLESx*# 1>=x>=10000' ");
  Serial.println("#");
}

bool updateBufferUntilDelim(char delim)
{
  char nextChar;
  while (Serial.available() > 0)
  {
    nextChar = Serial.read();
    if (nextChar == delim)
    {
      input_buffer[input_pos] = '\0';
      input_pos = 0;
      return true;
    }
    else if (nextChar != '\n')
    {
      input_buffer[input_pos % (INPUT_BUFFER_SIZE - 1)] = nextChar; // Size - 1 to always leave room for \0
      input_pos++;
    }
  }
  return false;
}

void serialCommand()
{
  int s = -1;
  int e = -1;
  char beginDelim = '!';
  char *beginCmd;
  char endDelim = '*';
  char *endCmd;
  char *command;
  bool done = false;
  bool unknown = false;

  // determin substring
  if (Serial.available() > 0)
  {
    done = updateBufferUntilDelim('#');
  }

  if (done)
  {
    s = -1;
    if ((beginCmd = strchr(input_buffer, beginDelim)) != NULL)
    {
      s = beginCmd - input_buffer;
    }

    e = -1;
    if ((endCmd = strchr(input_buffer, endDelim)) != NULL)
    {
      e = endCmd - input_buffer;
    }

    unknown = true;
    // check if valid command
    if (e != -1 && s != -1)
    {
      command = beginCmd + 1;
      *endCmd = '\0';
      Serial.flush();

      // check for known commands
      for (int i = 0; i < sizeof(cmdHandler) / sizeof(*cmdHandler); i++)
      {
        if (strncmp(cmdHandler[i].id, command, strlen(cmdHandler[i].id)) == 0)
        {
          cmdHandler[i].handler(command);
          unknown = false;
          input_buffer[0] = '\0'; // "Empty" input buffer
          break;
        }
      }
    }

    if (unknown)
    {
      Serial.println("UNKNOWN");
      Serial.println("#");
      Serial.flush();
    }
  }
}
////////////////////////////////////////////////////////////////////////////////

void setup()
{
  Serial.begin(BAUDRATE);
  while (!Serial)
    ;

  // If using the MS2Go-Kit: Enable following lines to switch on the sensor
  //  ***
  pinMode(LED2, OUTPUT);
  digitalWrite(LED2, HIGH);
  delay(50);
  // ***

  sensor.begin();
  sensor.disableTemp();
}
int getDelay(char *)
{
  Serial.print(MEASDELAY, 7);
  Serial.println("#");
  Serial.flush();
}

int getData(char *)
{
  unsigned long start;
  int16_t x = 0, y = 0, z = 0;
  int16_t x_1 = 0, y_1 = 0, z_1 = 0;
  int32_t sumX = 0, sumY = 0, sumZ = 0;
  int32_t sumXX = 0, sumYY = 0, sumZZ = 0;
  float varX = 0, varY = 0, varZ = 0;
  float meanX = 0, meanY = 0, meanZ = 0;

  // updateData reads values from sensor and reading triggers next measurement
  sensor.updateData();
  delay(MEASDELAY);
  
  //storing first measurement as approximation of mean value
  x_1 = sensor.getRawX();
  y_1 = sensor.getRawY();
  z_1 = sensor.getRawZ();
  
  for (int i = 0; i < sample_size; i += 1)
  {
    sensor.updateData();
    start = millis();

    x = sensor.getRawX()-x_1;
    y = sensor.getRawY()-y_1;
    z = sensor.getRawZ()-z_1;

    sumX += x;
    sumY += y;
    sumZ += z;

    sumXX += x * x;
    sumYY += y * y;
    sumZZ += z * z;
    //waiting until new data is ready in the sensor
    while( millis()<MEASDELAY+start){};
  }
  
  meanX = (float)sumX / sample_size + x_1;
  meanY = (float)sumY / sample_size + y_1;
  meanZ = (float)sumZ / sample_size + z_1;

  varX = ((float)sumXX - (float)sumX * sumX / sample_size) / (sample_size - 1);
  varY = ((float)sumYY - (float)sumY * sumY / sample_size) / (sample_size - 1);
  varZ = ((float)sumZZ - (float)sumZ * sumZ / sample_size) / (sample_size - 1);

  Serial.print(meanX, 7);
  Serial.print(",");
  Serial.print(meanY, 7);
  Serial.print(",");
  Serial.print(meanZ, 7);
  Serial.print(",");
  Serial.print(varX, 7);
  Serial.print(",");
  Serial.print(varY, 7);
  Serial.print(",");
  Serial.print(varZ, 7);
  Serial.println("#");
  Serial.flush();
}

int getTemp(char *)
{
  sensor.enableTemp();
  delay(10);
  sensor.updateData();
  delay(MEASDELAY);
  sensor.updateData();
  delay(MEASDELAY);
  float temp = sensor.getTemp();
  Serial.print(temp, 7);
  Serial.println("#");
  Serial.flush();
  sensor.disableTemp();
  delay(10);
}

int getVersion(char *)
{
  Serial.print(ARDUINO_TYPE);
  Serial.print(":");
  Serial.print(VERSION);
  Serial.print("#");
  Serial.flush();
}

int setSampleSize(char *command)
{
  int value_int = atoi(command + 7);
  if (value_int > 0 && value_int <= MAX_SAMPLE_SIZE)
  {
    sample_size = value_int;
  }
  Serial.print(sample_size);
  Serial.println("#");
  Serial.flush();
}

void loop()
{
  serialCommand();
}
