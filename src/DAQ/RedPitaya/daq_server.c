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
float *txBuff = NULL;
float *ffValues = NULL;
int64_t data_read;
int64_t data_read_total;
int64_t buff_size;
float amplitudeTx = 0.0;
float phaseTx = 0.0;
int64_t numFramesInMemoryBuffer;
int numSamplesInTxBuff;
int numSamplesPerFrame;
int64_t decimation = 64;

bool rxEnabled;
bool ffOn;
uint32_t wp_first;

int64_t currentFrameTotal;
int64_t oldFrameTotal;

struct paramsType {
  int numSamplesPerPeriod;
  int numSamplesPerTxPeriod;
  int numPeriodsPerFrame;
  int numFFChannels;
  bool txEnabled;
  bool ffEnabled;
  bool isMaster; // not used yet
};

struct paramsType params;

void wait_for_acq_trigger()
{
  rp_DpinSetDirection(RP_DIO1_P, RP_OUT);
  rp_DpinSetState(RP_DIO1_P, RP_LOW);

  rp_AcqSetTriggerSrc(RP_TRIG_SRC_EXT_PE);
  rp_DpinSetState(RP_DIO1_P, RP_HIGH);

  rp_acq_trig_state_t state = RP_TRIG_STATE_TRIGGERED;

  while(false) {
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
  wp_first = wp_old;
  //rp_AcqGetWritePointerAtTrig(&wp_old);
  data_read = 0;
  int counter = 0;
  currentFrameTotal = 0;
  oldFrameTotal = -1;

  ffOn = true;
  while(rxEnabled) {
     rp_AcqGetWritePointer(&wp);
     uint32_t size = getSizeFromStartEndPos(wp_old, wp)-1;
     //printf("____ %d %d %d \n", size, wp_old, wp);
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
         //       data_read, data_read_total/params.numSamplesPerPeriod);

       currentFrameTotal = data_read_total / params.numSamplesPerPeriod;
       if (ffOn) {
         if(currentFrameTotal > oldFrameTotal + 1) {
           printf("WARNING: We lost a frame! oldFr %lld newFr %lld size=%d\n", 
                   oldFrameTotal, currentFrameTotal, size);
         }
         if(currentFrameTotal > oldFrameTotal) {
           //printf("++++ currFrame: %lld\n",  currFr);
           int currFFStep = currentFrameTotal % params.numPeriodsPerFrame;
           for (int i=0; i< params.numFFChannels; i++) {

             int status = rp_AOpinSetValue(i, ffValues[currFFStep*params.numFFChannels+i]);
             //printf("Set ff channel %d in cycle %d to value %f.\n", i,
             //              currFFStep,ffValues[currFFStep*params.numFFChannels+i]);
             if (status != RP_OK) {
                 printf("Could not set AO[%i] voltage.\n", i);
             }
           }
         }
       }

       wp_old = wp;
       oldFrameTotal = currentFrameTotal;
     } 

     counter++;
   }
   printf("ACQ Thread is finished!\n");
       printf("____  data_written: %lld total_frame %lld\n",
                       data_read, data_read_total/params.numSamplesPerPeriod);
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

  n = read(newsockfd,&params,sizeof(struct paramsType));
  if (n < 0) error("ERROR reading from socket");
 
  numSamplesPerFrame = params.numSamplesPerPeriod * params.numPeriodsPerFrame; 
  numFramesInMemoryBuffer = 64*1024*1024 / numSamplesPerFrame / 2;
                             
  printf("Num Samples Per Period: %d\n", params.numSamplesPerPeriod);
  printf("Num Samples Per Tx Period: %d\n", params.numSamplesPerTxPeriod);
  printf("Num Periods Per Frame: %d\n", params.numPeriodsPerFrame);
  printf("Num Samples Per Frame: %d\n", numSamplesPerFrame);
  printf("Num Frames In Memory Buffer: %lld\n", numFramesInMemoryBuffer);
  printf("Num FF Channels: %d\n", params.numFFChannels);
  printf("txEnabled: %d\n", params.txEnabled);
  printf("ffEnabled: %d\n", params.ffEnabled);
  printf("isMaster: %d\n", params.isMaster);

  if(params.ffEnabled) {
    ffValues = (float *)malloc(params.numFFChannels* params.numPeriodsPerFrame * sizeof(float));
    n = read(newsockfd,ffValues,params.numFFChannels* params.numPeriodsPerFrame * sizeof(float));
    for(int i=0;i<params.numFFChannels* params.numPeriodsPerFrame; i++) printf(" %f ",ffValues[i]);
    printf("\n");
    if (n < 0) error("ERROR reading from socket");
  }
}

void send_data_to_host(int64_t frame, int64_t numframes, int64_t channel)
{
  int64_t frameInBuff = frame % numFramesInMemoryBuffer;

  int16_t* buff_ = channel == 1 ? buff : buffControl; 

  if(numframes+frameInBuff < numFramesInMemoryBuffer)
  {
    n = write(newsockfd, buff_+frameInBuff*numSamplesPerFrame, 
                  numSamplesPerFrame * numframes * sizeof(int16_t));
    if (n < 0) error("ERROR writing to socket"); 
  } else {
      int64_t frames1 = numFramesInMemoryBuffer - frameInBuff;
      int64_t frames2 = numframes - frames1;
      n = write(newsockfd, buff_+frameInBuff*numSamplesPerFrame,
                  numSamplesPerFrame * frames1 *sizeof(int16_t));
      if (n < 0) error("ERROR writing to socket");
      n = write(newsockfd, buff_,
                  numSamplesPerFrame * frames2 * sizeof(int16_t));
      if (n < 0) error("ERROR writing to socket");
  }
}

void updateTx();

void* communication_thread(void* ch)
{
  while(true)
  {
    n = read(newsockfd,buffer,4);
    if (n < 0) error("ERROR reading from socket");

    int command = ((int32_t*)buffer)[0];
    //printf("Command: %d\n", command);

    switch(command) {
      case 1: // get current frame number
        ((int64_t*)buffer)[0] = currentFrameTotal-1; // -1 because we want full frames
        n = write(newsockfd, buffer, sizeof(int64_t));
        if (n < 0) error("ERROR writing to socket");
      break;
      case 2: // get frame data
        n = read(newsockfd,buffer,255);
        if (n < 0) error("ERROR reading from socket");

        int64_t frame = ((int64_t*)buffer)[0];
        int64_t numframes = ((int64_t*)buffer)[1];
        int64_t channel = ((int64_t*)buffer)[3];
        printf("Frame to read: %lld\n", frame);
        send_data_to_host(frame,numframes,channel);
      break;
      case 3: // get new tx params
        n = read(newsockfd,buffer,16);
        if (n < 0) error("ERROR reading from socket");
        amplitudeTx = ((double*)buffer)[0];
        phaseTx = ((double*)buffer)[1];
        printf("New Tx: %f %f\n", amplitudeTx, phaseTx);
        updateTx();
      break;
      default:
       close(newsockfd);
       close(sockfd);
       rxEnabled = false;
       ffOn = false;
       return NULL;
    }
  }

  return NULL;
}

void fillTxBuff()
{
  for (int i = 0; i < numSamplesInTxBuff; ++i){
    txBuff[i] = sin(2.0*M_PI / numSamplesInTxBuff * i + phaseTx/180.0*M_PI);
  }
}

void startTx()
{
  rp_GenReset();
  
  numSamplesInTxBuff = decimation*params.numSamplesPerTxPeriod;  //16384/2;
  txBuff = (float *)malloc(numSamplesInTxBuff * sizeof(float));
  fillTxBuff();
  rp_GenWaveform(RP_CH_1, RP_WAVEFORM_ARBITRARY);
  rp_GenArbWaveform(RP_CH_1, txBuff, numSamplesInTxBuff);
  rp_GenFreq(RP_CH_1, 125.0e6 / ((double)decimation) / 256 );

  rp_GenAmp(RP_CH_1, amplitudeTx);

  rp_GenOutEnable(RP_CH_1);
}

void updateTx() {
  printf("amplitudeTx New: %f \n", amplitudeTx);
  printf("phaseTx New: %f \n", phaseTx);
  rp_GenAmp(RP_CH_1, amplitudeTx);
  //rp_GenWaveform(RP_CH_1, RP_WAVEFORM_ARBITRARY);
  fillTxBuff();
  rp_GenArbWaveform(RP_CH_1, txBuff, numSamplesInTxBuff);
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

  buff_size = params.numSamplesPerPeriod*numFramesInMemoryBuffer;
  buff = (int16_t*)malloc(buff_size * sizeof(int16_t) );
  memset(buff,0, buff_size * sizeof(int16_t));
  buffControl = (int16_t*)malloc(buff_size * sizeof(int16_t) );
  memset(buffControl,0, buff_size * sizeof(int16_t));
}

void releaseBuffers()
{
  free(buff);
  free(buffControl);
}

int main(int argc, char **argv){

  /* Print error, if rp_Init() function failed */
  if(rp_Init() != RP_OK) {
    fprintf(stderr, "Rp api init failed!\n");
  }

  // These are parameter that we need to know from host
  amplitudeTx = 0.1;

  while(true)
  {
    printf("New connection \n");

    init_socket();
    wait_for_connections();

    data_read = 0;
    data_read_total = 0;
        
    amplitudeTx = 0.1; // just temporarily
    phaseTx = 0.0;

    initBuffers();
    if(params.txEnabled) {
      startTx();
    }
    startRx();
    
    pthread_t pAcq;
    pthread_create(&pAcq, NULL, acquisition_thread, NULL);
    
    pthread_t pCom;
    pthread_create(&pCom, NULL, communication_thread, NULL);
    
    pthread_join(pAcq, NULL);
    printf("Acq Thread finished \n");
    pthread_join(pCom, NULL);
    printf("Com Thread finished \n");

    if(params.txEnabled) {
      stopTx();
    }
    stopRx();

    releaseBuffers();
  }

  rp_Release();

  return 0;
}


