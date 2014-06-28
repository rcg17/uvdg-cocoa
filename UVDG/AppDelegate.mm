
#import "AppDelegate.h"

#define HIDE_TAILNUMBERS NO
#define DUPLICATE_DETECTOR_BUFFER_SIZE 1000

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSString *logFilePath = [[NSUserDefaults standardUserDefaults] stringForKey:@"logFilePath"];
    [m_logFilePathLabel setStringValue:logFilePath != nil ? logFilePath : @""];
    
    NSString *serverHost = [[NSUserDefaults standardUserDefaults] stringForKey:@"serverHost"];
    [m_hostField setStringValue:serverHost != nil ? serverHost : @"127.0.0.1"];

    NSString *serverPort = [[NSUserDefaults standardUserDefaults] stringForKey:@"serverPort"];
    [m_portField setStringValue:serverPort != nil ? serverPort : @"31003"];
    
    m_buffer = (char *)malloc(256);
    m_bufferSize = 0;
    
    [self updateControlsState];
}

#pragma mark -

- (void)updateControlsState
{
    BOOL isLogEnabled = m_useLogSwitch.state == NSOnState;
    BOOL isServerEnabled = m_useServerSwitch.state == NSOnState;

    [m_chooseLogFileButton setEnabled:isLogEnabled];
    
    [m_hostField setEnabled:isServerEnabled];
    [m_portField setEnabled:isServerEnabled];
    
    [m_goButton setEnabled:isLogEnabled || isServerEnabled];
}

- (IBAction)useSwitchAction:(id)sender
{
    [self updateControlsState];
}

- (IBAction)chooseLogFileAction:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];

    NSInteger result = [panel runModal];
    if (result == 0)
    {
        // cancel
        return;
    }
    
    NSString *path = [[panel URLs][0] path];
    
    [m_logFilePathLabel setStringValue:path];
    
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:@"logFilePath"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)goAction:(id)sender
{
    [m_goButton setEnabled:NO];
    
    m_state = new UvdState();
    m_parser = new RtlUvdParser(m_state);
    
    NSString *logFilePath = [m_logFilePathLabel stringValue];
    NSString *logFileName = [logFilePath lastPathComponent];
    
    int yyyy, mm, dd;
    int gotTokens = sscanf([logFileName UTF8String], "rtl-uvd-log-%04d-%02d-%02d", &yyyy, &mm, &dd);
    if (gotTokens == 3)
    {
        m_state->setStartDate(yyyy, mm, dd);
    }
    
    if (m_useLogSwitch.state == NSOnState)
    {
        m_parser->parseLogFile([logFilePath UTF8String]);
    }
    
    [self.window close];

    m_graphWindowController = [[GraphWindowController alloc] initWithUvdState:m_state];
    [m_graphWindowController.window center];
    [m_graphWindowController.window makeKeyAndOrderFront:nil];
    
    [NSApp activateIgnoringOtherApps:YES];
    
    if (m_useServerSwitch.state == NSOnState)
    {
        m_state->startRealtimeMode();
        [[m_graphWindowController graphView] startRealtimeMode];
        
        [self performSelectorInBackground:@selector(tcpThread) withObject:nil];
        
        [[NSUserDefaults standardUserDefaults] setObject:[m_hostField stringValue] forKey:@"serverHost"];
        [[NSUserDefaults standardUserDefaults] setObject:[m_portField stringValue] forKey:@"serverPort"];
    }
}

#pragma mark -

- (void)stopReconnectTimer
{
    [m_reconnectTimer invalidate];
    m_reconnectTimer = nil;
}

- (void)connect
{
    NSLog(@"connecting.");

    if (m_reconnectDelay < 30)
    {
        m_reconnectDelay += 1;
    }
 
    [self stopReconnectTimer];

    [[m_graphWindowController graphView] tcpConnecting];
    
    CFReadStreamRef readStream;
    CFStreamCreatePairWithSocketToHost(NULL, (CFStringRef)[m_hostField stringValue], [m_portField intValue], &readStream, NULL);
    
    m_inputStream = (NSInputStream *)readStream;
    [m_inputStream setDelegate:self];
    [m_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [m_inputStream open];
}

- (void)tcpThread
{
    m_tcpThread = [NSThread currentThread];
    
    [self connect];
    
    [[NSRunLoop currentRunLoop] run];
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{    
    switch (eventCode)
    {
        case NSStreamEventOpenCompleted:
            NSLog(@"TCP: connected.");
            
            m_reconnectDelay = 1;

            [self stopReconnectTimer];

            [[m_graphWindowController graphView] tcpConnected];
            
            break;

        case NSStreamEventHasBytesAvailable:
        {
            NSInteger bytesRead;
            do
            {
                bytesRead = [(NSInputStream *)stream read:(uint8_t *)(m_buffer + m_bufferSize) maxLength:256 - m_bufferSize];
                m_bufferSize += bytesRead;
                
                char *eol;
                do
                {
                    eol = strnstr((const char *)m_buffer, "\r\n", m_bufferSize);
                    if (eol != NULL)
                    {
                        eol[0] = '\x00';
                        
                        double lineTime = m_parser->processLine(m_buffer);
                        if (lineTime > 0.0)
                        {
                            [[m_graphWindowController graphView] uvdStateChanged:lineTime];
                        }
                        
                        NSInteger lineLength = eol - m_buffer + 2;
                        memmove(m_buffer, eol + 2, m_bufferSize - lineLength);
                        m_bufferSize -= lineLength;
                    }
                } while (eol != NULL);
                
                if (m_bufferSize == 256)
                {
                    m_bufferSize = 0;
                }
                
            } while (bytesRead > 0);
                        
            break;
        }
            
        case NSStreamEventErrorOccurred:
        case NSStreamEventEndEncountered:
            NSLog(@"connection lost.");

            [m_inputStream release];
            
            [[m_graphWindowController graphView] tcpReconnectIn:m_reconnectDelay];

            NSLog(@"scheduling reconnect in %d.", m_reconnectDelay);
            m_secondsToReconnect = m_reconnectDelay;
            
            [self stopReconnectTimer];
            
            m_reconnectTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                target:self
                                                              selector:@selector(reconnectTimerFired:)
                                                              userInfo:nil
                                                               repeats:YES];
            break;

        default:
            break;
    }
}

- (void)reconnectTimerFired:(NSTimer *)timer
{
    m_secondsToReconnect -= 1;
    if (m_secondsToReconnect == 0)
    {
        [self connect];
    }
    else
    {
        [[m_graphWindowController graphView] tcpReconnectIn:m_secondsToReconnect];
    }
}

#pragma mark -

- (void)reconnect
{
    NSLog(@"reconnecting.");

    m_reconnectDelay = 0;
    [self connect];
}

- (void)disconnect
{
    NSLog(@"disconnecting.");
    
    [self stopReconnectTimer];
    
    [m_inputStream release];
    m_inputStream = nil;
    
    [[m_graphWindowController graphView] tcpDisconnected];
}

- (void)requestReconnect
{
    [self performSelector:@selector(reconnect) onThread:m_tcpThread withObject:nil waitUntilDone:NO];
}

- (void)requestDisconnect
{
    [self performSelector:@selector(disconnect) onThread:m_tcpThread withObject:nil waitUntilDone:NO];
}

@end
