"""Render the site's original brand artwork as a portable social-sharing card."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
root = Path(__file__).resolve().parent
scale = 2
im = Image.new('RGB',(2400,1260))
pixels=im.load()
for y in range(1260):
    for x in range(2400):
        glow=math.exp(-(((x-1840)/660)**2+((y-600)/600)**2))
        pixels[x,y]=(int(8+10*glow),int(10+19*glow),int(15+50*glow))
d=ImageDraw.Draw(im)
def font(size,bold=False):
    return ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial'+(' Bold' if bold else '')+'.ttf',size*scale)
def text(x,y,t,size,color,bold=False): d.text((x*scale,y*scale),t,font=font(size,bold),fill=color)
d.rounded_rectangle((140,100,212,172),radius=18,fill='#667ff3')
d.arc((156,116,196,156),-90,180,fill='white',width=5)
d.polygon([(176,121),(181,131),(191,136),(181,141),(176,151),(171,141),(161,136),(171,131)],fill='white')
text(116,53,'MacSweep',23,'#f0f3ff',True)
text(70,153,'YOUR MAC. IN ITS ELEMENT.',11,'#9dafe7')
text(66,205,'A clearer Mac.',66,'#f0f3ff',True)
text(66,280,'A better flow.',66,'#99b4ff',True)
text(70,382,'Clean. Protect. Understand.',22,'#b2bdd6')
text(70,434,'One thoughtfully powerful, native app.',17,'#8c99b7')
text(70,548,'macOS 15+   /   Apple Silicon   /   Native SwiftUI',12,'#7e8aa7')
# Orbital brand graphic, drawn from original geometric shapes.
cx,cy,r=1840,640,330
for radius in range(r,0,-1):
    k=radius/r
    c=(int(24+12*(1-k)),int(37+17*(1-k)),int(76+29*(1-k)))
    d.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill=c)
d.ellipse((cx-r,cy-r,cx+r,cy+r),outline='#647db9',width=2)
for angle in [-34,48]:
    pts=[]
    for n in range(361):
        a=math.radians(n); tilt=math.radians(angle)
        x=440*math.cos(a); y=160*math.sin(a)
        pts.append((cx+x*math.cos(tilt)-y*math.sin(tilt),cy+x*math.sin(tilt)+y*math.cos(tilt)))
    d.line(pts,fill='#516b9c',width=2)
d.arc((cx-104,cy-104,cx+104,cy+104),-90,180,fill='#d2e2ff',width=14)
d.polygon([(cx,cy-57),(cx+17,cy-17),(cx+57,cy),(cx+17,cy+17),(cx,cy+57),(cx-17,cy+17),(cx-57,cy),(cx-17,cy-17)],fill='#d6e5ff')
im.resize((1200,630),Image.Resampling.LANCZOS).save(root/'dist/assets/social.png',optimize=True)
print('Created assets/social.png (1200 × 630)')
