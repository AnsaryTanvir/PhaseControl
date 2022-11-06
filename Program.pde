#include <EEPROM.h>


volatile bool     zero_crossed    = false;  // Flag for sine wave zero crossing.
volatile uint8_t  AC_LOAD         = 8;      // MOC302 TRIAC controller is connected to this pin.
volatile uint8_t  counter         = 0;      // Counter used to measure ellapsed time.
volatile uint8_t  DELAY           = 0;      // It is the amount of time to wait before firing the TRIAC after a zero cross.


/* @brief This function is used to set the Arduino's physical pin "HIGH" by setting the PORT register for the associated pin.
 *  Directly accessing register bits to manipulate I/O is faster than library function call.
 *  Arduino Pin     PORT      PORT Number
 *   0 -  7          D           0 - 7 
 *   8 - 13          B           0 - 5
 */
void ON(uint8_t pin){
  if ( pin < 8 ) PORTD |= ( 1  << (pin-0) );  /* Set PORTD register bit */
  else           PORTB |= ( 1  << (pin-8) );  /* Set PORTB register bit */
}

/* @brief This function is used to set the Arduino's physical pin "LOW" by unsetting the PORT register for the associated pin.
 *  Directly accessing register bits to manipulate I/O is faster than library function call.
 *  Arduino Pin     PORT      PORT Number
 *   0 -  7          D           0 - 7 
 *   8 - 13          B           0 - 5
 */
void OFF(uint8_t pin){
  if ( pin < 8 ) PORTD &= ~( 1 << (pin-0) );  /* Unset or Clear PORTD register bit */
  else           PORTB &= ~( 1 << (pin-8) );  /* Unset or Clear PORTB register bit */
}


/* @brief Interrupt Service Routine for zero crossing detection.
 *  
 *  The 4N25 optocoupler's collector pin is pulled up via a 10k ohm resistor with the MCU's 5.0 V pin.
 *  Rectified sine wave is fed to the optocoupler's input section using a full bridge rectifierwith current control resistor.
 *  
 *  When the rectified sine wave is around the 0 volt region, no current flows from the optocoupler's collector to emitter. 
 *  So,the collector pin remains HIGH at round 5 V at this time.
 *  
 *  However, the 4N25 is activated when the voltage rises from 0 volt to a higher value, 
 *  and current begins to flow from the collector to the emitter,thus lowering the collector voltage to approximately 0 volt.
 *  
 *  The collector's voltage and the rectified sine wave relationship goes as follows: 
 *  Rectified Sine Wave Position    Collector's Voltage
 *        Zero  Crossing                  ≈ 5 V
 *        Other Region                    ≈ 0 V 
 *  
 *  In order to use the collector's voltage as an interrupt signal to determine zero crossing, 
 *  the collector pin is hooked up to one of the MCU's external hardware interrupt pins.
 *  The interrupt is configured as such that when the collector's voltage changes, it causes a hardware interrupt.
 *  The interrupt then calls this function to set the zero_crossed flag and disable the TRIAC for the next cycle.
 */
void zero_cross(){
  zero_crossed = true;  /* Update zero cross status [ON]   */
  OFF(AC_LOAD);         /* Disable the TRIAC on zero cross */
}


/* @brief Interrupt Service Routine for Timer1 CTC mode.
 *  
 *  Timer1 is configured in CTC mode ( Clear Timer on Compare Match ) at 10 kHz frequency.
 *  That means the ISR will be called every 100 microseconds.
 */
ISR(TIMER1_COMPA_vect){


  /* Check to see if zero is crossed.*/
  if ( zero_crossed ){

    /* Don't fire the TRIAC immediately, instead wait for the "DELAY" amount of time.
     * The counter holds elapsed time after zero crossing and when it exceeds "DELAY":
     *    Fire the TRIAC.
     *    Unset zero crossed flag.
     *    Reset counter.
     */
    if ( counter >= DELAY ){
      ON(AC_LOAD);
      zero_crossed  = false;
      counter       = 0;
      TCNT1         = 0;
    }else {
      counter++;  /* Each counter increment takes about 100 microseconds, as defined by the Timer Interrupt Frequency. */
    }
  }
    
}

void SetupTimerInterrupt(){
  
  noInterrupts(); //  Disable Global Interrupt
  TCCR1A  = 0;    //  Reset Timer1 Counter Control Register A (TCCR1A)
  TCCR1B  = 0;    //  Reset Timer1 Counter Control Register B (TCCR1B)
  TCNT1   = 0;    //  Reset Timer1 Counter.
  
  OCR1A   = 199;              //  Set Timer1 Output Compare Register A (OCR1A) [ Frequency 10 kHz ], time period 100 micro second.
  TCCR1B |= ( 1 << WGM12  );  //  Enable Clear Timer on Compare Match (CTC) mode
  TCCR1B |= ( 1 << CS11   );  //  Set CS11 bits for 8 prescaler
  TIMSK1 |= ( 1 << OCIE1A );  //  Enable timer compare interrupt
  interrupts();               //  Enable Global Interrupt
}


void setup() {

  Serial.begin(9600);
  pinMode(AC_LOAD, OUTPUT);
  digitalWrite(AC_LOAD, LOW);
  delay(1500);
  
  SetupTimerInterrupt();
  /* External interrupt pin for zero crossing detection */
  attachInterrupt( digitalPinToInterrupt(2) , zero_cross, CHANGE );

  DELAY = EEPROM.read( AC_LOAD );
}


void loop() {
  
 if ( Serial.available() ){
    uint8_t expectedDelay = Serial.parseInt();
    if ( expectedDelay > 95 ){
      /* Avoid flickering */
      expectedDelay = 95;
      EEPROM.write(AC_LOAD, expectedDelay);
    }
    DELAY = expectedDelay;
 }

} 
