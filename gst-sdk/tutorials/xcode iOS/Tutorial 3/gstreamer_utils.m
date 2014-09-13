#include "gstreamer_utils.h"
#include "core.h"

extern Gstreamer *gstreamer_data;

/* Listen for element's state change */
void on_state_changed (GstBus *bus, GstMessage *msg, gpointer userdata)
{
	char *TAG = "[Jni] on_state_changed";
    
	GstState old_state, new_state, pending_state;
	gst_message_parse_state_changed (msg, &old_state,
									 &new_state,
									 &pending_state);
    
    //	GstElement *videosink;
    //	videosink = gst_bin_get_by_name(GST_BIN(data->pipeline), "videosink");
    //
	//if (GST_MESSAGE_SRC (msg) == GST_OBJECT (gstreamer_data->pipeline))
	//{
    gchar *message = g_strdup_printf("%s changed to state %s",
                                     GST_MESSAGE_SRC_NAME(msg),
                                     gst_element_state_get_name(new_state));
    
    printf("[receive video]%s\n", message);
    g_free (message);
	//}
    
	/* Video is ready to play, so display it on surfaceview */
	if (gstreamer_data->pipeline->current_state == GST_STATE_PLAYING)
	{
		puts("Video is ready!");
        
//		JNIEnv *env = (JNIEnv *)get_jni_env ();
//		jclass cls = (*env)->GetObjectClass(env, this_Tutorial3);
//        
//		__android_log_print (ANDROID_LOG_DEBUG, TAG,
//                             "cls = %d", cls);
//        
//		jfieldID video_available_field_id = (*env)->GetFieldID (env, cls,
//                                                                "isVideoAvailable", "Z");
//        
//		__android_log_print (ANDROID_LOG_DEBUG, TAG,
//                             "video_available_field_id = %d",
//                             video_available_field_id);
//        
//		(*env)->SetBooleanField(env, this_Tutorial3,
//                                video_available_field_id, JNI_TRUE);
        
	}
}

void
on_error (GstBus     *bus,
          GstMessage *message,
          gpointer    user_data)
{
    char *TAG = "[Jni] on_error";
    
    GError *err;
    gchar *debug_info;
    gchar *message_string;
    
    gst_message_parse_error (message, &err, &debug_info);
    puts("=========================================\n");
    message_string = g_strdup_printf ("Error received from element %s: %s",
                                      GST_OBJECT_NAME (message->src), err->message);
    printf("debug_info = %s \n\n message_string = %s\n", debug_info, message_string);
    puts("=========================================\n");
    g_clear_error (&err);
    g_free (debug_info);
    g_free (message_string);
}

void on_pad_added (GstElement* object, GstPad* pad, gpointer data)
{
	char *TAG = "[Jni] on_pad_added";
	gchar *pad_name = gst_pad_get_name(pad);
	printf("on_pad_added = %s", pad_name);
	GstPad *sinkpad;
	GstElement *autovideosink = (GstElement *) data;
	sinkpad = gst_element_get_static_pad (autovideosink, "sink");
	gst_pad_link (pad, sinkpad);
	gst_object_unref (sinkpad);
}

void gstAndroidLog(GstDebugCategory * category,
                   GstDebugLevel      level,
                   const gchar      * file,
                   const gchar      * function,
                   gint               line,
                   GObject          * object,
                   GstDebugMessage  * message,
                   gpointer           data)
{
    //if (level <= gst_debug_category_get_threshold (category))
    //{
//    __android_log_print(ANDROID_LOG_DEBUG, "MY_APP", "%s,%s: %s",
//                        file, function, gst_debug_message_get(message));
    //}
}
