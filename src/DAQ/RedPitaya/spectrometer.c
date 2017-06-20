/* Red Pitaya C API example Acquiring a signal from a buffer  
 * This application acquires a signal on a specific channel */

#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include "redpitaya/rp.h"
#include <sys/socket.h> /* for socket(), connect(), send(), and recv() */
#include <arpa/inet.h>  /* for sockaddr_in and inet_addr() */
#include <sys/types.h> 
#include <netinet/in.h>
#include <pthread.h>

void error(const char *msg)
{
    perror(msg);
    exit(1);
}

static uint32_t getSizeFromStartEndPos(uint32_t start_pos, uint32_t end_pos) {
    end_pos   = end_pos   % ADC_BUFFER_SIZE;
    start_pos = start_pos % ADC_BUFFER_SIZE;
    if (end_pos < start_pos)
        end_pos += ADC_BUFFER_SIZE;
    return end_pos - start_pos + 1;
}


// The following are all global variables that are used by the
// data acquisition thread as well as the control thread
int16_t *buff;
int16_t *buffControl;
float *sinBuff = NULL;
float *cosBuff = NULL;
float *txBuff = NULL;
int64_t data_read;
int64_t data_read_total;
int64_t buff_size;
float intToVolt = 0.5/200222.109375; // needs config value
float amplitudeTx = 0.1;             // needs config value
float phaseTx = 0.0;                 // needs config value
int numSamplesPerPeriod;
int numPeriodsPerFrame;
int numPeriods;
int tx_buff_size;
float Kp = 0.2;
float Ki = 0.8;
float Kp_phase = 0.3;
float Ki_phase = 0.7;
float eps_amplitude = 0.001;
float eps_phase = 0.3;

bool controlPhase;
bool txEnabled;
bool isMaster;
bool rxEnabled;

int64_t currentFrameTotal;

void fill_tx_buff()
{
  for (int i = 0; i < tx_buff_size; ++i){
    txBuff[i] = sin(2.0*M_PI / tx_buff_size * i + phaseTx/180.0*M_PI);
  }
}


// The control thread
void *control_thread (void *ch)
{
  int64_t currentFrame = -1;
  int64_t counter = 0;

  float esum = amplitudeTx / Ki; 
  float epsum = 0.0 / Ki; 

  while(rxEnabled) {
    // Calculate frames
    int oldFrame = currentFrame;
    currentFrame = data_read / numSamplesPerPeriod -1;
            
    if(currentFrame >= 0 && currentFrame != oldFrame) {
      //printf("currentFrame: %lld, controlphase: %d \n", currentFrame, (int) controlPhase);
      
      // Calculate Fourier coeffcients
      float a = 0;
      float b = 0;
      int k;
      for(k=0;k<numSamplesPerPeriod;k++) {
         a += buffControl[currentFrame*numSamplesPerPeriod + k] * cosBuff[k];
         b += buffControl[currentFrame*numSamplesPerPeriod + k] * sinBuff[k];
      }
            
      // Here we should start controlling
      //printf("control coeff: %f %f\n", a, b);

      float amplitude = sqrt(a*a+b*b); 
      float phase = atan2(a,b) / M_PI * 180;
      //float phase = atan2(a,b) / M_PI * 180;
      //float phase = acos(a / amplitude) / M_PI * 180;

      float amplitudeV = amplitude*intToVolt;
              
      float targetAmplitude = 0.5;
      float e = -amplitudeV + targetAmplitude;
      
      float targetPhase = 0.0;//-M_PI/2.0;
      float ep = -phase + targetPhase;

      if ( fabs(e) / targetAmplitude > eps_amplitude || 
           fabs(ep)  > eps_phase)
      {
           printf("amplitudeRx: %f, phase: %f diff %f diffPhase %f \n", 
                            amplitudeV, phase, e, ep);
           printf("amplitudeTx Old: %f \n", amplitudeTx);
           printf("phaseTx Old: %f \n", phaseTx);
           
           amplitudeTx = Kp * e + Ki * esum; 
           esum += e;
           
           //amplitudeTx * targetAmplitude / amplitudeV;
           
           phaseTx = Kp_phase * ep + Ki_phase * epsum; 
           epsum += ep;

           //if(ep > 0) phaseTx +=1;
           //else phaseTx -=1;

           //phaseTx = phaseTx - 0.1*ep;
           //phaseTx = phaseTx +1;

           if(phaseTx > 180) phaseTx = 180;
           if(phaseTx < -180) phaseTx = -180;
           if(epsum > 180/Ki) epsum = 180/Ki_phase;
           if(epsum < -180/Ki) epsum = -180/Ki_phase;


           printf("amplitudeTx New: %f \n", amplitudeTx);
           printf("phaseTx New: %f \n", phaseTx);
           rp_GenAmp(RP_CH_1, amplitudeTx);
           //rp_GenWaveform(RP_CH_1, RP_WAVEFORM_ARBITRARY);
           fill_tx_buff();
           rp_GenArbWaveform(RP_CH_1, txBuff, tx_buff_size);

           usleep(5000);
      } else {
        if(controlPhase) {
          controlPhase = false;
        }
      }
      counter++;
    } else {
      // wait for next frame
      // usleep(100);
    }
  }

  return NULL;
}

void wait_for_acq_trigger()
{
  rp_DpinSetDirection(RP_DIO1_P, RP_OUT);
  rp_DpinSetState(RP_DIO1_P, RP_LOW);

  rp_AcqSetTriggerSrc(RP_TRIG_SRC_EXT_PE);
  rp_DpinSetState(RP_DIO1_P, RP_HIGH);

  rp_acq_trig_state_t state = RP_TRIG_STATE_TRIGGERED;

  while(true) {
    rp_AcqGetTriggerState(&state);
    if(state == RP_TRIG_STATE_TRIGGERED){
      //sleep(1);
      rp_AcqStart();
      break;
    }
  }
}

void* acquisition_thread(void* ch)
{        
  wait_for_acq_trigger();

  uint32_t wp,wp_old;
  rp_AcqGetWritePointer(&wp_old);
  //rp_AcqGetWritePointerAtTrig(&wp_old);
  data_read = 0;
  int counter = 0;
  currentFrameTotal = 0;

  while(rxEnabled) {
     rp_AcqGetWritePointer(&wp);
          
     uint32_t size = getSizeFromStartEndPos(wp_old, wp)-1;
     printf("____ %d %d %d \n", size, wp_old, wp);
     if (size > 0) {
       if(data_read + size <= buff_size) { 
         // Read measurement data
         rp_AcqGetDataRaw(RP_CH_2,wp_old, &size, buff+data_read );
         // Read control data
         rp_AcqGetDataRaw(RP_CH_1,wp_old, &size, buffControl+data_read );
         data_read += size;
         data_read_total += size;
       } else {
         uint32_t size1 = buff_size - data_read; 
         uint32_t size2 = size - size1; 
        
         rp_AcqGetDataRaw(RP_CH_2,wp_old, &size1, buff+data_read );
         rp_AcqGetDataRaw(RP_CH_1,wp_old, &size1, buffControl+data_read );
         data_read = 0;
         data_read_total += size1;
         
         //uint32_t wp_old_old = wp_old; 
         wp_old = (wp_old + size1) % ADC_BUFFER_SIZE;
         //printf("____ %d %d %d %d\n", wp_old_old, wp_old, size1, size2);
         
         rp_AcqGetDataRaw(RP_CH_2,wp_old, &size2, buff+data_read );
         rp_AcqGetDataRaw(RP_CH_1,wp_old, &size2, buffControl+data_read );  
         data_read += size2;
         data_read_total += size2;

       }

       //printf("++++ data_written: %lld total_frame %lld\n", 
       //         data_read, data_read_total/numSamplesPerPeriod);

       wp_old = wp;
       currentFrameTotal = data_read_total / numSamplesPerPeriod - 1;
     } 

     counter++;
   }
   printf("ACQ Thread is finished!\n");
       printf("____  data_written: %lld total_frame %lld\n",
                       data_read, data_read_total/numSamplesPerPeriod);
  return NULL;
}




// globals used for network communication
int sockfd, newsockfd, portno;
socklen_t clilen;
char buffer[256];
struct sockaddr_in serv_addr, cli_addr;
int n;
 

void init_socket()
{
  sockfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sockfd < 0) 
     error("ERROR opening socket");
  int enable = 1;
  if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &enable, sizeof(int)) < 0)
    error("setsockopt(SO_REUSEADDR) failed");

  bzero((char *) &serv_addr, sizeof(serv_addr));
  portno = 7777;
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = INADDR_ANY;
  serv_addr.sin_port = htons(portno);
  if (bind(sockfd, (struct sockaddr *) &serv_addr,
              sizeof(serv_addr)) < 0) 
              error("ERROR on binding");

}

void wait_for_connections()
{
  listen(sockfd,5);
  clilen = sizeof(cli_addr);
  newsockfd = accept(sockfd, 
                 (struct sockaddr *) &cli_addr, 
                 &clilen);
  if (newsockfd < 0) 
        error("ERROR on accept");
  bzero(buffer,256);


  n = read(newsockfd,buffer,4);
  if (n < 0) error("ERROR reading from socket");
  
  numSamplesPerPeriod = ((uint32_t*)buffer)[0];
  printf("Num Samples Per Period: %d\n", numSamplesPerPeriod);

  n = read(newsockfd,buffer,4);
  if (n < 0) error("ERROR reading from socket");
 
  numPeriods = ((uint32_t*)buffer)[0];
  printf("Num Periods: %d\n", numPeriods);
 
  n = read(newsockfd,buffer,4);
  if (n < 0) error("ERROR reading from socket");
  
  txEnabled = (((int32_t*)buffer)[0] == 1);
  printf("txEnabled: %d\n", txEnabled);
  
  n = read(newsockfd,buffer,4);
  if (n < 0) error("ERROR reading from socket");
  
  isMaster = (((int32_t*)buffer)[0] == 1);
  printf("isMaster: %d\n", isMaster);
}

void send_data_to_host(int64_t frame, int64_t numframes)
{
  int64_t frameInBuff = frame % numPeriods;

  if(numframes+frameInBuff < numPeriods)
  {
    n = write(newsockfd, buff+frameInBuff*numSamplesPerPeriod, 
                  numSamplesPerPeriod * numframes * sizeof(int16_t));
    if (n < 0) error("ERROR writing to socket"); 
    //n = write(newsockfd, buffControl+frameInBuff*numSamplesPerPeriod, 
    //              numSamplesPerPeriod * sizeof(int16_t));
    //if (n < 0) error("ERROR writing to socket"); 
  } else {
      int64_t frames1 = numPeriods - frameInBuff;
      int64_t frames2 = numframes - frames1;
      n = write(newsockfd, buff+frameInBuff*numSamplesPerPeriod,
                  numSamplesPerPeriod * frames1 *sizeof(int16_t));
      if (n < 0) error("ERROR writing to socket");
      n = write(newsockfd, buff,
                  numSamplesPerPeriod * frames2 * sizeof(int16_t));
      if (n < 0) error("ERROR writing to socket");
  }
}

void* communication_thread(void* ch)
{
  while(true)
  {
    n = read(newsockfd,buffer,255);
    if (n < 0) error("ERROR reading from socket");

    int command = ((int32_t*)buffer)[0];
    //printf("Command: %d\n", command);

    switch(command) {
      case 0: // get control phase
        ((int32_t*)buffer)[0] = controlPhase ? 1 : 0;
        n = write(newsockfd, buffer, sizeof(int32_t));
        if (n < 0) error("ERROR writing to socket");
      break;
      case 1: // get current frame number
        ((int64_t*)buffer)[0] = currentFrameTotal;
        n = write(newsockfd, buffer, sizeof(int64_t));
        if (n < 0) error("ERROR writing to socket");
      break;
      case 2: // get frame data
        n = read(newsockfd,buffer,255);
        if (n < 0) error("ERROR reading from socket");

        int64_t frame = ((int64_t*)buffer)[0];
        int64_t numframes = ((int64_t*)buffer)[1];
        printf("Frame to read: %lld\n", frame);
        send_data_to_host(frame,numframes);
      break;
      default:
       close(newsockfd);
       close(sockfd);
       rxEnabled = false;
       return NULL;
    }
  }

  return NULL;
}

void startTx()
{
  rp_GenReset();
  

  /*double targetFreq = 125.0e6 / 64.0 / numSamplesPerPeriod;
  float usedFreq;
  rp_GenFreq(RP_CH_1, 125.0e6 / 64.0 / numSamplesPerPeriod );
  rp_GenGetFreq(RP_CH_1, &usedFreq);
  printf("Target Freq: %f   Used Freq: %f  \n",targetFreq,usedFreq);
  */
  //rp_GenWaveform(RP_CH_1, RP_WAVEFORM_SINE);

  tx_buff_size = 64*numSamplesPerPeriod;  //16384/2;
  txBuff = (float *)malloc(tx_buff_size * sizeof(float));
  fill_tx_buff();
  rp_GenWaveform(RP_CH_1, RP_WAVEFORM_ARBITRARY);
  rp_GenArbWaveform(RP_CH_1, txBuff, tx_buff_size);
  rp_GenFreq(RP_CH_1, 125.0e6 / 64.0 / 256 );

  rp_GenAmp(RP_CH_1, amplitudeTx);

  rp_GenOutEnable(RP_CH_1);
}

void stopTx()
{
  rp_GenOutDisable(RP_CH_1);
  free(txBuff);
}

void startRx()
{  
  rp_AcqReset();
  rp_AcqSetDecimation(RP_DEC_64);
  //rp_AcqSetDecimation(RP_DEC_8);
  rp_AcqSetTriggerDelay(0);
  //rp_AcqSetTriggerDelay(8192 + 1);

  printf("Starting Acquisition");
  rp_AcqStart();
  rxEnabled = true;
}

void stopRx()
{
  rp_AcqStop();
}

void initBuffers()
{
  // intitialize buffers
  buff_size = numSamplesPerPeriod*numPeriods;
  buff = (int16_t*)malloc(buff_size * sizeof(int16_t) );
  memset(buff,0, buff_size * sizeof(int16_t));
  buffControl = (int16_t*)malloc(buff_size * sizeof(int16_t) );
  memset(buffControl,0, buff_size * sizeof(int16_t));

  // create lookup table for accelerated sin/cos computation
  sinBuff = (float*)malloc((numSamplesPerPeriod) * sizeof(float) );
  cosBuff = (float*)malloc((numSamplesPerPeriod) * sizeof(float) );
  int k;
  for(k=0;k<numSamplesPerPeriod;k++) { 
    sinBuff[k] = sin(2 * M_PI * (float) k / (float) numSamplesPerPeriod);
    cosBuff[k] = cos(2 * M_PI * (float) k / (float) numSamplesPerPeriod);
  }
}

void releaseBuffers()
{
  free(buff);
  free(buffControl);
  free(sinBuff);
  free(cosBuff);
}

int main(int argc, char **argv){

  /* Print error, if rp_Init() function failed */
  if(rp_Init() != RP_OK) {
    fprintf(stderr, "Rp api init failed!\n");
  }

  // These are parameter that we need to know from host
  intToVolt = 0.5/200222.109375;
  amplitudeTx = 0.1;

  while(true)
  {
    printf("New connection \n");

    init_socket();
    wait_for_connections();

    data_read = 0;
    data_read_total = 0;
        
    controlPhase = true;
        
    amplitudeTx = 0.1; // just temporarily
    phaseTx = 0.0;

    initBuffers();
    if(txEnabled) {
      startTx();
    }
    startRx();
    
    pthread_t pControl;
    if(txEnabled) { 
      pthread_create(&pControl, NULL, control_thread, NULL);
    }

    pthread_t pAcq;
    pthread_create(&pAcq, NULL, acquisition_thread, NULL);
    
    pthread_t pCom;
    pthread_create(&pCom, NULL, communication_thread, NULL);
    
    if(txEnabled) {
      pthread_join(pControl, NULL);
      printf("Control Thread finished \n");
    }
    pthread_join(pAcq, NULL);
    printf("Acq Thread finished \n");
    pthread_join(pCom, NULL);
    printf("Com Thread finished \n");

    stopTx();
    stopRx();

    releaseBuffers();
  }

  rp_Release();

  return 0;
}


