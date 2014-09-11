#include <UIKit/UIView.h>
#include <gst/gst.h>
extern UIView *ios_ui_video_view;
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
gpointer  video_receive_level_1(gpointer data);
gpointer  video_receive_level_2(gpointer data);
void free_receive_video_data();
