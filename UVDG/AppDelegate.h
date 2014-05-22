
typedef struct {
    int hh, mm, ss, usec;
    double time;
    int amplitude;
    int confidence;
} RecvInfo;

typedef struct {
    RecvInfo ri;
    int tailNumber;
} K1;

typedef struct {
    RecvInfo ri;
    int alt;
    int fuel;
} K2;

@class GraphView;

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    IBOutlet GraphView *m_graphView;
    IBOutlet NSSlider *m_timeOffsetSlider;
    IBOutlet NSSlider *m_zoomSlider;
    IBOutlet NSButton *m_confidence4OnlySwitch;
    IBOutlet NSSlider *m_boldThresholdSlider;
    
    NSMutableDictionary *m_pendingOccurrences;
    NSMutableArray *m_occurrences;
    NSMutableArray *m_points;
    double *m_duplicateDetectorBuffer;
    int m_duplicateDetectorBufferIndex;
    
    NSTimeInterval m_lastTime;
    int m_day;
    
    NSUInteger m_k1Conf3Lines;
    NSUInteger m_k2Conf3Lines;
    NSUInteger m_k1Conf4Lines;
    NSUInteger m_k2Conf4Lines;
}

@property (assign) IBOutlet NSWindow *window;

- (IBAction)timeOffsetAction:(id)sender;
- (IBAction)zoomAction:(id)sender;
- (IBAction)confidence4OnlyAction:(id)sender;
- (IBAction)boldThresholdAction:(id)sender;

@end
