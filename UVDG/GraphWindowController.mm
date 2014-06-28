
#import "GraphWindowController.h"

@implementation GraphWindowController

- (id)initWithUvdState:(UvdState *)state
{
    if ((self = [super initWithWindowNibName:@""]))
    {
        m_state = state;
    }

    return self;
}

- (void)loadWindow
{
    NSRect rect = NSMakeRect(0.0f, 0.0f, 800.0f, 400.0f);

    NSPanel *window = [[[NSPanel alloc] initWithContentRect:rect
                                                  styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO] autorelease];
    self.window = window;
    [window setTitle:@"UVDG Timeline"];
    [window setMinSize:NSMakeSize(512.0, 200.0)];

    m_graphView = [[GraphView alloc] initWithFrame:rect andUvdState:m_state];
    [m_graphView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    window.contentView = m_graphView;
}

- (GraphView *)graphView
{
    return m_graphView;
}

@end
