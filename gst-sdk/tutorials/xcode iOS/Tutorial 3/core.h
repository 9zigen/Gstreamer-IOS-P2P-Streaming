#include <UIKit/UIView.h>
#include <gst/gst.h>

/*
 * Gstreamer data holder
 */
typedef struct _Gstreamer Gstreamer;
struct _Gstreamer {
	GstElement *pipeline;
	gboolean initialized;
	GstElement *video_sink;
	GMainContext *context;
	GstBus *bus;
};

extern Gstreamer *gstreamer_data;
extern UIView *ios_ui_video_view;

gpointer  level_1(gpointer data);
gpointer  level_2(gpointer data);
void free_receive_video_data();
