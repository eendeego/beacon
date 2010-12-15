import processing.serial.*;

Serial port; 

void setup() 
{
  size(400, 160); 
  noStroke(); 
  frameRate(10); 
 
  // List all the available serial ports in the output pane. 
  // You will need to choose the port that the Arduino board is 
  // connected to from this list. The first port in the list is 
  // port #0 and the third port in the list is port #2. 
  println(Serial.list()); 
 
  // Open the port that the Arduino board is connected to (in this case #0) 
  // Make sure to open the port at the same speed Arduino is using (9600bps) 
  port = new Serial(this, Serial.list()[0], 9600);

  String control = "r!.w;";
  println(control);
  port.write(control);

  colorMode(RGB);
  fill(0);
  rect(0, 0, 400, 200);

  colorMode(HSB, 360, 100, 100);
  for(int i=0; i<360; i++) {
    fill(i, 100, 100);
    rect(20+i, 20, 1, 50);
  }

  fill(0, 0, 100);
  rect(20, 90, 360, 50);
}

void draw() {
  if(mousePressed) {
    if((mouseX >= 20) && (mouseX <= (20+360)) && (mouseY >= 20) && (mouseY <= (20+50))) {
      String control = "h(" + (mouseX - 20) + ").w;";
      println(control);
      port.write(control);
      return;
    }
    if((mouseX >= 20) && (mouseX <= (20+360)) && (mouseY >= 90) && (mouseY <= (90+50))) {
      String control = "a;";
      println(control);
      port.write(control);
      return;
    }
  }
  while (port.available() > 0) {
    int inByte = port.read();
    print((char) inByte);
  }
}
