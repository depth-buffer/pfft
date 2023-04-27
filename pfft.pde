import ddf.minim.*;
import ddf.minim.analysis.FFT;

// Global variables
Minim minim;
AudioInput mic;
double spp;
int cx, cy;
AudioRenderer renderer;

// TODO: Set an AudioListener so we neither drop buffers, nor process buffers more than once.
// Slide by half a buffer each STFT.
// Will need to store the resulting spectra somewhere for plotting - or just put directly into
// the spectrogram image, then draw that to the screen during draw()?

class AudioRenderer implements AudioListener
{
  private FFT fft;
  private float[] fftBuf;
  private ArrayList<color[]> slices;
  
  AudioRenderer()
  {
    fft = new FFT(1024 * 64, mic.sampleRate());
    fft.window(FFT.HANN);
    // If sample rate = 44100, then Nyquist = 22050.
    // 2^15 = 32768 (first power above 22050) so there will be 15 bands if we
    // ask for a log scale with bandwith 1Hz per octave. 15 * 72 = 1080.
    // ... or 22 * (2^10) = 22528, 10 * 108 = 1080.
    // If we ask for 352Hz per octave, 352 * 2^6 = 22528, 1080/6 = 180.
    // These different options favour more resolution in higher or lower frequencies.
    //fft.logAverages(690, 216);
    fft.logAverages(352, 180);
    //fft.logAverages(88, 135);
    //fft.logAverages(44, 120);
    //fft.logAverages(22, 108);
    //fft.logAverages(22, 864);
    //fft.logAverages(1, 72);

    // One average frequency band per row
    assert(fft.avgSize() == 1080);

    fftBuf = new float[1024 * 64];
    slices = new ArrayList<color[]>();
  }
  
  public synchronized void samples(float[] buf)
  {
    // Draw FFT (over a larger time window, to get higher resolution)
    // Copy our 1024-sample buffer in two 512-sample chunks, to get
    // some overlap, which should reduce artefacts between blocks.
    for (int o = 512; o >= 0; o -= 512)
    {
      arrayCopy(fftBuf, 0, fftBuf, 512, 512 * 127);
      arrayCopy(buf, o, fftBuf, 0, 512);
      fft.forward(fftBuf);
      slices.add(new color[displayHeight]);
      color[] slice = slices.get(slices.size() - 1);
      for (int i = 0, y = displayHeight - 1; i < fft.avgSize(); ++i, --y)
      {
        // Rough convert to decibels - but with a made-up scaling factor
        // & noise floor purely based on what visualises nicely, and no
        // compensation for window function amplitude loss, as I don't
        // actually understand how to apply that.
        float db = max(20 * (float)Math.log10(8 * fft.getAvg(i)), -100);
  
        color c = color(
          constrain(map(db, -75, 0, 0, 255), 0, 255),
          constrain(map(db, -40, 0, 0, 255), 0, 255),
          (db < -50) ?
            constrain(map(db, -100, -50, 0, 255), 0, 255)
            : constrain(map(db, -25, -50, 0, 255), 0, 255));
  
        slice[y] = c;
      }
    }
  }
  
  public synchronized void samples(float[] bufL, float[] bufR)
  {
    // Don't care about stereo for now
    this.samples(mic.mix.toArray());
  }
  
  public synchronized color[][] getSlices()
  {
    color[][] c = new color[slices.size()][displayHeight];
    slices.toArray(c);
    slices.clear();
    return c;
  }
}

void setup()
{
  fullScreen(P2D);
  frameRate(60);
  noSmooth();
  background(0);
  
  // Grab audio line in
  minim = new Minim(this);
  mic = minim.getLineIn(Minim.MONO, 1024, 44100);
  renderer = new AudioRenderer();
  mic.addListener(renderer);
  
  // Determine samples per pixel in the buffer
  cx = displayWidth / 2;
  cy = displayHeight / 2;
}

void draw()
{
  // Draw STFTs from samples collected since last frame
  
  // Scroll spectrogram
  color[][] slices = renderer.getSlices();
  copy(cx, 0, cx - slices.length, displayHeight, cx + slices.length, 0, cx - slices.length, displayHeight);
  
  for (int i = 0, x = cx + (slices.length - 1); i < slices.length; ++i, --x)
  {
    for (int y = 0; y < displayHeight; ++y)
    {
      stroke(slices[i][y]);
      circle(x, y, 1);
    }
  }
  
  // Draw waveform from left to right, ending at centre of screen
  
  float[] buf = mic.mix.toArray();
  fill(0);
  noStroke();
  rect(0, 0, cx - 1, displayHeight);

  // Old method - try and be clever; linearly interpolate our way through
  // the whole buffer over half the screen
  /*stroke(255);
  for (int x = 0; x < cx - 1; ++x)
  {
    float a = map(x, 0, cx - 2, 0, mic.bufferSize() - 2);
    float b = map(x + 1, 1, cx - 1, 1, mic.bufferSize() - 1);
    float i = lerp(buf[floor(a)], buf[ceil(a)], a - floor(a)) * cy;
    float j = lerp(buf[floor(b)], buf[ceil(b)], b - floor(b)) * cy;
    line(x, cy + i, x + 1, cy + j);
  }*/

  // New quick & dirty method - just iterate through the buffer one sample
  // at a time until we hit the middle of the screen. Don't worry that we
  // aren't drawing every sample; this is just a visualiser, not an analysis
  // tool!
  noFill();
  stroke(255);
  beginShape();
  for (int x = 0; x < cx; ++x)
  {
    vertex(x, cy + (buf[x] * cy));
  }
  endShape();
  
  /*// Draw frequency bands
  int lastF = 0;
  float[] frequencies = {100, 200, 500, 1000, 2000, 5000, 10000, 20000, 22051};
  for (int i = 0, y = displayHeight; i < fft.avgSize(); ++i, --y)
    
    if (fft.getAverageCenterFrequency(i) >= frequencies[lastF])
    {
      ++lastF;
      stroke(255);
      line(1920, y, 1900, y);
      text(fft.getAverageCenterFrequency(i), cx, y);
    }
  }*/
}
