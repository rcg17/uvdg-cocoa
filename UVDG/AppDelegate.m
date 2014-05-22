
#import "AppDelegate.h"
#import "GraphView.h"

#define HIDE_TAILNUMBERS NO
#define DUPLICATE_DETECTOR_BUFFER_SIZE 1000

@implementation AppDelegate

- (void)gotK1:(K1)k1
{
    if (k1.ri.confidence == 3)
    {
        m_k1Conf3Lines++;
    }
    else
    {
        m_k1Conf4Lines++;
    }
    
    NSNumber *time = [NSNumber numberWithDouble:k1.ri.time];
    NSNumber *tailNumber = [NSNumber numberWithInt:k1.tailNumber];

    if (m_pendingOccurrences[tailNumber] == nil)
    {
//        NSLog(@"new aircraft: %d.", k1.tailNumber);
        NSMutableDictionary *dict = [[@{@"tailNumber": tailNumber, @"first": time, @"last": time} mutableCopy] autorelease];
        m_pendingOccurrences[tailNumber] = dict;
    }
    else
    {
        m_pendingOccurrences[tailNumber][@"last"] = time;
    }
}

- (void)gotK2:(K2)k2
{
    if (k2.ri.confidence == 3)
    {
        m_k2Conf3Lines++;
    }
    else
    {
        m_k2Conf4Lines++;
    }
    
    NSValue *k2Value = [NSValue value:&k2 withObjCType:@encode(K2)];
    [m_points addObject:k2Value];
}

- (void)processLine:(char *)line
{
    // K1 14:57:41.207.405 [ 1776] {087} **** :01234
    // K2 14:57:41.212.757 [ 5352] {088} **** FL  770m [F025]+  F:40%
    
//    NSLog(@"line: %s", line);
    if (line[0] != 'K') return;
    if (line[1] < '1' && line[1] > '4') return;
    
    RecvInfo ri;
    ri.hh = atoi(line + 3);
    ri.mm = atoi(line + 6);
    ri.ss = atoi(line + 9);
    int msec = atoi(line + 12);
    int usec = atoi(line + 16);
    ri.usec = msec * 1000 + usec;
    
    int seconds = ri.hh * 3600 + ri.mm * 60 + ri.ss;
    double time = seconds + ((double)ri.usec / 1000000.0);
    
    for (int i = 0; i < DUPLICATE_DETECTOR_BUFFER_SIZE; i++)
    {
        if (time == m_duplicateDetectorBuffer[i])
        {
//            NSLog(@"duplicated line, ignoring: %s", line);
            return;
        }
    }
    
    m_duplicateDetectorBuffer[m_duplicateDetectorBufferIndex] = time;
    m_duplicateDetectorBufferIndex++;
    if (m_duplicateDetectorBufferIndex == DUPLICATE_DETECTOR_BUFFER_SIZE) m_duplicateDetectorBufferIndex = 0;
    
    if (time < m_lastTime)
    {
        // crossed 00:00:00
        m_day++;
        NSLog(@"day cross %d (%02d:%02d:%02d (%lf) < %lf).", m_day, ri.hh, ri.mm, ri.ss, time, m_lastTime);
    }
    double fixedTime = time + (m_day * 24 * 60 * 60);
    ri.time = fixedTime;
    
    m_lastTime = time;
    
    sscanf(line + 30, "%02X", &ri.amplitude);
    
    ri.confidence = (line[34] == '*') + (line[35] == '*') + (line[36] == '*') + (line[37] == '*');
    
    if (line[1] == '1')
    {
        int tn = atoi(line + 40);
        
        K1 k1;
        k1.ri = ri;
        k1.tailNumber = tn;
        
        if (k1.tailNumber == 0)
        {
//            NSLog(@"bad tail number: %s.", line + 40);
        }
        else
        {
            [self gotK1:k1];
        }
    }
    else if (line[1] == '2')
    {
        int alt = atoi(line + 42);
        int fuel = atoi(line + 59);

        K2 k2;
        k2.ri = ri;
        k2.alt = alt;
        k2.fuel = fuel;
        [self gotK2:k2];
    }
    else if (line[1] == '3')
    {
//        NSLog(@"%s", line);
        return;
    }
    else
    {
//        NSLog(@"%s", line);
        return;
    }
    
    NSMutableArray *finalizedOccurrences = [NSMutableArray new];
    for (NSNumber *tailNumber in m_pendingOccurrences.allKeys)
    {
        NSDictionary *dict = m_pendingOccurrences[tailNumber];
        double lastTime = [dict[@"last"] doubleValue];
        if (lastTime + 100.0 < fixedTime)
        {
            [finalizedOccurrences addObject:tailNumber];
        }
    }
    
    for (NSNumber *tailNumber in finalizedOccurrences)
    {
        NSDictionary *dict = m_pendingOccurrences[tailNumber];
        double firstTime = [dict[@"first"] doubleValue];
        double lastTime = [dict[@"last"] doubleValue];
        
        if (lastTime - firstTime > 1.0)
        {
            [m_occurrences addObject:dict];
        }
        
        [m_pendingOccurrences removeObjectForKey:tailNumber];
    }
    [finalizedOccurrences release];
}

- (void)obtainAircraftStatistics
{
    NSMutableDictionary *aircrafts = [NSMutableDictionary dictionary];
    for (NSDictionary *dict in m_occurrences)
    {
        NSString *tailNumber = dict[@"tailNumber"];
        NSNumber *first = dict[@"first"];
        NSNumber *last = dict[@"last"];

        NSMutableArray *occurrences = aircrafts[tailNumber];
        if (occurrences == nil)
        {
            occurrences = [NSMutableArray array];
            aircrafts[tailNumber] = occurrences;
        }
        
        NSDictionary *occurrence = @{@"first": first, @"last": last};
        [occurrences addObject:occurrence];
    }
    
    NSArray *sortedTailNumbers = [[aircrafts allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    NSLog(@"Unique aircrafts: %ld.", [[aircrafts allKeys] count]);
    for (NSString *tailNumber in sortedTailNumbers)
    {
        double duration = 0.0;
        NSArray *occurrences = aircrafts[tailNumber];
        NSMutableSet *days = [NSMutableSet set];
        for (NSDictionary *occurrence in occurrences)
        {
            double first = [occurrence[@"first"] doubleValue];
            double last = [occurrence[@"last"] doubleValue];
            
            int firstDay = (int)first / 86400;
            int lastDay = (int)last / 86400;
            
            [days addObject:[NSNumber numberWithInt:firstDay]];
            [days addObject:[NSNumber numberWithInt:lastDay]];
            
            duration += last - first;
        }
        
        NSLog(@"%05d: %ld occurrence(s), duration %.0lf mins over %ld day(s).",
              [tailNumber intValue], [occurrences count], duration / 60.0, [days count]);
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    NSInteger result = [panel runModal];
    if (result == 0)
    {
        // cancel
        [NSApp terminate:nil];
        return;
    }
    NSString *path = [[panel URLs][0] path];
    
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil)
    {
        NSLog(@"bad log file: %@.", path);
        [NSApp terminate:nil];
        return;
    }
    
    m_pendingOccurrences = [NSMutableDictionary dictionary];
    m_occurrences = [NSMutableArray array];
    m_points = [NSMutableArray array];
    m_duplicateDetectorBuffer = (double *)calloc(1, DUPLICATE_DETECTOR_BUFFER_SIZE * sizeof(double));

    NSUInteger i = 0, length = data.length;
    char *c = (char *)data.bytes;
    char line[100];
    int j = 0;
    while (i++ < length)
    {
        if (*c == '\r')
        {
            c++;
            continue;
        }
        
        if (*c == '\n')
        {
            c++;
            line[j] = 0;
            j = 0;
            [self processLine:line];
            continue;
        }

        if (j < 100)
        {
            line[j++] = *c;
        }
        
        c++;
    }

    // finalize
    for (NSString *tailNumber in m_pendingOccurrences)
    {
        [m_occurrences addObject:m_pendingOccurrences[tailNumber]];
    }
    
    NSLog(@"Confidence 3: K1 lines: %ld, K2 lines: %ld.", m_k1Conf3Lines, m_k2Conf3Lines);
    NSLog(@"Confidence 4: K1 lines: %ld, K2 lines: %ld.", m_k1Conf4Lines, m_k2Conf4Lines);
    NSLog(@"Days: %d.", m_day + 1);
    
    if (HIDE_TAILNUMBERS)
    {
        char randomTailNumber[6];
        randomTailNumber[5] = '\x00';
        for (NSMutableDictionary *dict in m_occurrences)
        {
            for (int i = 0; i < 5; i++)
            {
                int r = arc4random() % 10;
                randomTailNumber[i] = '0' + r;
            }
            dict[@"tailNumber"] = [NSString stringWithUTF8String:randomTailNumber];
        }
    }
    
    [self obtainAircraftStatistics];
    
    [m_graphView setOccurrences:m_occurrences andPoints:m_points];
}

#pragma mark -

- (IBAction)timeOffsetAction:(id)sender
{
    [m_graphView setNormalizedTimeOffset:m_timeOffsetSlider.doubleValue];
}

- (IBAction)zoomAction:(id)sender
{
    [m_graphView setZoom:m_zoomSlider.doubleValue];
}

- (IBAction)confidence4OnlyAction:(id)sender
{
    [m_graphView setConfidence4Only:m_confidence4OnlySwitch.state == NSOnState];
}

- (IBAction)boldThresholdAction:(id)sender
{
    [m_graphView setBoldThreshold:m_boldThresholdSlider.doubleValue];
}

@end
