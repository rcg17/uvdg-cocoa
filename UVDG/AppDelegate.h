
#import "GraphWindowController.h"
#include "UvdState.h"
#import "RtlUvdParser.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, NSStreamDelegate>
{
    GraphWindowController *m_graphWindowController;
    
    IBOutlet NSButton *m_useLogSwitch;
    IBOutlet NSButton *m_chooseLogFileButton;
    IBOutlet NSTextField *m_logFilePathLabel;

    IBOutlet NSButton *m_useServerSwitch;
    IBOutlet NSTextField *m_hostField;
    IBOutlet NSTextField *m_portField;
    
    IBOutlet NSButton *m_goButton;
    
    UvdState *m_state;
    RtlUvdParser *m_parser;
    
    NSThread *m_tcpThread;
    NSInputStream *m_inputStream;
    int m_reconnectDelay;
    int m_secondsToReconnect;
    NSTimer *m_reconnectTimer;

    char *m_buffer;
    int m_bufferSize;
}

@property (assign) IBOutlet NSWindow *window;

- (IBAction)useSwitchAction:(id)sender;
- (IBAction)chooseLogFileAction:(id)sender;
- (IBAction)goAction:(id)sender;

- (void)requestDisconnect;
- (void)requestReconnect;

@end
