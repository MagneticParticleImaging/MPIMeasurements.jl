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
int64_t data_read;
int64_t data_read_total;
int64_t buff_size;
float intToVolt = 0.5/200222.109375; // needs config value
float amplitudeTx = 0.1;             // needs config value
float phaseTx = 0.0;                 // needs config value
int numSamplesPerPeriod;
int numPeriods;
float Kp = 0.2;
float Ki = 0.8;
float eps_amplitude = 0.001;
float eps_phase = 2.0;

bool controlPhase;

// The control thread
void *control_thread (void *ch)
{
  int64_t currentFrame = -1;
  int64_t counter = 0;

  float esum = amplitudeTx / Ki; 
  float epsum = 0.0 / Ki; 

  bool firstPhaseControl = false;

  while(currentFrame < numPeriods-1 ) {
    // Calculate frames
    int oldFrame = currentFrame;
    currentFrame = data_read / numSamplesPerPeriod -1;
            
    if(currentFrame >= 0 && currentFrame != oldFrame) {
      printf("currentFrame: %lld, controlphase: %d \n", currentFrame, (int) controlPhase);
      
      // Calculate Fourier coeffcients
      float a = 0;
      float b = 0;
      int k;
      for(k=0;k<numSamplesPerPeriod;k++) {
         a += buffControl[currentFrame*numSamplesPerPeriod + k] * cosBuff[k];
         b += buffControl[currentFrame*numSamplesPerPeriod + k] * sinBuff[k];
      }
            
      // Here we should start controlling
      printf("control coeff: %f %f\n", a, b);

      float amplitude = sqrt(a*a+b*b); 
      float phase = atan2(a, b) / M_PI * 180;
      printf("amplitude: %f  phase: %f \n", amplitude, phase);


      if(!firstPhaseControl) {
        printf("ADJUSTING PHASE \n");
        // the following need changes in RP api
        //rp_GenPhase(RP_CH_1, phase);
        firstPhaseControl = true;
      }

      float amplitudeV = amplitude*intToVolt;
              
      float targetAmplitude = 0.5;
      float e = -amplitudeV + targetAmplitude;
      
      printf("amplitude in V: %f, error: %f \n", amplitudeV, e);
      float targetPhase = 0.0;
      float ep = phase + targetPhase;

      if ( fabs(e) / targetAmplitude > eps_amplitude || 
           fabs(ep)  > eps_phase)
      {
           printf("amplitudeTx Old in V: %f \n", amplitudeTx);
           
           amplitudeTx = Kp * e + Ki * esum; 
           esum += e;
           
           //amplitudeTx * targetAmplitude / amplitudeV;
           
           phaseTx = Kp * ep + Ki * epsum; 
           epsum += ep;

           printf("amplitudeTx New in V: %f \n", amplitudeTx);
           printf("phaseTx New: %f \n", phaseTx);
           rp_GenPhase(RP_CH_1, phaseTx);
           rp_GenAmp(RP_CH_1, amplitudeTx);
           usleep(5000);
      } else {
        if(controlPhase) {
          controlPhase = false;
          currentFrame = -1;
        }
      }
      counter++;
    } else {
      // wait for next frame
//      usleep(100);
    }
  }

  return NULL;
}

void* acquisition_thread(void* ch)
{        
  uint32_t wp,wp_old;
  rp_AcqGetWritePointer(&wp_old);
  //rp_AcqGetWritePointerAtTrig(&wp_old);
  data_read = 0;
  int counter = 0;

  bool finalRun = false;

  while(true) {
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
         
         if(finalRun) {
           data_read = buff_size;
           break;
         }

         uint32_t wp_old_old = wp_old; 
         wp_old = (wp_old + size1) % ADC_BUFFER_SIZE;
         printf("____ %d %d %d %d\n", wp_old_old, wp_old, size1, size2);
         
         rp_AcqGetDataRaw(RP_CH_2,wp_old, &size2, buff+data_read );
         rp_AcqGetDataRaw(RP_CH_1,wp_old, &size2, buffControl+data_read );  
         data_read += size2;
         data_read_total += size2;

         if(!controlPhase) {
           printf("We are going for the final run now !!!\n");
           finalRun = true;
         }
       }


       printf("++++ data_written: %lld total_frame %lld\n", 
                data_read, data_read_total/numSamplesPerPeriod);

       wp_old = wp;
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


  n = read(newsockfd,buffer,255);
  if (n < 0) error("ERROR reading from socket");
  
  numSamplesPerPeriod = ((uint32_t*)buffer)[0];
  printf("Num Samples Per Period: %d\n", numSamplesPerPeriod);

  n = read(newsockfd,buffer,255);
  if (n < 0) error("ERROR reading from socket");
 
  numPeriods = ((uint32_t*)buffer)[0];
  printf("Num Periods: %d\n", numPeriods);
 
}

void send_data_to_host()
{
  //n = write(newsockfd,"I got your message",18);

  int l=0;
  int data_send = 0;
  int packet_size = 10000;
  while(data_send < buff_size) { 
    int local_packet_size = (data_send + packet_size > buff_size) ?
                             (buff_size-data_send) : packet_size; 
    n = write(newsockfd, buff+l*packet_size, 
                 local_packet_size * sizeof(int16_t));
    if (n < 0) error("ERROR writing to socket"); 
    n = write(newsockfd, buffControl+l*packet_size, 
                 local_packet_size * sizeof(int16_t));
    if (n < 0) error("ERROR writing to socket"); 
    n = read(newsockfd,buffer,255);
    if (n < 0) error("ERROR reading from socket");
    l++;
    data_send += local_packet_size;
  }

  close(newsockfd);
  close(sockfd);
}


int main(int argc, char **argv){

        /* Print error, if rp_Init() function failed */
        if(rp_Init() != RP_OK){
                fprintf(stderr, "Rp api init failed!\n");
        }

        // These are parameter that we need to know from host
        intToVolt = 0.5/200222.109375;
        amplitudeTx = 0.1;

   while(true)
   {
        init_socket();
        wait_for_connections();

        data_read = 0;
        data_read_total = 0;
        
        controlPhase = true;
        
        amplitudeTx = 0.1; // just temporarily

        rp_GenReset();
        rp_GenFreq(RP_CH_1, 125.0e6 / 64.0 / numSamplesPerPeriod );
        rp_GenAmp(RP_CH_1, amplitudeTx);
        rp_GenWaveform(RP_CH_1, RP_WAVEFORM_SINE);
        rp_GenOutEnable(RP_CH_1);

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

        rp_AcqReset();
        rp_AcqSetDecimation(RP_DEC_64);
        //rp_AcqSetDecimation(RP_DEC_8);
        rp_AcqSetTriggerDelay(0);
        //rp_AcqSetTriggerDelay(8192 + 1);

        printf("Starting Acquisition");
        rp_AcqStart();

        // TODO: Gen external trigger
        //rp_DpinSetDirection(RP_DIO1_P, RP_OUT);
        //rp_DpinSetState(RP_DIO1_P, RP_LOW);

        /* After acquisition is started some time delay is needed in order to acquire fresh samples in to buffer*/
        /* Here we have used time delay of one second but you can calculate exact value taking in to account buffer*/
        /*length and smaling rate*/

//        sleep(1.1);
        
        //rp_AcqSetTriggerSrc(RP_TRIG_SRC_NOW);
        
        //rp_AcqSetTriggerSrc(RP_TRIG_SRC_AWG_PE);
        //rp_GenTrigger(3);        
        
        //rp_AcqSetTriggerSrc(RP_TRIG_SRC_EXT_PE);        
        //rp_DpinSetState(RP_DIO1_P, RP_HIGH);

        //rp_acq_trig_state_t state = RP_TRIG_STATE_TRIGGERED;

        //while(1){
//        rp_GenTrigger(3);        
         //       rp_AcqGetTriggerState(&state);
         //       printf("Waiting for trigger\n");
         //       if(state == RP_TRIG_STATE_TRIGGERED){
//                  sleep(0.0);
         //         rp_AcqStart();
         //       break;
         //       }
       // }

        // Start the control thread
        pthread_t pControl;
        pthread_create(&pControl, NULL, control_thread, NULL);

        pthread_t pAcq;
        pthread_create(&pAcq, NULL, acquisition_thread, NULL);
        
        pthread_join (pControl, NULL);
        pthread_join (pAcq, NULL);

        printf("The buff_size is %lld   Data written %lld\n", buff_size, data_read);

        rp_GenOutDisable(RP_CH_1);
        
        send_data_to_host();

        /* Releasing resources */
        free(buff);
        free(buffControl);
        free(sinBuff);
        free(cosBuff);
  }

   rp_Release();

   return 0;
}

/*
        int i;
        FILE* fp = fopen("test.txt","w");
        for(i = 0; i < buff_size; i++){
                fprintf(fp,"%d\n", buff[i]);
        }
        fclose(fp);
*/

