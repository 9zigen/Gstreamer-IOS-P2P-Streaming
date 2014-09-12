#include "stream.h"
#include "login.h"
#include "gstreamer_utils.h"
#include "pjnath_initialize.h"
#include "gstpjnath.h"
#include "receive_video.h"

#include <sys/socket.h>
#include <gst/gst.h>
#include <gst/video/video.h>

Gstreamer *gstreamer_data;
UIView *ios_ui_video_view;

static Holder *data_for_rpi; // connect to rpi
static Holder *data_for_android_master; // connect to android level 1
static Holder *data_for_android_client; // connect to android level 2

extern char *peerIdRpi;
extern char *androidMasterId;
extern char *androidClientId;
static gboolean isPipelineReady;

#define WAIT_UNTIL_ANDROID_GSTREAMER_INIT_DONE(sleepTime) \
while(!init_gstreamer_done) usleep(sleepTime)

/******************************************************************************/
/*						GENERAL (MASTER && CLIENT)
 /******************************************************************************/

/*
 *	Must to check pipeline status to set it to paused status.
 */
static void isReadyToPlayPipeline()
{
//	LOGD(__FILE__,"video_sink = %d, native_window = %d",
//         gstreamer_data->video_sink,
//         gstreamer_data->native_window);
//    
//	if (!gstreamer_data->video_sink ||
//		!gstreamer_data->native_window) return;
//    
//	gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY (gstreamer_data->video_sink),
//                                        (guintptr)gstreamer_data->native_window);
//	GstStateChangeReturn ret = gst_element_set_state(gstreamer_data->pipeline,
//													 GST_STATE_PAUSED);
    
	isPipelineReady = TRUE;
}

/*
 * New pad for decodebin
 */
static void cb_newpad (GstElement *decodebin,
					   GstPad     *pad,
					   GstElement *autovideosink)
{
	GstCaps *caps;
	GstStructure *str;
	GstPad *videopad;
    
	/* only link once */
	videopad = gst_element_get_static_pad (autovideosink, "sink");
	//assert(videopad);
    
	if (GST_PAD_IS_LINKED (videopad)) {
		g_object_unref (videopad);
		return;
	}
    
	/* check media type */
	caps = gst_pad_query_caps (pad, NULL);
	str = gst_caps_get_structure (caps, 0);
	if (!g_strrstr (gst_structure_get_name (str), "video")) {
		gst_caps_unref (caps);
		gst_object_unref (videopad);
		return;
	}
	gst_caps_unref (caps);
    
	/* link'n'play */
	gst_pad_link (pad, videopad);
    
	g_object_unref (videopad);
}

/*
 * Initialize gstreamer pipeline
 * */
static void  video_receive_init_gstreamer(Holder *data)
{
	//WAIT_UNTIL_ANDROID_GSTREAMER_INIT_DONE(1000);
	puts("video_receive_init_gstreamer");
    
    GstElement *videotestsrc;
	GstElement *pjnathsrc;
	GstElement *tee;
	GstElement *queue;
	GstElement *capsfilter;
	GstElement *rtph264depay;
	GstElement *h264parse;
	GstElement *decodebin;
	GstElement *video_view;
	GstElement *rtpjitterbuffer;
	GstMessage *msg;
	GstStateChangeReturn ret;
	GSource *bus_source;
	GstPadTemplate *tee_src_pad_template;
	GstPad *tee_q1_pad;
	GstPad *q1_pad;
	GstPadLinkReturn retv;
    
	/* Init gstreamer library & pjnath-gstreamer plugin */
  	gst_init(NULL, NULL);
	gst_plugin_register_static(GST_VERSION_MAJOR,
							   GST_VERSION_MINOR,
							   PLUGIN_NAME,
							   "Interactive UDP connectivity establishment",
							   plugin_init, "0.1.4", "LGPL", "libpjnath",
							   "http://telepathy.freedesktop.org/wiki/", "");
    
	/* Create elements */
    videotestsrc = gst_element_factory_make("videotestsrc", "videotestsrc");
	pjnathsrc = gst_element_factory_make("pjnathsrc", "pjnathsrc");
	tee = gst_element_factory_make("tee", "tee");
	queue = gst_element_factory_make("queue", NULL);
	capsfilter = gst_element_factory_make("capsfilter", NULL);
	rtpjitterbuffer = gst_element_factory_make("rtpjitterbuffer", NULL);
	rtph264depay = gst_element_factory_make("rtph264depay", NULL);
	h264parse = gst_element_factory_make("h264parse", NULL);
	decodebin = gst_element_factory_make("decodebin", NULL);
	video_view = gst_element_factory_make("autovideosink", NULL);
	gstreamer_data->pipeline = gst_pipeline_new("Receive Video Pipeline");
    
	/* Set element's properties */
	g_object_set(pjnathsrc, "icest", data->icest, NULL);
	g_object_set(pjnathsrc, "address",
                 &data->rem.def_addr[0], NULL);
	g_object_set(pjnathsrc, "component", 1, NULL);
	g_object_set(pjnathsrc, "do-timestamp", TRUE, NULL);
	g_object_set(pjnathsrc, "blocksize", 4096, NULL);
    
	g_object_set(capsfilter, "caps", gst_caps_from_string
                 ("application/x-rtp, payload=(int)96"), NULL);
	g_object_set(video_view, "sync", FALSE, NULL);
    
	//g_object_set(rtpjitterbuffer, "drop-on-latency", TRUE, NULL);
	//g_object_set(rtpjitterbuffer, "latency", 20000, NULL);
	//g_object_set(rtpjitterbuffer, "percent", 100, NULL);
	g_object_set(rtpjitterbuffer, "mode", 0, NULL);
    
	/* Queue
	 * Set leaky to 2(downstream) to ignore old(don't need anymore) frames
	 * to make smooth display.
	 * */
	g_object_set(queue, "max-size-buffers", 10, NULL);
	g_object_set(queue, "leaky", 2, NULL);
    
//	assert(gstreamer_data->pipeline);
//	assert(pjnathsrc);
//	assert(tee);
//	assert(queue);
//	assert(capsfilter);
//	assert(rtpjitterbuffer);
//	assert(rtph264depay);
//	assert(video_view);
//	assert(decodebin);
//	assert(h264parse);

    if (!gstreamer_data->pipeline) {
        puts("gstreamer_data->pipeline = null");
        exit(EXIT_FAILURE);
    }
    if (!pjnathsrc) {
        puts("pjnathsrc= null");
        exit(EXIT_FAILURE);
    }
    if (!tee) {
        puts("tee = null");
        exit(EXIT_FAILURE);
    }
    if (!queue) {
        puts("queue = null");
        exit(EXIT_FAILURE);
    }
    if (!capsfilter) {
        puts("capsfilter = null");
        exit(EXIT_FAILURE);
    }
    if (!rtpjitterbuffer) {
        puts("rtpjitterbuffer = null");
        exit(EXIT_FAILURE);
    }
    if (!rtph264depay) {
        puts("rtph264depay = null");
        exit(EXIT_FAILURE);
    }
    if (!video_view) {
        puts("video_view = null");
        exit(EXIT_FAILURE);
    }
    if (!decodebin) {
        puts("decodebin = null");
        exit(EXIT_FAILURE);
    }
    
    
    gst_bin_add_many(GST_BIN (gstreamer_data->pipeline),
					 pjnathsrc, tee, queue, capsfilter, rtpjitterbuffer,
					 rtph264depay, decodebin, video_view, NULL);

    //gst_bin_add_many(GST_BIN(gstreamer_data->pipeline), videotestsrc, video_view, NULL);
	g_signal_connect (decodebin, "pad-added", G_CALLBACK (cb_newpad), video_view);
    
	if (!gst_element_link_many(pjnathsrc, tee, NULL)||
		!gst_element_link_many(queue, capsfilter, rtpjitterbuffer,
						       rtph264depay,
							   decodebin, NULL)){
            puts("Elements could not be linked.\n");
            gst_object_unref(gstreamer_data->pipeline);
            return;
        }

    //gst_element_link_many(videotestsrc, video_view, NULL);
    puts("debug 01");
    
	/* Link the tee to the queue 1 */
	if((tee_src_pad_template = gst_element_class_get_pad_template (GST_ELEMENT_GET_CLASS (tee), "src_%u")) == NULL ||
       (tee_q1_pad = gst_element_request_pad (tee, tee_src_pad_template, NULL, NULL)) == NULL ||
       (q1_pad = gst_element_get_static_pad (queue, "sink")) == NULL){
		g_critical("Failed to get pads!");
	}
    
	if((retv = gst_pad_link (tee_q1_pad, q1_pad)) != GST_PAD_LINK_OK ){
		g_critical("tee_q1 = %d, q1_pad = %d", tee_q1_pad, q1_pad);
		g_critical("ret = %d", retv);
		g_critical("Tee for q1 could not be linked.\n");
		gst_object_unref(gstreamer_data->pipeline);
		return;
	}
    
	gst_object_unref(q1_pad);
    
	gst_element_set_state(gstreamer_data->pipeline , GST_STATE_READY);
	gstreamer_data->video_sink = gst_bin_get_by_interface(gstreamer_data->pipeline, GST_TYPE_VIDEO_OVERLAY);
    if (!gstreamer_data->video_sink) {
        GST_ERROR ("Could not retrieve video sink");
        return;
    }
    
    gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(gstreamer_data->video_sink),
                                        (guintptr) (id) ios_ui_video_view);
    
	//assert(gstreamer_data->video_sink);
    
    //	/* Debug setting */
    //	gst_debug_set_default_threshold(GST_LEVEL_DEBUG);
    //	gst_debug_add_log_function(gstAndroidLog, NULL);
    //	gst_debug_set_active (true);
    
	/* Listen to the bus */
//	gstreamer_data->bus = gst_element_get_bus(gstreamer_data->pipeline);
//	gst_bus_enable_sync_message_emission(gstreamer_data->bus);
//	gst_bus_add_signal_watch(gstreamer_data->bus);
//    
//	g_signal_connect(G_OBJECT(gstreamer_data->bus),
//                     "message::error",
//                     (GCallback)on_error, NULL);
//	g_signal_connect(G_OBJECT(gstreamer_data->bus),
//                     "message::state-changed",
//                     (GCallback)on_state_changed, gstreamer_data);
    
	isReadyToPlayPipeline();
    puts("gstreamer done");
}

/*
 * Auto called when SurfaceView(Android) is created.
 * */
//void init_video_surface(JNIEnv *env, jobject surface)
//{
//	LOGD(__FILE__, "init_video_surface");
//    
//	assert(gstreamer_data);
//	ANativeWindow *new_native_window = (ANativeWindow *)ANativeWindow_fromSurface(env, surface);
//	assert(new_native_window);
//    
//	if(gstreamer_data->native_window){
//		ANativeWindow_release(gstreamer_data->native_window);
//		if(gstreamer_data->native_window == new_native_window){
//			if (gstreamer_data->video_sink){
//				gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(gstreamer_data->video_sink),
//													(guintptr)NULL);
//				gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY(gstreamer_data->video_sink),
//													(guintptr)NULL);
//			}
//			return;
//		}
//		else{
//			gstreamer_data->initialized = FALSE;
//		}
//	}
//    
//	gstreamer_data->native_window = new_native_window;
//	isReadyToPlayPipeline();
//}

/*
 * Auto called when SurfaceView(Android) is destroyed.
 * */
//void free_video_surface()
//{
//	LOGD(__FILE__, "free_video_surface");
//    
//	if (!gstreamer_data) return;
//    
//	if (gstreamer_data->video_sink) {
//		gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY (gstreamer_data->video_sink),
//                                            (guintptr) NULL);
//		gst_element_set_state(gstreamer_data->pipeline,
//                              GST_STATE_READY);
//	}
//
//	if (!gstreamer_data->native_window) return;
//    
//	ANativeWindow_release(gstreamer_data->native_window);
//	gstreamer_data->native_window = NULL;
//	gstreamer_data->initialized = FALSE;
//}

/* Will be called from main thread - stream.c */
void free_receive_video_data ()
{
	//LOGD(__FILE__, "free_gstreamer_data");
    
//	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_NULL);
//	gst_object_unref(gstreamer_data->video_sink);
//	gst_object_unref(gstreamer_data->pipeline);
//	gst_object_unref(gstreamer_data->bus);
}

static set_pipeline_to_playing_state()
{
    puts("set_pipeline_to_playing_state");
    
	/*
	 * When master is android, we set pipeline to PLAYING state directly not
	 * send signal start-streaming to master. So we must wait pipeline ready
	 * */
	GstStateChangeReturn ret;
    
	while(!isPipelineReady) usleep(1000);
	
    ret = gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PLAYING);
    if (ret == GST_STATE_CHANGE_FAILURE) {
        puts("Set pipeline to PLAYING");
        exit(EXIT_FAILURE);
    }
    
    puts("set_pipeline_to_playing_state done");
}

/*
 * Send request to start streaming to mster (source of video).
 * */
static void start_streaming(char *masterId)
{
	puts("start_streaming");
    
	char *recvbuffer;
	char *sendbuffer;
	char *result;
    
	result = (char *)calloc(1000, sizeof(char));
	recvbuffer = (char *)calloc(1000, sizeof(char));
	sendbuffer = (char *)calloc(1000, sizeof(char));
    
	sprintf(sendbuffer, "<STARTSTREAMING>"
            "<from>%s</from>"
            "<to>%s</to>"
            "</STARTSTREAMING>",
            username, masterId);
    
	send(global_socket, sendbuffer, strlen(sendbuffer), 0);
	printf("Send: %s\n", sendbuffer);
    
	while (1) {
		if (recv(global_socket, recvbuffer, 1000, 0)) {
			printf("receive: %s\n", recvbuffer);
            
			/* Correct format? */
			parse_xml_node_content(recvbuffer, "to", result);
			printf("to: %s\n", result);
			if (strcmp(result, username)) continue;
            
			memset(result, 0, strlen(result));
			parse_xml_node_content(recvbuffer, "status", result);
			printf("status: %s\n", result);
            
			if (!strcmp(result, "OK")) {
				set_pipeline_to_playing_state();
				break;
			}
			else if (!strcmp(result, "FAILED")) break;
			else continue;
		}
	}
}


/******************************************************************************/
/*						MASTER
 /******************************************************************************/

static void add_pjnathsink_to_pipeline(Holder *holder)
{
	//LOGD(__FILE__, "add_pjnathsink_to_pipeline");
    
	GstElement *tee;
	GstElement *queue;
	GstElement *pjnathsink;
	GstPadTemplate *tee_src_pad_template;
	GstPad *tee_q2_pad;
	GstPad *q2_pad;
	GstStateChangeReturn rc;
	GstPadLinkReturn retv;
    
	// Initialize GStreamer
	gst_init(NULL, NULL);
    
	// Register gstreamer plugin pjnath
	gst_plugin_register_static(GST_VERSION_MAJOR,
							   GST_VERSION_MINOR,
							   PLUGIN_NAME,
							   "Interactive UDP connectivity establishment",
							   plugin_init, "0.1.4", "LGPL", "libpjnath",
							   "http://telepathy.freedesktop.org/wiki/", "");
    
	/* Create elements */
	pjnathsink = gst_element_factory_make("pjnathsink", "pjnathsink");
	queue = gst_element_factory_make("queue", "queue2");
	if (!(tee = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline), "tee"))) {
		//LOGD(__FILE__, "Couldn't get tee");
	}
    
	g_object_set(pjnathsink, "icest", holder->icest, NULL);
	g_object_set(pjnathsink, "address", &holder->rem.def_addr[0], NULL);
	g_object_set(pjnathsink, "component", 1, NULL);
	g_object_set(pjnathsink, "pool", holder->pool, NULL);
    
	/* Queue
	 * Set leaky to 2(downstream) to ignore old-don't need frames
	 * to make smooth display
	 * */
	g_object_set(queue, "max-size-buffers", 10, NULL);
	g_object_set(queue, "leaky", 2, NULL);
    
	/*
	 * Add pjnathsink element into
	 * Receive Video Pipeline
	 * */
	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PAUSED);
	gst_bin_add_many( GST_BIN(gstreamer_data->pipeline), queue, pjnathsink, NULL);
	gst_element_link(queue, pjnathsink);
    
	if ((tee_src_pad_template = gst_element_class_get_pad_template (GST_ELEMENT_GET_CLASS (tee), "src_%u")) == NULL ||
        (tee_q2_pad = gst_element_request_pad (tee, tee_src_pad_template, NULL, NULL)) == NULL ||
        (q2_pad = gst_element_get_static_pad (queue, "sink")) == NULL) {
		//LOGD(__FILE__, "Failed to get pads!");
	}
    
	/* Link the tee to the queue 1 */
	if ((retv = gst_pad_link (tee_q2_pad, q2_pad)) != GST_PAD_LINK_OK)
	{
		//LOGD(__FILE__, "tee_q1 = %d, q1_pad = %d", tee_q2_pad, q2_pad);
		//LOGD(__FILE__, "ret = %d", retv);
		//LOGD(__FILE__, "Tee for q1 could not be linked.\n");
		//gst_object_unref (pipeline);
		return;
	}
    
	gst_object_unref (q2_pad);
    
	rc = gst_element_set_state( gstreamer_data->pipeline, GST_STATE_PLAYING);
	if (rc == GST_STATE_CHANGE_FAILURE) {
		//LOGD(__FILE__, "set to playing state failed");
		//LOGD(__FILE__, "rc = %d", rc);
	}
    
	//LOGD(__FILE__, "add_pjnathsink_to_pipeline done");
}

static void listen_anrdoid_client_connect()
{
	//LOGD(__FILE__, "listen_to_become_master");
    
	data_for_android_client = g_new0(Holder, 1);
	establish_stun_with_client(data_for_android_client);
	add_pjnathsink_to_pipeline(data_for_android_client);
}

static void remove_gstreamer_branch_for_androidclient()
{
	//LOGD(__FILE__, "remove_gstreamer_branch_for_androidclient");
    
	GstElement *queue, *pjnathsink;
    
	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PAUSED);
	if ( !(pjnathsink = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline), "pjnathsink"))) {
		//LOGD(__FILE__, "Couldn't get pjnathsink");
	}
    
	if (!(queue = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline), "queue2"))) {
		//LOGD(__FILE__, "Couldn't get queue");
	}
    
	gst_bin_remove_many(GST_BIN(gstreamer_data->pipeline), pjnathsink, queue, NULL);
	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PLAYING);
}

static void listen_android_client_exit()
{
	//LOGD(__FILE__, "listen_android_client_exit");
    
	char *recvBuf;
	char *destination;
	char *origin;
    
	recvBuf = (char *)calloc(1000, sizeof(char));
	destination = (char *)calloc(200, sizeof(char));
	origin = (char *)calloc(200, sizeof(char));
    
	/* Listen */
	while (recv(global_socket, recvBuf, 1000, 0)) {
		//LOGD(__FILE__, "receive = \"%s\"", recvBuf);
        
		/* Check correct format */
		if (!strstr(recvBuf, "DESTROYCONN")) continue;
        
		/* Check this message is for me */
		parse_xml_node_content(recvBuf, "to", destination);
		//LOGD(__FILE__, "to: %s", destination);
		if (strcmp(destination, username)) continue;
        
		/* Get anroid client id */
		parse_xml_node_content(recvBuf, "from", origin);
		//LOGD(__FILE__, "from: %s", origin);
		if (strcmp(origin, androidClientId)) continue;
		break;
	}
    
	/* Remove pjnathsink in pipeline */
	remove_gstreamer_branch_for_androidclient();
}

/*
 *	This function is master own
 *	This will listen android client in level 2
 *	connect and disconnect.
 * */
void master_ownner_listener()
{
	/* Listen android client status */
	do{
		listen_anrdoid_client_connect();
		listen_android_client_exit();
	}while(mLevel == 1);
}

/*
 * Function of android master in level 2
 */
gpointer  video_receive_level_1(gpointer data)
{
	puts("+++++++++++video_receive_level_1");
	pj_status_t  rc;
	pj_thread_desc desc;
	pj_thread_t *this_thread;
    
	/* Register pjnath thread */
//	if (!pj_thread_is_registered()) {
//		puts("\n\n Register thread \n\n");
//		rc = pj_thread_register("thread", desc, &this_thread);
//		if(rc != PJ_SUCCESS) {
//			puts("\nRegister thread failed!\n");
//			printf("\nError code = %s\n", strerror(rc-120000));
//		}
//	}
    
	/*
     * Check gstreamer & surface init done
     * to change pipeline to PLAYING state
     */
	isPipelineReady = FALSE;
    
	/* ICE to Rpi */
	data_for_rpi = g_new0 (Holder, 1);
	establish_stun_with_master(data_for_rpi, peerIdRpi);
	puts("\n\n\n\n+++++++++++ice rpi init done");
    
	/* Start play streaming */
	puts("+++++++++++peer Rpi gstreamer");
	video_receive_init_gstreamer(data_for_rpi);
	
    start_streaming(peerIdRpi);
    
    puts("done");
	/* Start master listener */
	//master_ownner_listener();
}

/******************************************************************************/
/*						CLIENT
 /******************************************************************************/

static void gstreamer_pipeline_change_to_master_rpi(Holder *data)
{
	LOGD(__FILE__, "gstreamer_pipeline_change_to_master_rpi");
    
	GstElement *pjnathsrc;
    
	gst_element_set_state(gstreamer_data->pipeline , GST_STATE_PAUSED);
    
	/* Change pjnathsink element properties */
	if(!(pjnathsrc = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline),
										 "pjnathsrc"))){
		LOGD(__FILE__, "Couldn't get pjnathsrc");
	}
    
	g_object_set(pjnathsrc, "icest", data->icest, NULL);
	g_object_set(pjnathsrc, "address",
				 &data->rem.def_addr[0], NULL);
	g_object_set(pjnathsrc, "component", 1, NULL);
	g_object_set(pjnathsrc, "do-timestamp", TRUE, NULL);
	g_object_set(pjnathsrc, "blocksize", 4096, NULL);
}

/*
 * If android is client(level 2), then listen android master(level 1)
 * status. If master exit, then start streaming with rpi
 * */
static void client_owner_listener()
{
////	LOGD(__FILE__, "client_owner_listener");
//	char *recvBuf;
//	char *origin;
//    
//	recvBuf = (char *)calloc(1000, sizeof(char));
//	origin = (char *)calloc(200, sizeof(char));
//    
//	/* Wait master exit? */
//	while(recv(global_socket, recvBuf, 1000, 0)){
////		LOGD(__FILE__, "receive = \"%s\"", recvBuf);
//        
//		/* Check correct format */
//		if(!strstr(recvBuf, "DESTROYCONN")) continue;
//        
//		/* Get anroid master id */
//		parse_xml_node_content(recvBuf, "from", origin);
////		LOGD(__FILE__, "from: %s", origin);
//		if(strcmp(origin, androidMasterId)) continue;
//        
//		break;
//	}
//    
//	/* Delete android master information */
//	memset(androidMasterId,0,strlen(androidMasterId));
//	androidMasterId = NULL;
//    
//	/* Change pipeline to play video from rpi */
//	gstreamer_pipeline_change_to_master_rpi(data_for_rpi);
//    
//	/* Start streaming with rpi */
//	start_streaming(peerIdRpi);
//    
//	/* Now u become master */
//	assert(mLevel == 2);
//	mLevel = 1;
//	master_ownner_listener();
}

/*
 * Function of android client in level 2
 */
gpointer  video_receive_level_2(gpointer data)
{
//	LOGD(__FILE__, "video_receive_level2");
    
	pj_status_t  rc;
	pj_thread_desc desc;
	pj_thread_t *this_thread;
    
	/* Register pjnath thread */
//	if (!pj_thread_is_registered()) {
//		LOGD(__FILE__, "\n\n Register thread \n\n");
//        
//		rc = pj_thread_register("thread", desc, &this_thread);
//		if (rc != PJ_SUCCESS) {
//			LOGE(__FILE__, "\nRegister thread failed!\n");
//			LOGE(__FILE__, "\nError code = %s\n", strerror(rc-120000));
//		}
//	}
    
	/* Create data for own pipeline */
	isPipelineReady = FALSE;
    
	/* ICE to android master */
	data_for_android_master = g_new0(Holder, 1);
	establish_stun_with_master(data_for_android_master, androidMasterId);
//	LOGD(__FILE__, "ice anroid peer init done");
    
	/* Play Gstreamer */
//	LOGD(__FILE__, "peer android gstreamer");
	video_receive_init_gstreamer(data_for_android_master);
	set_pipeline_to_playing_state();
    
	/* ICE to Rpi */
	data_for_rpi = g_new0 (Holder, 1);
	establish_stun_with_master(data_for_rpi, peerIdRpi);
//	LOGD(__FILE__, "ice rpi init done");
    
	/* Listen master status */
	client_owner_listener();
}
