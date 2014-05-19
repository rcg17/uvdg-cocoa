
#import "GraphView.h"

#define MAX_ALTITUDE 10000.0f
#define OCCURRENCE_LANE_HEIGHT 15.0f
#define OCCURRENCE_LANES_HEIGHT 76.0f
#define OCCURRENCE_FIRST_LANE_OFFSET 1.0f

@implementation GraphView

- (K2)getPoint:(unsigned long)index
{
    K2 k2;
    [m_points[index] getValue:&k2];
    
    return k2;
}

- (void)putPixelAtX:(int)x y:(int)y r:(int)r g:(int)g b:(int)b
{
    if (x >= m_bitmapRect.size.width) return;
    if (y >= m_bitmapRect.size.height) return;
    
    int pixelIndex = (x + y * (int)m_bitmapRect.size.width) * 4;
    
    m_bitmap[pixelIndex] = r;
    m_bitmap[pixelIndex + 1] = g;
    m_bitmap[pixelIndex + 2] = b;
    m_bitmap[pixelIndex + 3] = 0xff;
}

- (void)updateBitmap
{
    if (m_bitmap == NULL) return;
    
    memset(m_bitmap, 0, m_bitmapRect.size.width * m_bitmapRect.size.height * 4);
    
    if (m_points == nil) return;
    
    [[NSColor blackColor] set];
    
    double timeOffset = [self screenLeftTime];
    
    int startIndex = 0;
    double startTime = m_firstTime;
    while (startTime < timeOffset) {
        if (startIndex >= m_points.count) return;
        K2 point = [self getPoint:startIndex++];
        
        startTime = point.ri.time;
    }
//    NSLog(@"timeOffset %lf, startIndex %d.", timeOffset, startIndex);
    
    double time = timeOffset;
    int index = startIndex;
    for (int i = 0; i < m_bitmapRect.size.width; i++) {
        double prevTime = time;
        time += m_timeSlice;

        if ((int)prevTime % 3600 > (int)time % 3600)
        {
            for (int j = 0; j < m_bitmapRect.size.height; j++)
            {
                if (j % 3 != 0) continue;
                [self putPixelAtX:i y:j r:0x7f g:0x7f b:0x7f];
            }
        }
        
        double pointTime;
        while (pointTime < time)
        {
            if (index >= m_points.count) break;
            K2 point = [self getPoint:index++];
            if (m_confidence4Only && point.ri.confidence != 4) continue;
            pointTime = point.ri.time;
            
            float normAlt = point.alt / MAX_ALTITUDE;
            float y = (1.0 - normAlt) * (m_bitmapRect.size.height - 1);
            
            uint8 colorR, colorG, colorB;
            if (point.fuel == 0)
            {
                colorR = 0x7f;
                colorG = 0x7f;
                colorB = 0xff;
            }
            else
            {
                colorR = 0xff;
                colorG = 255 * (point.fuel / 100.0f);
                colorB = 255 * (point.fuel / 100.0f);
            }
            
            [self putPixelAtX:i y:y r:colorR g:colorG b:colorB];
            if (point.ri.amplitude > m_boldThreshold)
            {
                [self putPixelAtX:i y:y - 1 r:colorR g:colorG b:colorB];
            }
        }
    }
    
    [self setNeedsDisplay:YES];
}

- (void)updateFrame:(NSSize)size
{
    m_bitmapRect = NSMakeRect(0.0f, OCCURRENCE_LANES_HEIGHT, size.width, size.height - OCCURRENCE_LANES_HEIGHT);
    
    if (m_bitmap != NULL) free(m_bitmap);
    
    m_bitmap = (uint8 *)malloc(m_bitmapRect.size.width * m_bitmapRect.size.height * 4);
    
    [self updateBitmap];
}

#pragma mark -

- (NSString *)timeString:(double)time
{
    int t = (int)time % 86400;
    int hh = t / 3600;
    t %= 3600;
    int mm = t / 60;
    t %= 60;
    int ss = t;
    
    return [NSString stringWithFormat:@"%02d:%02d:%02d", hh, mm, ss];
}

- (double)screenLeftTime
{
    return m_firstTime + ((m_lastTime - m_firstTime) * m_normalizedTimeOffset);
}

- (double)screenRightTime
{
    return [self screenLeftTime] + m_bitmapRect.size.width * m_timeSlice;
}

- (double)timeForX:(float)x
{
    return (x * m_timeSlice) + [self screenLeftTime];
}

- (int)altForY:(float)y
{
    int alt = ((y - OCCURRENCE_LANES_HEIGHT) / m_bitmapRect.size.height) * MAX_ALTITUDE;
    return alt >= 0 ? alt : 0;
}

#pragma mark -

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
    {
        m_timeSlice = 1.0;
        m_boldThreshold = 100;      // sync with XIB
        m_downPoint = NSMakePoint(-1.0f, -1.0f);
        
        NSMutableParagraphStyle *centerAlignStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [centerAlignStyle setAlignment:NSCenterTextAlignment];
        m_centerAlignStyle = centerAlignStyle;

        NSMutableParagraphStyle *rightAlignStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [rightAlignStyle setAlignment:NSRightTextAlignment];
        m_rightAlignStyle = rightAlignStyle;
        
        [self updateFrame:frame.size];
    }
    
    return self;
}

- (void)dealloc
{
    [m_centerAlignStyle release];
    [m_rightAlignStyle release];
    
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (m_points == nil) return;
    
    double screenLeftTime = [self screenLeftTime];
    double screenRightTime = [self screenRightTime];
    
    //
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(m_bitmap,
                                                 m_bitmapRect.size.width,
                                                 m_bitmapRect.size.height,
                                                 8,
                                                 m_bitmapRect.size.width * 4,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast);
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    CGRect imageRect = NSRectToCGRect(m_bitmapRect);
    CGContextDrawImage((CGContextRef)[[NSGraphicsContext currentContext] graphicsPort], imageRect, quartzImage);
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    CGImageRelease(quartzImage);
    
    //
    
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, self.bounds.size.width, OCCURRENCE_LANES_HEIGHT));
    
    //
    
    if (m_downPoint.x >= 0)
    {
        NSBezierPath *marker = [NSBezierPath bezierPath];
        [marker moveToPoint:m_downPoint];
        [marker lineToPoint:m_dragPoint];
        [[NSColor yellowColor] set];
        [marker stroke];
        
        float deltaX = m_dragPoint.x - m_downPoint.x;
        float deltaTime = deltaX * m_timeSlice;
        
        float deltaY = (m_dragPoint.y - m_downPoint.y) / m_bitmapRect.size.height;
        float deltaAlt = deltaY * MAX_ALTITUDE;
        
        NSString *rateString = [NSString stringWithFormat:@"%.1f m/s", deltaAlt / deltaTime];
        NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor whiteColor]};
        [rateString drawAtPoint:NSMakePoint(m_dragPoint.x + 4.0f, m_dragPoint.y + 4.0f) withAttributes:attributes];
    }
    
    //
    
    double pendingLastTimes[10];
    for (int i = 0; i < 10; i++) pendingLastTimes[i] = 0.0;
    
    for (NSDictionary *dict in m_occurrences)
    {
        double first = [dict[@"first"] doubleValue];
        double last = [dict[@"last"] doubleValue];
        int tailNumber = [dict[@"tailNumber"] intValue];
        NSString *tailNumberString = [NSString stringWithFormat:@"%05d", tailNumber];
        
        if ((last > screenLeftTime && last < screenRightTime)
            || (first > screenLeftTime && first < screenRightTime)
            || (first < screenLeftTime && last > screenRightTime))
        {
            float firstX = (first - screenLeftTime) / m_timeSlice;
            float lastX = (last - screenLeftTime) / m_timeSlice;

            int n;
            for (int i = 0; i < 10; i++)
            {
                if (first > pendingLastTimes[i])
                {
                    pendingLastTimes[i] = last;
                    n = i;
                    break;
                }
            }
            
            NSRect rect = NSMakeRect(firstX, (n * OCCURRENCE_LANE_HEIGHT) + OCCURRENCE_FIRST_LANE_OFFSET, lastX - firstX, OCCURRENCE_LANE_HEIGHT);
            NSBezierPath *box = [NSBezierPath bezierPathWithRect:rect];
            
            [[[NSColor yellowColor] colorWithAlphaComponent:0.2] setFill];
            [box fill];
            
            NSRect textRect = rect;
            NSColor *textColor;
            if (NSPointInRect(m_hoverPoint, rect))
            {
                NSRect bigBoxRect = NSMakeRect(firstX, 0.0f, lastX - firstX, self.bounds.size.height);
                [[[NSColor yellowColor] colorWithAlphaComponent:0.1] setFill];
                NSBezierPath *bigBox = [NSBezierPath bezierPathWithRect:bigBoxRect];
                [bigBox fill];
                
                [[NSColor yellowColor] set];
                NSBezierPath *leftLine = [NSBezierPath bezierPath];
                [leftLine moveToPoint:NSMakePoint(firstX, 0.0f)];
                [leftLine lineToPoint:NSMakePoint(firstX, self.bounds.size.height)];
                [leftLine stroke];
                NSBezierPath *rightLine = [NSBezierPath bezierPath];
                [rightLine moveToPoint:NSMakePoint(lastX, 0.0f)];
                [rightLine lineToPoint:NSMakePoint(lastX, self.bounds.size.height)];
                [rightLine stroke];
                
                float expandedRectWidth = rect.size.width > 48.0f ? rect.size.width : 48.0f;
                textRect = NSMakeRect(rect.origin.x, rect.origin.y, expandedRectWidth, rect.size.height);
                
                textColor = [NSColor whiteColor];
            } else {
                [[[NSColor yellowColor] colorWithAlphaComponent:0.7] set];
                textColor = [NSColor lightGrayColor];
            }
            
            [box stroke];
            
            NSDictionary *attributes = @{NSForegroundColorAttributeName: textColor, NSParagraphStyleAttributeName: m_centerAlignStyle};
            [tailNumberString drawInRect:textRect withAttributes:attributes];
        }
    }
    
    // ground

    [[NSColor redColor] set];
    
    NSBezierPath *ground = [NSBezierPath bezierPath];
    [ground moveToPoint:NSMakePoint(0.0f, OCCURRENCE_LANES_HEIGHT)];
    [ground lineToPoint:NSMakePoint(self.bounds.size.width, OCCURRENCE_LANES_HEIGHT)];
    [ground stroke];

    // cross

    if (m_showLineCross && m_hoverPoint.y > OCCURRENCE_LANES_HEIGHT)
    {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:0.7] set];
        
        NSBezierPath *crossV = [NSBezierPath bezierPath];
        [crossV moveToPoint:NSMakePoint(m_hoverPoint.x, 0.0f)];
        [crossV lineToPoint:NSMakePoint(m_hoverPoint.x, self.bounds.size.height)];
        [crossV stroke];

        NSBezierPath *crossH = [NSBezierPath bezierPath];
        [crossH moveToPoint:NSMakePoint(0.0f, m_hoverPoint.y)];
        [crossH lineToPoint:NSMakePoint(self.bounds.size.width, m_hoverPoint.y)];
        [crossH stroke];
    }
    
    // hover alt / time
    
    double hoverTime = [self timeForX:m_hoverPoint.x];
    int hoverAlt = [self altForY:m_hoverPoint.y];
    NSString *debugString = [NSString stringWithFormat:@"alt %d time %@", hoverAlt, [self timeString:hoverTime]];
    NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_centerAlignStyle};
    [debugString drawInRect:NSMakeRect(0.0f, self.bounds.size.height - 22.0f, self.bounds.size.width, 18.0f) withAttributes:attributes];
    
    // times
    
    NSDictionary *leftTimeAttributes = @{NSForegroundColorAttributeName: [NSColor whiteColor]};
    NSString *leftTimeString = [self timeString:screenLeftTime];
    [leftTimeString drawInRect:NSMakeRect(4.0f, self.bounds.size.height - 100.0f, 100.0f, 20.0f) withAttributes:leftTimeAttributes];

    NSDictionary *rightTimeAttributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_rightAlignStyle};
    NSString *rightTimeString = [self timeString:screenRightTime];
    [rightTimeString drawInRect:NSMakeRect(self.bounds.size.width - 104.0f, self.bounds.size.height - 100.0f, 100.0f, 20.0f) withAttributes:rightTimeAttributes];
}

- (void)setFrame:(NSRect)frameRect
{
    [self updateFrame:frameRect.size];
    
    [super setFrame:frameRect];
}

- (void)updateTrackingAreas
{
    m_trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                  options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp
                                                    owner:self
                                                 userInfo:nil];
    [self addTrackingArea:m_trackingArea];
}

- (void)resetCursorRects
{
    [self addCursorRect:self.bounds cursor:[NSCursor crosshairCursor]];
}

#pragma mark -

- (void)setOccurrences:(NSArray *)occurrences andPoints:(NSArray *)points
{
    m_occurrences = [occurrences retain];
    
    m_points = [points retain];
    K2 firstPoint = [self getPoint:0];
    m_firstTime = firstPoint.ri.time;
    K2 lastPoint = [self getPoint:points.count - 1];
    m_lastTime = lastPoint.ri.time;
    
    [self updateBitmap];
}

- (void)setNormalizedTimeOffset:(double)normalizedTimeOffset
{
    m_normalizedTimeOffset = normalizedTimeOffset;
    [self updateBitmap];
}

- (void)setZoom:(double)zoom
{
    m_timeSlice = 1.0 + zoom * 10.0;
    [self updateBitmap];
}

- (void)setConfidence4Only:(BOOL)flag
{
    m_confidence4Only = flag;
    [self updateBitmap];
}

- (void)setBoldThreshold:(double)boldThreshold
{
    m_boldThreshold = boldThreshold * 255.0;
    NSLog(@"bold threshold set to %d.", m_boldThreshold);
    [self updateBitmap];
}

#pragma mark -

- (void)mouseDown:(NSEvent *)event
{
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_downPoint = location;
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_dragPoint = location;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
//    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_downPoint = NSMakePoint(-1.0f, -1.0f);
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event
{
    m_hoverPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    [super keyDown:event];
}

- (void)keyUp:(NSEvent *)event
{
    if (event.keyCode == 49)
    {
        // space
        
        m_showLineCross = !m_showLineCross;
        [self setNeedsDisplay:YES];
    }
        
    [super keyUp:event];
}

@end
