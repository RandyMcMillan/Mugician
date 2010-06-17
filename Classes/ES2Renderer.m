//
//  ES2Renderer.m
//  kickAxe
//
//  Created by Robert Fielding on 4/7/10.
//  Copyright Check Point Software 2010. All rights reserved.
//

//#import <CoreGraphics/CoreGraphics.h>

#import "ES2Renderer.h"

#define NOTECOUNT 12

// The pixel dimensions of the CAEAGLLayer
static GLint backingWidth;
static GLint backingHeight;
static unsigned int tickCounter=0;

static const double kNotesPerOctave = 12.0;
static const double kMiddleAFrequency = 440.0;
static const double kMiddleANote = 48; //100; //24;//49;

#define SLIDERCOUNT 8
#define SPLITCOUNT 12
#define SNAPCONTROL 7
static NSSet* lastTouches;
static UIView* lastTouchesView;
static AudioOutput* lastAudio;
static float NoteStates[NOTECOUNT];
static float MicroStates[NOTECOUNT];
static float SliderValues[SLIDERCOUNT];
static float bounceX=0;
static float bounceY=0;
static float bounceDX=0.1;
static float bounceDY=0.1;

static GLuint textures[1];


float GetFrequencyForNote(float note) {
	return kMiddleAFrequency * powf(2, (note - kMiddleANote) / kNotesPerOctave);
}

// uniform index
enum {
    UNIFORM_TRANSLATE,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// attribute index
enum {
    ATTRIB_VERTEX,
    ATTRIB_COLOR,
    NUM_ATTRIBUTES
};


void TouchesInit()
{
	lastTouches = nil;
	lastTouchesView = nil;
}



void ButtonStatesInit()
{
	for(int i=0;i<NOTECOUNT;i++)
	{
		NoteStates[i]=0;
		MicroStates[i]=0;
	}
}


void ButtonsTrack()
{
	NSArray* touches = [lastTouches allObjects];
	if(touches != NULL && [touches count] > 0)
	{
		for(unsigned int t=0; t < [touches count] && t < FINGERS; t++)
		{
			UITouch* touch = [touches objectAtIndex:t];
			if(touch != NULL)
			{
				CGPoint point = [touch locationInView:lastTouchesView];
				//Find the square we are in, and enable it
				float ifl = (1.0*SPLITCOUNT * point.x)/backingWidth;
				int i = (int)ifl;
				float di = ifl-i;
				int j = SPLITCOUNT-(SPLITCOUNT * point.y)/backingHeight;
				unsigned int n = (5*j+i)%12;
				if((j>0) && 0<=n && n<NOTECOUNT)
				{
					if(di < 0.25)
					{
						//quarterflat
						MicroStates[n] = (1+7*MicroStates[n])/8;
					}
					else
					if(0.75 < di) 
					{
						//quartersharp
						MicroStates[(n+1)%NOTECOUNT] = (1+7*MicroStates[(n+1)%NOTECOUNT])/8;
					}
					else
					{
						//on note
						NoteStates[n] = (1+7*NoteStates[n])/8;
					}
				}
			}
		}
	}	
	//Fade all notes
	for(unsigned int n=0;n<NOTECOUNT;n++)
	{
		NoteStates[n] *= 0.99;
		MicroStates[n] *= 0.99;
	}
}



#define SQUAREVERTICESMAX 800
static int Vertices2Count;
//static GLfloat Vertices2[2*SQUAREVERTICESMAX];
static GLfloat Vertices2Translated[2*SQUAREVERTICESMAX];
static GLubyte Vertices2Colors[4*SQUAREVERTICESMAX];

//Recreate immediate mode
void Vertices2Clear()
{
	Vertices2Count = 0;
}

void Vertices2Insert(GLfloat x,GLfloat y,GLubyte r,GLubyte g,GLubyte b,GLubyte a)
{
	if(Vertices2Count < SQUAREVERTICESMAX)
	{
		Vertices2Translated[2*Vertices2Count+0] = x; 
		Vertices2Translated[2*Vertices2Count+1] = y; 
		Vertices2Colors[4*Vertices2Count+0] = r; 
		Vertices2Colors[4*Vertices2Count+1] = g; 
		Vertices2Colors[4*Vertices2Count+2] = b; 
		Vertices2Colors[4*Vertices2Count+3] = a; 
		Vertices2Count++;
	}
}

void Vertices2Render(int triType)
{
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, Vertices2Translated);
	glEnableVertexAttribArray(ATTRIB_VERTEX);
	glVertexAttribPointer(ATTRIB_COLOR, 4, GL_UNSIGNED_BYTE, 1, 0, Vertices2Colors);
	glEnableVertexAttribArray(ATTRIB_COLOR);	
    // Draw
    glDrawArrays(triType, 0, Vertices2Count);	
}

void ButtonRender(int i,int j,float hilite)
{
	GLfloat f = 1.0/SPLITCOUNT;
	GLfloat l = 2*((i+0)*f-0.5);
	GLfloat r = 2*((i+1)*f-0.5);
	GLfloat t = 2*((j+1)*f-0.5);
	GLfloat b = 2*((j+0)*f-0.5);
	int n = (j*5+(i+9))%12;
	int isWhite = (n==0 || n==2 || n==3 || n==5 || n==7 || n==8 || n==10);
	
	float wr;// = w*255-hilite*255*k;
	float wg;// = w*255-hilite*255;
	float wb;// = w*255+k*hilite*255;
	
	if(isWhite)
	{
		wr = 255;
		wg = 255;
		wb = 255-hilite*255;
	}
	else
	{
		wr = 0;
		wg = 0;
		wb = hilite*255;
	}
		
	Vertices2Clear();

	Vertices2Insert(l,t,wr,wg,wb,255);
	Vertices2Insert(r,t,wr,wg,wb,255);
	Vertices2Insert(l,b,wr*0.5,wg*0.5,wb*0.5,255);
	Vertices2Insert(r,b,wr*0.25,wg*0.25,wb*0.25,255);
	
	Vertices2Render(GL_TRIANGLE_STRIP);
}

void MicroRedButtonRender(int i,int j,float hilite)
{
	GLfloat f = 1.0/SPLITCOUNT;
	GLfloat l = 2*((i-0.1)*f-0.5);
	GLfloat r = 2*((i+0.1)*f-0.5);
	GLfloat t = 2*((j+0.5+0.1)*f-0.5);
	GLfloat b = 2*((j+0.5-0.1)*f-0.5);
	GLfloat h = 255*hilite;
	GLfloat cr = 255;
	GLfloat cg = 0;
	GLfloat cb = 0;
	Vertices2Clear();
	Vertices2Insert(l,t,cr,cg,cb,h);
	Vertices2Insert(r,t,cr,cg,cb,h);
	Vertices2Insert(l,b,cr,cg,cb,h);
	Vertices2Insert(l,b,cr,cg,cb,h);
	Vertices2Insert(r,t,cr,cg,cb,h);
	Vertices2Insert(r,b,cr,cg,cb,h);
	Vertices2Render(GL_TRIANGLES);
}

void MicroGreenButtonRender(int i,int j,float hilite)
{
	GLfloat f = 1.0/SPLITCOUNT;
	GLfloat l = 2*((i-0.1+0.5)*f-0.5);
	GLfloat r = 2*((i+0.1+0.5)*f-0.5);
	GLfloat t = 2*((j+0.5+0.1)*f-0.5);
	GLfloat b = 2*((j+0.5-0.1)*f-0.5);
	GLfloat h = 255*hilite;
	GLfloat cr = 0;
	GLfloat cg = 255;
	GLfloat cb = 0;
	Vertices2Clear();
	Vertices2Insert(l,t,cr,cg,cb,h);
	Vertices2Insert(r,t,cr,cg,cb,h);
	Vertices2Insert(l,b,cr,cg,cb,h);
	Vertices2Insert(l,b,cr,cg,cb,h);
	Vertices2Insert(r,t,cr,cg,cb,h);
	Vertices2Insert(r,b,cr,cg,cb,h);
	Vertices2Render(GL_TRIANGLES);
}

void ButtonsRender()
{
	for(int j=0;j<SPLITCOUNT;j++)
	{
		for(int i=0;i<SPLITCOUNT;i++)
		{
			ButtonRender(i,j,NoteStates[(5*j+i)%12]);
			//MicroGreenButtonRender(i,j,NoteStates[(5*j+i)%12]);
		}
	}
}

void MicroButtonsRender()
{
	for(int j=0;j<SPLITCOUNT;j++)
	{
		//Note that we are over by 1
		for(int i=0;i<SPLITCOUNT+1;i++)
		{
			MicroRedButtonRender(i,j,MicroStates[(5*j+i)%12]);
		}
	}
}

void LinesRender()
{
	Vertices2Clear();
	for(int i=0;i<SPLITCOUNT;i++)
	{
		float v = -1 + i*2.0/SPLITCOUNT;
		Vertices2Insert(-1,v,0,255,0,255);
		Vertices2Insert(1,v,0,255,0,255);
		Vertices2Insert(v,-1,0,255,0,255);
		Vertices2Insert(v,1,0,255,0,255);
	}
	Vertices2Render(GL_LINES);
}

static const GLfloat vertices[4][3] = {
	{-1.0,  1.0, -0.0},
	{ 1.0,  1.0, -0.0},
	{-1.0, -1.0, -0.0},
	{ 1.0, -1.0, -0.0}
};
static const GLfloat texCoords[] = {
	0.0, 1.0,
	1.0, 1.0,
	0.0, 0.0,
	1.0, 0.0
};

void Control4RenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b,GLfloat scale,int slider)
{
	GLfloat v = (2*t+b)/3;
	GLfloat a = (t-b);
	GLfloat n = 60;
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.1*a*sin(200*((i+tickCounter)/n)+SliderValues[6]*8*cos( scale*tickCounter/10.0)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
}


void ControlFifthsRenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b)
{
	GLfloat v = (2*t+b)/3;
	GLfloat a = (t-b);
	GLfloat n = 60;
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.1*a*sin(M_PI*3*10.0*((i+tickCounter)/n)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.2*a*sin(M_PI*10.0*((i+tickCounter)/n)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
}

void Control3RenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b)
{
	GLfloat v = (2*t+b)/3;
	GLfloat a = (t-b);
	GLfloat n = 60;
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.1*a*sin(M_PI*20.0*((i+tickCounter)/n)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.2*a*sin(M_PI*10.0*((i+tickCounter)/n)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
}

void Control1RenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b)
{
	GLfloat v = (2*t+b)/3;
	GLfloat d = 0.01;
	GLfloat U = v - 0.05;
	GLfloat D = v + 0.05;
	GLfloat R = 0.000005;
	bounceX += bounceDX;
	bounceY += bounceDY;
	if(bounceX < l)
	{
		bounceX = l;
		bounceDX = R+d;
	}
	if(r < bounceX)
	{
		bounceX = r;
		bounceDX = -R-d;
	}
	if(bounceY < U)
	{
		bounceY = U;
		bounceDY = R+d;
	}
	if(D < bounceY)
	{
		bounceY = D;
		bounceDY = -R-d;
	}
	GLfloat p = 255 * (bounceX-l)/(r-l);
	
	Vertices2Clear();
	Vertices2Insert(bounceX-d,bounceY-d, 255,255, 255, p);
	Vertices2Insert(bounceX+d,bounceY-d, 255,255, 255, p);
	Vertices2Insert(bounceX-d,bounceY+d, 255,255, 255, p);
	Vertices2Insert(bounceX+d,bounceY+d, 255,255, 255, p);
	Vertices2Render(GL_TRIANGLE_STRIP);	
	
}
						
void Control0RenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b)
{
	GLfloat v = (2*t+b)/3;
	GLfloat a = (t-b);
	GLfloat n = 60;
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.1*a*sin(M_PI*8.0*((i+tickCounter)/n)), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
}

float sign(float x)
{
	return (x<=0) ? -1 : 1;
}

void Control2RenderSkin(GLfloat l,GLfloat r,GLfloat t,GLfloat b)
{
	GLfloat v = (2*t+b)/3;
	GLfloat a = (t-b);
	GLfloat n = 60;
	Vertices2Clear();
	for(int i=0; i<n; i++)
	{
		Vertices2Insert(l+(r-l)*i/n,v + 0.1*a*sign(sin(M_PI*8.0*((i+tickCounter)/n))), 255,255, 255, i/n*255);
	}
	Vertices2Render(GL_LINE_STRIP);	
}
						
void ControlRender()
{
	GLfloat t = -1 + 2.0/SPLITCOUNT;
	GLfloat b = -1;
	GLfloat a = (t-b);
	
	GLfloat v = (2*t+b)/3;
	
	GLfloat begin = -1;
	GLfloat end = 1;
	int sliderCount=SLIDERCOUNT;
	for(int slider=0; slider < sliderCount; slider++)
	{
		GLfloat sl = begin + slider * (end-begin) / sliderCount;
		GLfloat sr = begin + (slider+1) * (end-begin) / sliderCount;
		GLfloat sv = sl + SliderValues[slider]*(sr-sl);
		
		GLfloat cr = 0;
		GLfloat cg = 0;
		GLfloat cb = 0;
		if(slider==0)
		{
			cg = 255;
		}
		if(slider==1)
		{
			cb = 255;
		}
		if(slider==2)
		{
			cr = 255;
		}
		if(slider==3)
		{
			cr = 200;
			cb = 200;
		}
		if(slider==4)
		{
			cr = 200;
			cb = 200;
		}
		if(slider==5)
		{
			cr = 200;
			cg = 100;
		}
		if(slider==6)
		{
			cr = 200;
			cg = 100;
		}
		if(slider==7)
		{
			cr = 200;
			cg = 100;
		}
		
		GLfloat crd = cr * 0.5;
		GLfloat cgd = cg * 0.5;
		GLfloat cbd = cb * 0.5;
		
		Vertices2Clear();
		Vertices2Insert(sl,t, crd,cgd, cbd, 255);
		Vertices2Insert(sr,t, crd,cgd, cbd, 255);
		Vertices2Insert(sl,b, crd*0.50*0.5,cgd*0.5*0.5, cbd*0.5*0.5, 255);	
		Vertices2Insert(sr,b, crd*0.25*0.5,cgd*0.25*0.5, cbd*0.25*0.5, 255);	
		Vertices2Render(GL_TRIANGLE_STRIP);	
		
		Vertices2Clear();
		Vertices2Insert(sl,v+a*0.27, cr,cg, cb, 255);
		Vertices2Insert(sv,v+a*0.27, cr,cg, cb, 255);
		Vertices2Insert(sl,v-a*0.27, cr*0.5*0.5,cg*0.5*0.5, cb*0.5*0.5, 255);	
		Vertices2Insert(sv,v-a*0.27, cr*0.25*0.5,cg*0.25*0.5, cb*0.25*0.5, 255);	
		Vertices2Render(GL_TRIANGLE_STRIP);	
		
		switch(slider)
		{
			case 0: Control0RenderSkin(sl,sr,t,b); break;
			case 1: Control1RenderSkin(sl,sr,t,b); break;
			case 2: Control2RenderSkin(sl,sr,t,b); break;
			case 3: Control3RenderSkin(sl,sr,t,b); break;
			case 4: ControlFifthsRenderSkin(sl,sr,t,b); break;
			case 5: Control4RenderSkin(sl,sr,t,b,0.25,5); break;
			case 6: Control0RenderSkin(sl,sr,t,b); break;
			case 7: Control4RenderSkin(sl,sr,t,b,1.0,7); break;
			//default:
				//TODO
		}
	}
}

void FingerControl(float i,float j)
{
	//Slidercontrol spans 5 slots
	float sliderf = SLIDERCOUNT*i/12;
	int slider = (int)sliderf;
	float v = sliderf - slider;
	//NSLog(@"%d:%f",slider,v);
	switch(slider)
	{
		case 0: SliderValues[0]=v; [lastAudio setMaster: SliderValues[0]]; break;
		case 1: SliderValues[1]=v; [lastAudio setReverb: SliderValues[1]]; break;
		case 2: SliderValues[2]=v; [lastAudio setGain: SliderValues[2]]; break;
		case 3: SliderValues[3]=v; [lastAudio setPower: SliderValues[3]]; break;
		case 4: SliderValues[4]=v; [lastAudio setFM1: SliderValues[4]]; break;
		case 5: SliderValues[5]=v; [lastAudio setFM2: SliderValues[5]]; break;
		case 6: SliderValues[6]=v; [lastAudio setFM3: SliderValues[6]]; break;
		case 7: SliderValues[7]=v; [lastAudio setFM4: SliderValues[7]]; break;
	}
}

void FingerRenderRaw2(float i,float j,GLfloat x,GLfloat y,CGFloat px,CGFloat py,int finger)
{
	
	GLfloat d = 1.0/SPLITCOUNT;
	GLfloat l = d - x;
	GLfloat t = d + y;
	GLfloat r = -d - x;
	GLfloat b = -d + y;
	GLfloat flat = 127 + 127 * cos((i)*2*M_PI);//255*(i-((int)(i+0.5)));
	GLfloat sharp = 127 + 127 * cos((i+0.5)*2*M_PI);//*(((int)(i))-i);
	GLfloat harm = 127 + 127 * cos((j)*2*M_PI);//*(((int)(i))-i);
	Vertices2Insert(l,t, flat, sharp, harm, 150);
	Vertices2Insert(r,t, flat,sharp, harm, 150);
	Vertices2Insert(l,b, flat,sharp, harm, 150);
	Vertices2Insert(r,b, flat,sharp, harm, 150);
	
	float n = ((int)j)*5 + i  -24 - 0.8;
	float f = GetFrequencyForNote(n);
	[lastAudio setNote:f forFinger: finger];	
	[lastAudio setVol:1.0 forFinger: finger];	
	[lastAudio setHarmonics:(j-((int)j)) forFinger: finger];	
}

void FingerRenderRaw(CGPoint p,int finger)
{
	GLfloat x = (0.5-p.x/backingWidth)*2;
	GLfloat y = (0.5-p.y/backingHeight)*2;
	CGFloat px=p.x;
	CGFloat py=p.y;
	float i = (SPLITCOUNT * px)/backingWidth;
	float j = SPLITCOUNT-(SPLITCOUNT * py)/backingHeight;
	if(j<1)
	{
		FingerControl(i,j);
	}
	else 
	{
		FingerRenderRaw2(i,j,x,y,px,py,finger);
	}

}

void FingersRender()
{
	Vertices2Clear();
	NSArray* touches = [lastTouches allObjects];
	if(touches != NULL && [touches count] > 0)
	{
		for(int i=0; i < [touches count] && i < FINGERS; i++)
		{
			UITouch* touch = [touches objectAtIndex:i];
			if(touch != NULL)
			{
				CGPoint lastPoint = [touch locationInView:lastTouchesView];
				FingerRenderRaw(lastPoint,i);
			}
		}
	}
	Vertices2Render(GL_TRIANGLE_STRIP);
}

void DisableFingers()
{
	//Turn off all sounds
	for(int b=0;b<FINGERS;b++)
	{
		[lastAudio setVol:0 forFinger: b];
	}
}

void SetupTextureMapping()
{
	//We assume that blending is setup already
	glEnable(GL_TEXTURE_2D);
	glGenTextures(1,&textures[0]);
	glBindTexture(GL_TEXTURE_2D,textures[0]);
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR); 
	glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);	
	
    NSString *path = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"png"];
    NSData *texData = [[NSData alloc] initWithContentsOfFile:path];
    UIImage *image = [[UIImage alloc] initWithData:texData];
    if (image == nil)
        NSLog(@"Do real error checking here");
	
    GLuint width = CGImageGetWidth(image.CGImage);
    GLuint height = CGImageGetHeight(image.CGImage);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    void *imageData = malloc( height * width * 4 );
    CGContextRef context = CGBitmapContextCreate( imageData, width, height, 8, 4 * width, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big );
    CGColorSpaceRelease( colorSpace );
    CGContextClearRect( context, CGRectMake( 0, 0, width, height ) );
    CGContextTranslateCTM( context, 0, height - height );
    CGContextDrawImage( context, CGRectMake( 0, 0, width, height ), image.CGImage );
	
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, imageData);
	
    CGContextRelease(context);
	
    free(imageData);
    [image release];
    [texData release];
}

@interface ES2Renderer (PrivateMethods)
- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation ES2Renderer

// Create an OpenGL ES 2.0 context
- (id)init
{
    if ((self = [super init]))
    {
        context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

        if (!context || ![EAGLContext setCurrentContext:context] || ![self loadShaders])
        {
            [self release];
            return nil;
        }

        // Create default framebuffer object. The backing will be allocated for the current layer in -resizeFromLayer
        glGenFramebuffers(1, &defaultFramebuffer);
        glGenRenderbuffers(1, &colorRenderbuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
		
		glEnable(GL_BLEND);		
		glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);	
		//SetupTextureMapping();
		
    }
	//MasterVol is 1/4 in beginning
	SliderValues[0] = 0.25;
	SliderValues[1] = 0.9;
	SliderValues[2] = 0.9;
	SliderValues[3] = 0.9;
	SliderValues[4] = 0.25;
	SliderValues[5] = 0.5;
	SliderValues[6] = 0.25;
	SliderValues[7] = 0;
	
	somethingChanged = true;
	TouchesInit();
	ButtonStatesInit();

	sound = [AudioOutput alloc];
	lastAudio = sound;
	[sound init];
	[sound start];
	
    return self;
}

- (void)render
{	
	tickCounter++;
	//[[UIDevice currentDevice] orientation]UIDeviceOrientationLandscapeLeft
	
    // This application only creates a single context which is already set current at this point.
    // This call is redundant, but needed if dealing with multiple contexts.
    [EAGLContext setCurrentContext:context];

    // This application only creates a single default framebuffer which is already bound at this point.
    // This call is redundant, but needed if dealing with multiple framebuffers.
    glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
    glViewport(0, 0, backingWidth,backingHeight);
	
    glClearColor(0.5f, 0.5f, 0.5f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // Use shader program
    glUseProgram(program);
#if defined(DEBUG)
    if (![self validateProgram:program])
    {
        NSLog(@"Failed to validate program: %d", program);
        return;
    }
#endif
	
	ButtonsRender();
	MicroButtonsRender();	
	ButtonsTrack();
	//LinesRender();
	ControlRender();
	DisableFingers();
	FingersRender();
			
	
    // This application only creates a single color renderbuffer which is already bound at this point.
    // This call is redundant, but needed if dealing with multiple renderbuffers.
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER];
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;

    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source)
    {
        NSLog(@"Failed to load vertex shader");
        return FALSE;
    }

    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);

#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif

    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0)
    {
        glDeleteShader(*shader);
        return FALSE;
    }

    return TRUE;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;

    glLinkProgram(prog);

#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif

    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0)
        return FALSE;

    return TRUE;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;

    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }

    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0)
        return FALSE;

    return TRUE;
}

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;

    // Create shader program
    program = glCreateProgram();

    // Create and compile vertex shader
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname])
    {
        NSLog(@"Failed to compile vertex shader");
        return FALSE;
    }

    // Create and compile fragment shader
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname])
    {
        NSLog(@"Failed to compile fragment shader");
        return FALSE;
    }

    // Attach vertex shader to program
    glAttachShader(program, vertShader);

    // Attach fragment shader to program
    glAttachShader(program, fragShader);

    // Bind attribute locations
    // this needs to be done prior to linking
    glBindAttribLocation(program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(program, ATTRIB_COLOR, "color");

    // Link program
    if (![self linkProgram:program])
    {
        NSLog(@"Failed to link program: %d", program);

        if (vertShader)
        {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader)
        {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (program)
        {
            glDeleteProgram(program);
            program = 0;
        }
        
        return FALSE;
    }

    // Get uniform locations
    uniforms[UNIFORM_TRANSLATE] = glGetUniformLocation(program, "translate");

    // Release vertex and fragment shaders
    if (vertShader)
        glDeleteShader(vertShader);
    if (fragShader)
        glDeleteShader(fragShader);

    return TRUE;
}

- (BOOL)resizeFromLayer:(CAEAGLLayer *)layer
{
    // Allocate color buffer backing based on the current layer size
    glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
    [context renderbufferStorage:GL_RENDERBUFFER fromDrawable:layer];
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
        return NO;
    }
    return YES;
}

- (void)dealloc
{
    // Tear down GL
    if (defaultFramebuffer)
    {
        glDeleteFramebuffers(1, &defaultFramebuffer);
        defaultFramebuffer = 0;
    }

    if (colorRenderbuffer)
    {
        glDeleteRenderbuffers(1, &colorRenderbuffer);
        colorRenderbuffer = 0;
    }

    if (program)
    {
        glDeleteProgram(program);
        program = 0;
    }

    // Tear down context
    if ([EAGLContext currentContext] == context)
        [EAGLContext setCurrentContext:nil];

    [context release];
    context = nil;

    [super dealloc];
}

- (void)touchesBegan:(NSSet*)touches atView:(UIView*)v
{
	lastTouches = touches;
	lastTouchesView = v;
//	somethingChanged = true;
	ButtonsTrack();

}

- (void)touchesMoved:(NSSet*)touches atView:(UIView*)v
{
	lastTouches = touches;
	lastTouchesView = v;
//	somethingChanged = true;
	ButtonsTrack();
}

- (void)touchesEnded:(NSSet*)touches atView:(UIView*)v
{
	lastTouches = touches;
	lastTouchesView = v;
//	somethingChanged = true;
	ButtonsTrack();
}

@end
