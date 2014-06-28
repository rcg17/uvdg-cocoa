
#import "UvdState.h"
#import "UvdBitmapGenerator.h"

@interface GraphView : NSView < NSSoundDelegate>
{
    UvdState *m_state;
    
    UvdBitmapGenerator *m_bitmapGenerator;
    uint8 *m_bitmap;
    NSRect m_bitmapRect;
    
    double m_firstTime;
    double m_lastTime;
    double m_timeOffset;
    double m_timeSlice;
    BOOL m_isLineCrossEnabled;
    
    NSPoint m_downPoint;
    NSPoint m_dragPoint;
    NSPoint m_hoverPoint;
    int m_hoverFuel;
    
    NSRect m_knobRect;
    bool m_isDraggingKnob;
    float m_knobDragOffset;
    
    bool m_isNotificationShown;
    float m_notificationTimeLeft;
    NSString *m_notificationText;
    
    bool m_isStartingRealtimeMode;
    double m_realtimeMarkerTime;
    bool m_isLockedOnRealtimeMarker;

    NSTimeInterval m_lastTimeLocal;
    NSTimeInterval m_realtimeTickTimeLocal;
    NSTimeInterval m_lastUpdateTimeLocal;
    
    bool m_isBeepingEnabled;
    bool m_isBeepPlaying;
    NSSound *m_beep;
    
    bool m_isShowingStatusBox;
    
    NSString *m_connectionStatus;

    NSTimer *m_timer;

    NSTrackingArea *m_trackingArea;
    
    NSParagraphStyle *m_centerAlignStyle;
    NSParagraphStyle *m_rightAlignStyle;
}

- (id)initWithFrame:(NSRect)frame andUvdState:(UvdState *)state;

- (void)startRealtimeMode;

- (void)uvdStateChanged:(double)time;

- (void)tcpConnecting;
- (void)tcpConnected;
- (void)tcpReconnectIn:(int)seconds;
- (void)tcpDisconnected;

@end
