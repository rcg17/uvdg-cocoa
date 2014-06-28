
#import "GraphView.h"
#import "AppDelegate.h"
#import <Carbon/Carbon.h>

#define OCCURRENCE_LANE_HEIGHT 15.0f
#define OCCURRENCE_LANES_HEIGHT 76.0f
#define OCCURRENCE_FIRST_LANE_OFFSET 1.0f
#define TIME_SCROLLER_HEIGHT 20.0f
#define NOTIFICATION_BOX_WIDTH 200.0f
#define NOTIFICATION_BOX_HEIGHT 20.0f
#define STATUS_BOX_WIDTH 400.0f
#define STATUS_BOX_HEIGHT 20.0f
#define NORM_REALTIME_MARKER_OFFSET 0.9

@implementation GraphView

- (void)updateBitmap
{
    m_bitmapGenerator->lock();
    m_bitmapGenerator->update([self screenLeftTime], [self screenRightTime], m_firstTime, m_lastTime, m_timeSlice);
    m_bitmapGenerator->unlock();
    
    m_lastUpdateTimeLocal = [NSDate timeIntervalSinceReferenceDate];

    [self setNeedsDisplay:YES];
}

- (void)updateFrame:(NSSize)size
{
    m_bitmapRect = NSMakeRect(0.0f, OCCURRENCE_LANES_HEIGHT, size.width, size.height - OCCURRENCE_LANES_HEIGHT);

    m_bitmapGenerator->lock();
    if (m_bitmap != NULL) free(m_bitmap);
    m_bitmap = (uint8 *)malloc(m_bitmapRect.size.width * m_bitmapRect.size.height * 4);
    m_bitmapGenerator->setBitmap(m_bitmap, m_bitmapRect.size.width, m_bitmapRect.size.height);
    m_bitmapGenerator->unlock();
    
    if (m_isLockedOnRealtimeMarker)
    {
        [self scrollToRealtimeMarker];
    }
    
    [self updateBitmap];
}

#pragma mark -

- (NSString *)timeString:(double)time
{
    if (time < 0.0) time = 0.0;
    
    int t = (int)time;
    int dd = t / 86400;
    t %= 86400;
    int hh = t / 3600;
    t %= 3600;
    int mm = t / 60;
    t %= 60;
    int ss = t;
    
    NSString *dateString;
    int year, month, day;
    if (m_state->getStartDate(&year, &month, &day))
    {
        NSDateComponents *dateComponents = [[NSDateComponents new] autorelease];
        [dateComponents setYear:year];
        [dateComponents setMonth:month];
        [dateComponents setDay:day];
        NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:dateComponents];
        
        NSDateComponents *dayIncrement = [[NSDateComponents new] autorelease];
        [dayIncrement setDay:dd];
        
        NSDate *currentDate = [[NSCalendar currentCalendar] dateByAddingComponents:dayIncrement toDate:date options:0];
        NSDateComponents *currentDateComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                                                  fromDate:currentDate];
        
        dateString = [NSString stringWithFormat:@"%04d-%02d-%02d",
                      (int)[currentDateComponents year],
                      (int)[currentDateComponents month],
                      (int)[currentDateComponents day]];
    }
    else
    {
        dateString = [NSString stringWithFormat:@"%d", dd];
    }
    
    return [NSString stringWithFormat:@"%@ / %02d:%02d:%02d", dateString, hh, mm, ss];
}

- (double)screenLeftTime
{
    return m_firstTime + m_timeOffset;
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

- (float)xForTime:(double)time
{
    return (time - [self screenLeftTime]) / m_timeSlice;
}

- (void)setTimeOffset:(double)timeOffset
{
    // do not allow negative time
    
    if (m_firstTime + timeOffset < 0.0)
    {
        m_timeOffset = -m_firstTime;
    }
    else
    {
        m_timeOffset = timeOffset;
    }
    
    if (m_isLockedOnRealtimeMarker)
    {
        m_isLockedOnRealtimeMarker = false;
        
        [self showNotification:@"Lock on realtime marker lost."];
    }
}

- (float)modifierMultiplier
{
    UInt32 modifiers = GetCurrentKeyModifiers();
    if ((modifiers & shiftKey) != 0)
    {
        return 5.0f;
    }
    
    if ((modifiers & optionKey) != 0)
    {
        return 0.2f;
    }

    return 1.0f;
}

- (void)scrollToRealtimeMarker
{
    m_timeOffset = m_realtimeMarkerTime - m_firstTime - (m_bitmapRect.size.width * NORM_REALTIME_MARKER_OFFSET) * m_timeSlice;
}

#pragma mark -

- (id)initWithFrame:(NSRect)frame andUvdState:(UvdState *)state
{
    if ((self = [super initWithFrame:frame]))
    {
        m_state = state;
        
        m_bitmapGenerator = new UvdBitmapGenerator(state);
        
        m_state->lock();
        std::vector<K2> *points = m_state->points();
        if (points->size() > 0)
        {
            K2 firstPoint = points->at(0);
            m_firstTime = firstPoint.ri.time;
            K2 lastPoint = points->at(points->size() - 1);
            m_lastTime = lastPoint.ri.time;
        }
        else
        {
            m_firstTime = -1.0;
        }
        m_state->unlock();
        
        m_timeSlice = 1.0;
        m_downPoint = NSMakePoint(-1.0f, -1.0f);

        m_realtimeMarkerTime = -1.0;
        m_isLockedOnRealtimeMarker = false;

        m_isBeepingEnabled = true;
        m_isBeepPlaying = false;
        m_beep = [NSSound soundNamed:@"beep"];
        [m_beep setDelegate:self];
        
        m_isShowingStatusBox = true;
    
        m_connectionStatus = @"LOG ONLY";
        
        m_timer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                   target:self
                                                 selector:@selector(timerFired:)
                                                 userInfo:nil
                                                  repeats:YES];

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
    if (m_bitmap != NULL) free(m_bitmap);
    
    [m_connectionStatus release];
    
    [m_centerAlignStyle release];
    [m_rightAlignStyle release];
    
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    m_bitmapGenerator->lock();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
    CGContextRef context = CGBitmapContextCreate(m_bitmapGenerator->bitmap(),
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
    m_bitmapGenerator->unlock();
    
    //
    
    double leftTime = [self screenLeftTime];
    double rightTime = [self screenRightTime];

    //
    
    [[NSColor blackColor] setFill];
    NSRectFill(NSMakeRect(0.0f, 0.0f, self.bounds.size.width, OCCURRENCE_LANES_HEIGHT));
    
    // rate calculator
    
    if (m_downPoint.x >= 0 && !m_isDraggingKnob)
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
    
    // occurrence lanes
    
    double pendingLastTimes[10];
    for (int i = 0; i < 10; i++) pendingLastTimes[i] = 0.0;

    m_state->lock();
    
    std::vector<OccurrenceRecord> *occurrences = m_state->occurrences();
    std::vector<OccurrenceRecord>::iterator iter;
    for (iter = occurrences->begin(); iter != occurrences->end(); ++iter)
    {
        OccurrenceRecord record = *iter;
        NSString *tailNumberString = [NSString stringWithFormat:@"%05d", record.tailNumber];
        
        if ((record.lastTime > leftTime && record.lastTime < rightTime)
            || (record.firstTime > leftTime && record.firstTime < rightTime)
            || (record.firstTime < leftTime && record.lastTime > rightTime))
        {
            float firstX = (record.firstTime - leftTime) / m_timeSlice;
            float lastX = (record.lastTime - leftTime) / m_timeSlice;

            int n;
            for (int i = 0; i < 10; i++)
            {
                if (record.firstTime > pendingLastTimes[i])
                {
                    pendingLastTimes[i] = record.lastTime;
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
    
    // scroller

    [[NSColor whiteColor] set];
    
    NSBezierPath *scrollerPath = [NSBezierPath bezierPathWithRect:NSMakeRect(0.0f, self.bounds.size.height - TIME_SCROLLER_HEIGHT, self.bounds.size.width - 1.0f, TIME_SCROLLER_HEIGHT - 1.0f)];
    [scrollerPath stroke];

    if (m_state->points()->size() > 1)
    {
        float normalizedLeftTime = (leftTime - m_firstTime) / (m_lastTime - m_firstTime);
        float normalizedRightTime = (rightTime - m_firstTime) / (m_lastTime - m_firstTime);
        float knobLeftX = normalizedLeftTime * self.bounds.size.width;
        float knobRightX = normalizedRightTime * self.bounds.size.width;
        
        m_knobRect = NSMakeRect(knobLeftX, self.bounds.size.height - TIME_SCROLLER_HEIGHT + 1.0f, knobRightX - knobLeftX, TIME_SCROLLER_HEIGHT - 3.0f);
        
        NSBezierPath *scrollerKnobPath = [NSBezierPath bezierPathWithRect:m_knobRect];
        [scrollerKnobPath stroke];
        
        [[[NSColor whiteColor] colorWithAlphaComponent:0.4f] setFill];
        [scrollerKnobPath fill];
    }

    m_state->unlock();
    
    // ground

    [[NSColor redColor] set];
    
    NSBezierPath *ground = [NSBezierPath bezierPath];
    [ground moveToPoint:NSMakePoint(0.0f, OCCURRENCE_LANES_HEIGHT)];
    [ground lineToPoint:NSMakePoint(self.bounds.size.width, OCCURRENCE_LANES_HEIGHT)];
    [ground stroke];

    // line cross

    if (m_isLineCrossEnabled && m_hoverPoint.y > OCCURRENCE_LANES_HEIGHT)
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
    NSString *altTimeString = [NSString stringWithFormat:@"alt %d time %@", hoverAlt, [self timeString:hoverTime]];
    NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_centerAlignStyle};
    [altTimeString drawInRect:NSMakeRect(0.0f, self.bounds.size.height - 22.0f, self.bounds.size.width, 18.0f) withAttributes:attributes];
    
    // times
    
    NSDictionary *leftTimeAttributes = @{NSForegroundColorAttributeName: [NSColor whiteColor]};
    NSString *leftTimeString = [self timeString:leftTime];
    [leftTimeString drawInRect:NSMakeRect(4.0f, self.bounds.size.height - TIME_SCROLLER_HEIGHT - 24.0f, 200.0f, 20.0f) withAttributes:leftTimeAttributes];

    NSDictionary *rightTimeAttributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_rightAlignStyle};
    NSString *rightTimeString = [self timeString:rightTime];
    [rightTimeString drawInRect:NSMakeRect(self.bounds.size.width - 204.0f, self.bounds.size.height - TIME_SCROLLER_HEIGHT - 24.0f, 200.0f, 20.0f) withAttributes:rightTimeAttributes];
    
    // notification
    
    if (m_isNotificationShown)
    {
        NSRect notificationBoxRect = NSMakeRect((self.bounds.size.width - NOTIFICATION_BOX_WIDTH) / 2.0f, (self.bounds.size.height - NOTIFICATION_BOX_HEIGHT) / 2.0f, NOTIFICATION_BOX_WIDTH, NOTIFICATION_BOX_HEIGHT);
        
        NSBezierPath *notificationPath = [NSBezierPath bezierPathWithRect:notificationBoxRect];
        [[NSColor blueColor] set];
        [notificationPath stroke];
        
        [[[NSColor blueColor] colorWithAlphaComponent:0.5] setFill];
        [notificationPath fill];
        
        notificationBoxRect.origin.y -= 2.0f;
        NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_centerAlignStyle};
        [m_notificationText drawInRect:notificationBoxRect withAttributes:attributes];
    }
    
    // realtime line
    
    if (m_realtimeMarkerTime > 1.0)
    {
        float x = [self xForTime:m_realtimeMarkerTime];
        NSBezierPath *realtimeMarker = [NSBezierPath bezierPath];
        [realtimeMarker moveToPoint:NSMakePoint(x, 0.0f)];
        [realtimeMarker lineToPoint:NSMakePoint(x, self.bounds.size.height)];
        [realtimeMarker stroke];
    }
    
    // status box
    
    if (m_isShowingStatusBox)
    {
        NSRect statusBoxRect = NSMakeRect((self.bounds.size.width - STATUS_BOX_WIDTH) / 2.0f, self.bounds.size.height - TIME_SCROLLER_HEIGHT - STATUS_BOX_HEIGHT, STATUS_BOX_WIDTH, STATUS_BOX_HEIGHT);
        
        NSBezierPath *statusBoxPath = [NSBezierPath bezierPathWithRect:statusBoxRect];
        [statusBoxPath stroke];
        
        NSString *statusString = [NSString stringWithFormat:@"%s | %@ | %s | %s | %s | BOLD %d",
                                  m_state->isRealtimeStarted() ? "RT" : "LOG",
                                  m_connectionStatus,
                                  m_isLockedOnRealtimeMarker ? "LOCK" : "NO LOCK",
                                  m_isBeepingEnabled ? "BEEP" : "NO BEEP",
                                  m_bitmapGenerator->isConfidence4Only() ? "C4" : "C3+C4",
                                  m_bitmapGenerator->boldThreshold()];

        statusBoxRect.origin.y -= 2.0f;
        NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor whiteColor], NSParagraphStyleAttributeName: m_centerAlignStyle};
        [statusString drawInRect:statusBoxRect withAttributes:attributes];
    }
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

- (BOOL)acceptsFirstResponder
{
    return YES;
}

#pragma mark -

- (void)showNotification:(NSString *)text
{
    m_isNotificationShown = true;
    m_notificationTimeLeft = 2.0f;
    
    if (m_notificationText != text)
    {
        [m_notificationText release];
        m_notificationText = text;
        [m_notificationText retain];
    }
    
    [self setNeedsDisplay:YES];
}

- (void)timerFired:(NSTimer *)timer
{
    if (m_notificationTimeLeft >= 0.0f)
    {
        m_notificationTimeLeft -= 0.1f;
    }
    else if (m_isNotificationShown)
    {
        m_isNotificationShown = false;
        [self setNeedsDisplay:YES];
    }
    
    NSTimeInterval timeLocal = [NSDate timeIntervalSinceReferenceDate];
    if (m_state->isRealtimeStarted() && timeLocal > m_realtimeTickTimeLocal)
    {
        m_realtimeTickTimeLocal = timeLocal + 1.0;

        m_realtimeMarkerTime = m_lastTime + (timeLocal - m_lastTimeLocal);

        if (m_isLockedOnRealtimeMarker)
        {
            [self scrollToRealtimeMarker];
        }
        
        [self updateBitmap];
    }
}

#pragma mark -

- (void)mouseDown:(NSEvent *)event
{
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_downPoint = location;
    m_dragPoint = location;
    
    if (NSPointInRect(m_downPoint, m_knobRect))
    {
        m_isDraggingKnob = true;
        m_knobDragOffset = m_downPoint.x - m_knobRect.origin.x;
    }
    
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_dragPoint = location;
    
    if (m_isDraggingKnob)
    {
        double normalizedTimeOffset = (m_dragPoint.x - m_knobDragOffset) / self.bounds.size.width;
        [self setTimeOffset:(m_lastTime - m_firstTime) * normalizedTimeOffset];
        [self updateBitmap];
    }
    
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
//    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    m_downPoint = NSMakePoint(-1.0f, -1.0f);
    m_isDraggingKnob = false;
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event
{
    m_hoverPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    
    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    if (event.keyCode == kVK_Space)
    {
        m_isLineCrossEnabled = !m_isLineCrossEnabled;
        
        [self setNeedsDisplay:YES];
    }
    else if (event.keyCode == kVK_UpArrow)
    {
        m_timeSlice += 1.0;
        if (m_timeSlice > 10.0) m_timeSlice = 10.0;
        
        if (m_isLockedOnRealtimeMarker)
        {
            [self scrollToRealtimeMarker];
        }

        [self updateBitmap];
    }
    else if (event.keyCode == kVK_DownArrow)
    {
        m_timeSlice -= 1.0;
        if (m_timeSlice < 1.0) m_timeSlice = 1.0;

        if (m_isLockedOnRealtimeMarker)
        {
            [self scrollToRealtimeMarker];
        }

        [self updateBitmap];
    }
    else if (event.keyCode == kVK_LeftArrow)
    {
        double timeOffset = m_timeOffset - (10.0 * m_timeSlice * [self modifierMultiplier]);
        [self setTimeOffset:timeOffset];
        
        [self updateBitmap];
    }
    else if (event.keyCode == kVK_RightArrow)
    {
        double timeOffset = m_timeOffset + (10.0 * m_timeSlice * [self modifierMultiplier]);
        [self setTimeOffset:timeOffset];
        
        [self updateBitmap];
    }
    else if (event.keyCode == kVK_ANSI_C)
    {
        bool isConfidence4Only = !m_bitmapGenerator->isConfidence4Only();
        m_bitmapGenerator->setConfidence4Only(isConfidence4Only);
        
        [self showNotification:[NSString stringWithFormat:@"Show only confidence 4 points: %s.", isConfidence4Only ? "ON" : "OFF"]];
        
        [self updateBitmap];
    }
    else if (event.keyCode == kVK_ANSI_Q)
    {
        int boldThreshold = m_bitmapGenerator->boldThreshold() + 10;
        if (boldThreshold > 250) boldThreshold = 250;
        m_bitmapGenerator->setBoldThreshold(boldThreshold);

        [self showNotification:[NSString stringWithFormat:@"Bold threshold set to %d.", boldThreshold]];
        
        [self updateBitmap];
    }
    else if (event.keyCode == kVK_ANSI_A)
    {
        int boldThreshold = m_bitmapGenerator->boldThreshold() - 10;
        if (boldThreshold < 0) boldThreshold = 0;
        m_bitmapGenerator->setBoldThreshold(boldThreshold);
        
        [self showNotification:[NSString stringWithFormat:@"Bold threshold set to %d.", boldThreshold]];
        
        [self updateBitmap];
    }
    else if (event.keyCode == kVK_ANSI_L)
    {
        if (!m_isLockedOnRealtimeMarker && m_state->isRealtimeStarted())
        {
            m_isLockedOnRealtimeMarker = true;
            
            [self scrollToRealtimeMarker];
            
            [self showNotification:@"Locked on realtime marker."];
        
            [self updateBitmap];
        }
    }
    else if (event.keyCode == kVK_ANSI_B)
    {
        m_isBeepingEnabled = !m_isBeepingEnabled;

        [self showNotification:[NSString stringWithFormat:@"Beep on new points: %s.", m_isBeepingEnabled ? "ON" : "OFF"]];
        
        [self setNeedsDisplay:YES];
    }
    else if (event.keyCode == kVK_ANSI_R)
    {
        [[NSApp delegate] requestReconnect];
    }
    else if (event.keyCode == kVK_ANSI_D)
    {
        [[NSApp delegate] requestDisconnect];
    }
    else if (event.keyCode == kVK_ANSI_I)
    {
        m_isShowingStatusBox = !m_isShowingStatusBox;
        
        [self setNeedsDisplay:YES];
    }
    else if (event.keyCode == kVK_F1)
    {
        NSMutableString *message = [NSMutableString string];
        [message appendString:@"Left/right arrows : time offset\n"];
        [message appendString:@"Up/down arrows : time scale\n"];
        [message appendString:@"Space : toggle line cross\n"];
        [message appendString:@"Q/A : change bold threshold\n"];
        [message appendString:@"C : toggle 4 points only confidence\n"];
        [message appendString:@"L : lock on realtime marker\n"];
        [message appendString:@"B : toggle beep on new points\n"];
        [message appendString:@"R/D : reconnect/disconnect\n"];
        [message appendString:@"I : toggle status box\n"];
        [message appendString:@"\n"];
        [message appendString:@"When changing time offset: Shift increases scroll speed, Alt decreases."];
        
        NSRunAlertPanel(@"UVDG Help",
                        @"%@",
                        @"OK",
                        @"",
                        @"",
                        message);
    }
}

- (void)scrollWheel:(NSEvent *)event
{
    float delta = [event deltaY] != 0.0 ? [event deltaY] : [event deltaX];  // if shift is pressed Y scroll becomes X scroll
    
    double timeOffset = m_timeOffset - (delta * m_timeSlice * [self modifierMultiplier]);
    [self setTimeOffset:timeOffset];

    [self updateBitmap];
}

#pragma mark -

- (void)startRealtimeMode
{
    m_isStartingRealtimeMode = true;
}

- (void)uvdStateChanged:(double)time
{
    if (m_isStartingRealtimeMode)
    {
        m_isStartingRealtimeMode = false;
        m_isLockedOnRealtimeMarker = true;
    }
    
    if (m_firstTime < 0.0)
    {
        m_firstTime = time;
    }
    
    m_lastTime = time;
    m_realtimeMarkerTime = time;
    m_lastTimeLocal = [NSDate timeIntervalSinceReferenceDate];
    m_realtimeTickTimeLocal = m_lastTimeLocal + 1.0;
    
    if (m_isBeepingEnabled)
    {
        if (!m_isBeepPlaying)
        {
            [m_beep play];
            m_isBeepPlaying = true;
        }
    }
    
    if (m_isLockedOnRealtimeMarker)
    {
        [self scrollToRealtimeMarker];
    }
    
    if (m_lastUpdateTimeLocal + 0.5 > [NSDate timeIntervalSinceReferenceDate])
    {
//        NSLog(@"delaying update.");
    }
    else
    {
        [self updateBitmap];
    }
}

- (void)setConnectionStatus:(NSString *)status
{
    if (status != m_connectionStatus)
    {
        [status retain];
        [m_connectionStatus release];
        m_connectionStatus = status;
    }
    
    [self setNeedsDisplay:YES];
}

- (void)tcpConnecting
{
    [self setConnectionStatus:@"CONN ..."];
}

- (void)tcpConnected
{
    [self setConnectionStatus:@"CONN OK"];
}

- (void)tcpReconnectIn:(int)seconds
{
    [self setConnectionStatus:[NSString stringWithFormat:@"RECONN IN %d", seconds]];
}

- (void)tcpDisconnected
{
    [self setConnectionStatus:@"CONN OFF"];
    [self showNotification:@"Disconnected."];
}

#pragma mark -

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)aBool
{
    m_isBeepPlaying = false;
}

@end
