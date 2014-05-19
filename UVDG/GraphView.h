
#import "AppDelegate.h"

@interface GraphView : NSView
{
    uint8 *m_bitmap;

    NSArray *m_occurrences;

    NSArray *m_points;
    double m_firstTime;
    double m_lastTime;
    
    double m_normalizedTimeOffset;
    double m_timeSlice;
    BOOL m_confidence4Only;
    int m_boldThreshold;
    
    NSPoint m_downPoint;
    NSPoint m_dragPoint;
    NSPoint m_hoverPoint;
    BOOL m_showLineCross;
    
    NSRect m_bitmapRect;
    
    NSTrackingArea *m_trackingArea;
    
    NSParagraphStyle *m_centerAlignStyle;
    NSParagraphStyle *m_rightAlignStyle;
}

- (void)setOccurrences:(NSArray *)occurrences andPoints:(NSArray *)points;
- (void)setNormalizedTimeOffset:(double)normalizedTimeOffset;
- (void)setZoom:(double)zoom;
- (void)setConfidence4Only:(BOOL)flag;
- (void)setBoldThreshold:(double)boldThreshold;

@end
