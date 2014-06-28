
#import "UvdState.h"
#import "GraphView.h"

@interface GraphWindowController : NSWindowController
{
    UvdState *m_state;

    GraphView *m_graphView;
}

- (id)initWithUvdState:(UvdState *)state;

- (GraphView *)graphView;

@end
