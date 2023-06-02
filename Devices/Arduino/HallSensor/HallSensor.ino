#define ARDUINO_TYPE "HALLSENS"
#define VERSION "4.0"
#define BAUDRATE 9600
#define MEASDELAY 1

#include <Tle493d_w2b6.h>

// Tlv493d Opject
Tle493d_w2b6 sensor = Tle493d_w2b6(Tle493d::MASTERCONTROLLEDMODE);
int sample_size = 1000;
bool fast_mode_on = false;
// Communication
#define INPUT_BUFFER_SIZE 3000
#define VALUE_BUFFER_SIZE 1024
char input_buffer[INPUT_BUFFER_SIZE];
int16_t value_buffer[VALUE_BUFFER_SIZE * 3];
unsigned int input_pos = 0;

int getDelay(char *);
int getData(char *);
int getPosition(char *);
int getTemp(char *);
int getVersion(char *);
int getCommands(char *);
int setSampleSize(char *);
int setFastMode(char *);

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
    {"SAMPLES", setSampleSize},
    {"FASTMODE", setFastMode}};

int getCommands(char *)
{
  Serial.print("Valid Commands (without quotes):");
  Serial.print("'!DATA*#' ");
  Serial.print("'!DELAY*#' ");
  Serial.print("'!VERSION*#' ");
  Serial.print("'!TEMP*#' ");
  Serial.print("'!COMMANDS*#' ");
  Serial.print("'!SAMPLESx*# 1>=x>=1024' ");
  Serial.print("'!FASTMODEx*# x =1|0'");
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
  unsigned long start, end, startFP, endA;
  int16_t x = 0, y = 0, z = 0;
  int32_t sumX = 0, sumY = 0, sumZ = 0;
  float sumXX = 0, sumYY = 0, sumZZ = 0;
  float varX = 0, varY = 0, varZ = 0;
  float meanX = 0, meanY = 0, meanZ = 0;

  // updateData reads values from sensor and reading triggers next measurement
  sensor.updateData();
  delay(MEASDELAY);

  // calculating mean values Mean =sum(x[i])/sample_size
  // measurement is stored for calculating the variance in a second go
  if (fast_mode_on)
  {
    for (int i = 0; i < sample_size * 3; i += 3)
    {
      sensor.updateData();
      start = millis();

      x = sensor.getRawX();
      y = sensor.getRawY();
      z = sensor.getRawZ();

      sumX += x;
      sumY += y;
      sumZ += z;

      // waiting until new data is ready in the sensor
      end = millis();
      if (end - start < MEASDELAY)
      {
        delay(MEASDELAY - (end - start));
      }
    }
  }
  else
  {
    for (int i = 0; i < sample_size * 3; i += 3)
    {
      sensor.updateData();
      start = millis();

      x = sensor.getRawX();
      y = sensor.getRawY();
      z = sensor.getRawZ();

      value_buffer[i] = x;
      value_buffer[i + 1] = y;
      value_buffer[i + 2] = z;

      sumX += x;
      sumY += y;
      sumZ += z;

      // waiting until new data is ready in the sensor
      end = millis();
      if (end - start < MEASDELAY)
      {
        delay(MEASDELAY - (end - start));
      }
    }
  }
  meanX = (float)sumX / sample_size;
  meanY = (float)sumY / sample_size;
  meanZ = (float)sumZ / sample_size;

  Serial.print(meanX, 7);
  Serial.print(",");
  Serial.print(meanY, 7);
  Serial.print(",");
  Serial.print(meanZ, 7);

  if (!fast_mode_on)
  {
    // calculating var var(x) = sum((x[i]-x_mean)^2)/(sample_size-1)
    // for sample_size = 1 the variance is zero
    if (sample_size > 1)
    {
      for (int i = 0; i < sample_size * 3; i += 3)
      {
        sumXX += ((float)value_buffer[i] - meanX) * ((float)value_buffer[i] - meanX);
        sumYY += ((float)value_buffer[i + 1] - meanY) * ((float)value_buffer[i + 1] - meanY);
        sumZZ += ((float)value_buffer[i + 2] - meanZ) * ((float)value_buffer[i + 2] - meanZ);
      }

      varX = sumXX / (sample_size - 1);
      varY = sumYY / (sample_size - 1);
      varZ = sumZZ / (sample_size - 1);
    }
    Serial.print(",");
    Serial.print(varX, 7);
    Serial.print(",");
    Serial.print(varY, 7);
    Serial.print(",");
    Serial.print(varZ, 7);
  }
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
  if (value_int > 0 && value_int <= VALUE_BUFFER_SIZE)
  {
    sample_size = value_int;
  }
  Serial.print(sample_size);
  Serial.println("#");
  Serial.flush();
}

int setFastMode(char *command)
{
  int value_int = atoi(command + 8);
  if (value_int == 0)
  {
    fast_mode_on = false;
  }
  else if (value_int == 1)
  {
    fast_mode_on = true;
  }
  else
  {
    Serial.print("value must be 0 or 1");
    Serial.println("#");
    Serial.flush();
    return 0;
  }
  Serial.print(fast_mode_on);
  Serial.println("#");
  Serial.flush();
}

void loop()
{
  serialCommand();
}
