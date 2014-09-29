#include "core.h"
#include "pjnath_initialize.h"
#include "login.h"
#include "gstreamer_utils.h"
#include "gstpjnath.h"
#include "ins_debug.h"

#include <sys/socket.h>
#include <gst/gst.h>
#include <gst/video/video.h>

GstreamerHolder *gstreamer_data;
UIView *ios_ui_video_view;
static gboolean isPipelineReady;

//static PjnathHolder *data_for_rpi;
static RtpSever *rpi_rtp_server;
extern char *peerIdRpi;

/* Not using now */
extern char *androidMasterId;
extern char *androidClientId;
static PjnathHolder *data_for_android_master;	// connect to android level 1
static PjnathHolder *data_for_android_client;	// connect to android level 2

#define WAIT_UNTIL_ANDROID_GSTREAMER_INIT_DONE(sleepTime) \
while(!init_gstreamer_done) usleep(sleepTime)

/******************************************************************************
 *						GENERAL (MASTER && CLIENT)
 ******************************************************************************/

void free_resource()
{
    free(rpi_rtp_server);
    free(peerIdRpi);
}

static void isReadyToPlayPipeline()
{
	isPipelineReady = TRUE;
}

/*
 * New pad for decodebin will get suitable
 * decoder in ios phone
 */
static void cb_newpad(GstElement * decodebin, GstPad * pad, GstElement * autovideosink)
{
	GstCaps *caps;
	GstStructure *str;
	GstPad *videopad;

	/* only link once */
	videopad = gst_element_get_static_pad(autovideosink, "sink");
	g_assert(videopad);

	if (GST_PAD_IS_LINKED(videopad)) {
		g_object_unref(videopad);
		exit(EXIT_FAILURE);
	}

	/* Check media type is video */
	caps = gst_pad_query_caps(pad, NULL);
	str = gst_caps_get_structure(caps, 0);

	if (!g_strrstr(gst_structure_get_name(str), "video")) {
		gst_caps_unref(caps);
		gst_object_unref(videopad);
		exit(EXIT_FAILURE);
	}

	gst_caps_unref(caps);

	/* link'n'play */
	gst_pad_link(pad, videopad);

	g_object_unref(videopad);
}

static void setup_ghost_sink(GstElement * sink, GstBin * bin)
{
	GstPad *sinkPad = gst_element_get_static_pad(sink, "sink");
	GstPad *binPad = gst_ghost_pad_new("sink", sinkPad);
	gst_element_add_pad(GST_ELEMENT(bin), binPad);
}

static void setup_ghost_source(GstElement * source, GstBin * bin)
{
	GstPad *srcPad = gst_element_get_static_pad(source, "src");
	GstPad *binPad = gst_ghost_pad_new("source", srcPad);
	gst_element_add_pad(GST_ELEMENT(bin), binPad);
}

/**
 * make_audio_session:
 *
 * Create audio session then join into rtpBin
 */
static void *make_audio_session(PjnathHolder * audioSessionHolder, GstElement * rtpBin)
{
	g_print("\n make_audio_session\n");

	GstElement *capsfilter;
	GstElement *rtpspeexdepay;
	GstElement *speexdec;
	GstElement *audioconvert;
	GstElement *audioresample;
	GstElement *autoaudiosink;
	GstPad *srcpad;
	GstPad *sinkpad;
	GstPadLinkReturn retv;

	audioSessionHolder->pjnathsrc = gst_element_factory_make("pjnathsrc", NULL);
	capsfilter = gst_element_factory_make("capsfilter", NULL);
	rtpspeexdepay = gst_element_factory_make("rtpspeexdepay", NULL);
	speexdec = gst_element_factory_make("speexdec", NULL);
	audioconvert = gst_element_factory_make("audioconvert", NULL);
	audioresample = gst_element_factory_make("audioresample", NULL);
	autoaudiosink = gst_element_factory_make("autoaudiosink", NULL);

	g_assert(audioSessionHolder->pjnathsrc);
	g_assert(capsfilter);
	g_assert(rtpspeexdepay);
	g_assert(speexdec);
	g_assert(audioconvert);
	g_assert(audioresample);
	g_assert(autoaudiosink);

	g_object_set(audioSessionHolder->pjnathsrc, "icest", audioSessionHolder->icest, NULL);
	g_object_set(audioSessionHolder->pjnathsrc, "address", &audioSessionHolder->rem.def_addr[0], NULL);
	g_object_set(audioSessionHolder->pjnathsrc, "component", 1, NULL);
	g_object_set(audioSessionHolder->pjnathsrc, "do-timestamp", TRUE, NULL);
	g_object_set(audioSessionHolder->pjnathsrc, "blocksize", 4096, NULL);
	g_object_set(capsfilter, "caps",
		     gst_caps_from_string
		     ("application/x-rtp, media=(string)audio, clock-rate=(int)44100,"
		      "encoding-name=(string)SPEEX, encoding-params=(string)1,"
		      "payload=(int)110, ssrc=(uint)1647313534,"
		      "timestamp-offset=(uint)2918479805, seqnum-offset=(uint)26294"), NULL);

	gst_bin_add_many(GST_BIN(gstreamer_data->pipeline),
			 audioSessionHolder->pjnathsrc, capsfilter,
			 rtpspeexdepay, speexdec, audioconvert, audioresample, autoaudiosink, NULL);

	if (gst_element_link_many(audioSessionHolder->pjnathsrc, capsfilter, NULL) != TRUE) {
		g_printerr("1. Elements could not be linked.\n");
		gst_object_unref(gstreamer_data->pipeline);
		exit(EXIT_FAILURE);
	}

	if (gst_element_link_many(rtpspeexdepay, speexdec, audioconvert, audioresample, autoaudiosink, NULL) != TRUE) {
		g_printerr("2. Elements could not be linked.\n");
		gst_object_unref(gstreamer_data->pipeline);
		exit(EXIT_FAILURE);
	}

	/* Link capsfilter->rtpbin_sink */
	sinkpad = gst_element_get_request_pad(rtpBin, "recv_rtp_sink_%u");
	srcpad = gst_element_get_static_pad(capsfilter, "src");

	if (gst_pad_link(srcpad, sinkpad) != GST_PAD_LINK_OK) {
		puts("Failed to link audio capsfilter to rtpbin");
		exit(EXIT_FAILURE);
	}

	gst_object_unref(srcpad);
	gst_object_unref(sinkpad);

	/* Link rtpBin to rtpspeexdepay */
	g_signal_connect(rtpBin, "pad-added", G_CALLBACK(on_pad_added), rtpspeexdepay);

	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_READY);
}

/**
 * make_video_session:
 *
 * Create video session then join into rtpBin
 */
static void *make_video_session(PjnathHolder * videoSessionHolder, GstElement * rtpBin)
{
	g_print("\nmake_video_session\n");

	GstElement *tee;
	GstElement *queue;
	GstElement *capsfilter;
	GstElement *rtph264depay;
	GstElement *decodebin;
	GstElement *videoconvert, *videoscale;
	GstElement *video_view;
	GstPadTemplate *tee_src_pad_template;
	GstPad *tee_q1_pad;
	GstPad *q1_pad;
	GstPad *srcpad;
	GstPad *sinkpad;
	GstPadLinkReturn retv;

	/* Create elements */
	videoSessionHolder->pjnathsrc = gst_element_factory_make("pjnathsrc", "pjnathsrc");
	tee = gst_element_factory_make("tee", "tee");
	queue = gst_element_factory_make("queue", NULL);
	capsfilter = gst_element_factory_make("capsfilter", NULL);
	rtph264depay = gst_element_factory_make("rtph264depay", NULL);
	decodebin = gst_element_factory_make("decodebin", NULL);
	videoconvert = gst_element_factory_make("videoconvert", NULL);
	videoscale = gst_element_factory_make("videoscale", NULL);
	video_view = gst_element_factory_make("autovideosink", NULL);

	/* Set element's properties */
	g_object_set(videoSessionHolder->pjnathsrc, "icest", videoSessionHolder->icest, NULL);
	g_object_set(videoSessionHolder->pjnathsrc, "address", &videoSessionHolder->rem.def_addr[0], NULL);
	g_object_set(videoSessionHolder->pjnathsrc, "component", 1, NULL);
	g_object_set(videoSessionHolder->pjnathsrc, "do-timestamp", TRUE, NULL);
	g_object_set(videoSessionHolder->pjnathsrc, "blocksize", 4096, NULL);
	g_object_set(capsfilter, "caps", gst_caps_from_string
		     ("application/x-rtp, payload=(int)96, "
		      "media=(string)video,clock-rate=(int)90000," "encoding-name=(string)H264"), NULL);
	g_object_set(video_view, "sync", FALSE, NULL);
    /**
     * Set leaky to 2(downstream) to ignore old(don't need anymore) frames
     * to make smooth display.
     */
	g_object_set(queue, "max-size-buffers", 10, NULL);
	g_object_set(queue, "leaky", 0, NULL);

	gst_bin_add_many(GST_BIN(gstreamer_data->pipeline),
			 videoSessionHolder->pjnathsrc, tee, queue, capsfilter, rtph264depay,
			 decodebin, videoscale, videoconvert, video_view, NULL);

	if (!gst_element_link_many(videoSessionHolder->pjnathsrc, tee, NULL) ||
	    !gst_element_link_many(queue, capsfilter, NULL) ||
	    !gst_element_link_many(rtph264depay, decodebin, NULL) ||
	    !gst_element_link_many(videoscale, videoconvert, video_view, NULL)) {
		g_printerr("Elements could not be linked.\n");
		gst_object_unref(gstreamer_data->pipeline);
		exit(EXIT_FAILURE);
	}

	/* Link the tee to the queue 1 */
	if ((tee_src_pad_template =
	     gst_element_class_get_pad_template(GST_ELEMENT_GET_CLASS(tee),
						"src_%u")) == NULL
	    || (tee_q1_pad =
		gst_element_request_pad(tee, tee_src_pad_template, NULL,
					NULL)) == NULL
	    || (q1_pad = gst_element_get_static_pad(queue, "sink")) == NULL) {
		g_printerr("Failed to get pads!");
		exit(EXIT_FAILURE);
	}

	if ((retv = gst_pad_link(tee_q1_pad, q1_pad)) != GST_PAD_LINK_OK) {
		g_critical("tee_q1 = %d, q1_pad = %d", tee_q1_pad, q1_pad);
		g_critical("ret = %d", retv);
		g_critical("Tee for q1 could not be linked.\n");
		gst_object_unref(gstreamer_data->pipeline);
		exit(EXIT_FAILURE);
	}

	gst_object_unref(q1_pad);

	/* Link capsfilter->rtpbin_sink */
	sinkpad = gst_element_get_request_pad(rtpBin, "recv_rtp_sink_%u");
	srcpad = gst_element_get_static_pad(capsfilter, "src");
	if (gst_pad_link(srcpad, sinkpad) != GST_PAD_LINK_OK) {
		g_printerr("Failed to link audio capsfilter to rtpbin");
		exit(EXIT_FAILURE);
	}

	gst_object_unref(srcpad);
	gst_object_unref(sinkpad);

	/* Link rtpBin to rtph264depay */
	g_signal_connect(rtpBin, "pad-added", G_CALLBACK(on_pad_added), rtph264depay);
	/* Link decobin to videoscale */
	g_signal_connect(decodebin, "pad-added", G_CALLBACK(cb_newpad), videoscale);

	/* Link videosink to IOS SurfaceView */
	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_READY);

	gstreamer_data->video_sink =
	    gst_bin_get_by_interface(GST_BIN(gstreamer_data->pipeline), GST_TYPE_VIDEO_OVERLAY);
	g_assert(gstreamer_data->video_sink);

	gst_video_overlay_set_window_handle(GST_VIDEO_OVERLAY
					    (gstreamer_data->video_sink), (guintptr) (id) ios_ui_video_view);
}

/**
 * init_gstreamer:
 *
 * Initialize gstreamer pipeline
 *
 * Returns: void
 */
static void init_gstreamer(RtpSever * rtp_server)
{
	puts("init_gstreamer");

	GstElement *rtpBin;

	setenv("GST_DEBUG", "*:3", 1);

	/* Initialize Gstreamer library 1.0 & pjnath-gstreamer plugin */
	gst_init(NULL, NULL);
	gst_plugin_register_static(GST_VERSION_MAJOR,
				   GST_VERSION_MINOR,
				   PLUGIN_NAME,
				   "Interactive UDP connectivity establishment",
				   plugin_init, "0.1.4", "LGPL", "libpjnath",
                   "http://ispioneer.com", "");
    
	gstreamer_data->pipeline = gst_pipeline_new(NULL);
	rtpBin = gst_element_factory_make("rtpbin", NULL);

	gst_bin_add(GST_BIN(gstreamer_data->pipeline), rtpBin);

#ifdef RECEIVE_VIDEO_SESSION
	make_video_session(&rtp_server->receive_video_session, rtpBin);
#endif

#ifdef RECEIVE_AUDIO_SESSION
	make_audio_session(&rtp_server->receive_audio_session, rtpBin);
#endif

//     puts("debug 10.1");
//      /* Listen to the bus */
//      gstreamer_data->bus = gst_element_get_bus(gstreamer_data->pipeline);
//    g_assert(gstreamer_data->bus);
//      gst_bus_enable_sync_message_emission(gstreamer_data->bus);
//      gst_bus_add_signal_watch(gstreamer_data->bus);
//
//     puts("debug 10.2");
//      g_signal_connect(G_OBJECT(gstreamer_data->bus), "message::error", (GCallback) on_error, NULL);
//      g_signal_connect(G_OBJECT(gstreamer_data->bus),
//                       "message::state-changed", (GCallback) on_state_changed, gstreamer_data);
//     puts("debug 10.3");
}

/* Will be called from main thread - stream.c */
void free_receive_video_data()
{
//      gst_element_set_state(gstreamer_data->pipeline, GST_STATE_NULL);
//      gst_object_unref(gstreamer_data->video_sink);
//      gst_object_unref(gstreamer_data->pipeline);
//      gst_object_unref(gstreamer_data->bus);
}

/**
 * set_pipeline_to_playing_state:
 *
 * When master is android, we set pipeline to PLAYING state directly not
 * send signal start-streaming to master. So we must wait pipeline ready
 */
static void set_pipeline_to_playing_state()
{
	g_print("set_pipeline_to_playing_state");

	GstStateChangeReturn ret;

	ret = gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PLAYING);

	if (ret == GST_STATE_CHANGE_FAILURE) {
		g_printerr("Failed set pipeline to PLAYING");
	}

	g_print("set_pipeline_to_playing_state done");
}

/**
 * start_streaming:
 *
 * Send request to start streaming to mster (source of video).
 */
static void start_streaming(char *masterId)
{
	puts("start_streaming");

	char *recvbuffer;
	char *sendbuffer;
	char *result;

	result = (char *)calloc(1000, sizeof(char));
	recvbuffer = (char *)calloc(1000, sizeof(char));
	sendbuffer = (char *)calloc(1000, sizeof(char));

	sprintf(sendbuffer, "<STARTSTREAMING>" "<from>%s</from>" "<to>%s</to>" "</STARTSTREAMING>", username, masterId);

	send(global_socket, sendbuffer, strlen(sendbuffer), 0);
	printf("Send: %s\n", sendbuffer);

	while (1) {
		if (recv(global_socket, recvbuffer, 1000, 0)) {
			printf("receive: %s\n", recvbuffer);

			/* Correct format? */
			parse_xml_node_content(recvbuffer, "to", result);
			printf("to: %s\n", result);
			if (strcmp(result, username))
				continue;

			memset(result, 0, strlen(result));
			parse_xml_node_content(recvbuffer, "status", result);
			printf("status: %s\n", result);

			if (!strcmp(result, "OK")) {
				set_pipeline_to_playing_state();
				break;
			} else if (!strcmp(result, "FAILED"))
				break;
			else
				continue;
		}
	}
}

/******************************************************************************/
/*						MASTER
 /******************************************************************************/

static void add_pjnathsink_to_pipeline(PjnathHolder * holder)
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

	/* Initialize GStreamer */
	gst_init(NULL, NULL);

	/* Register gstreamer plugin pjnath */
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
	gst_bin_add_many(GST_BIN(gstreamer_data->pipeline), queue, pjnathsink, NULL);
	gst_element_link(queue, pjnathsink);

	if ((tee_src_pad_template =
	     gst_element_class_get_pad_template(GST_ELEMENT_GET_CLASS(tee),
						"src_%u")) == NULL
	    || (tee_q2_pad =
		gst_element_request_pad(tee, tee_src_pad_template, NULL,
					NULL)) == NULL
	    || (q2_pad = gst_element_get_static_pad(queue, "sink")) == NULL) {
		//LOGD(__FILE__, "Failed to get pads!");
	}

	/* Link the tee to the queue 1 */
	if ((retv = gst_pad_link(tee_q2_pad, q2_pad)) != GST_PAD_LINK_OK) {
		//LOGD(__FILE__, "tee_q1 = %d, q1_pad = %d", tee_q2_pad, q2_pad);
		//LOGD(__FILE__, "ret = %d", retv);
		//LOGD(__FILE__, "Tee for q1 could not be linked.\n");
		//gst_object_unref (pipeline);
		return;
	}

	gst_object_unref(q2_pad);

	rc = gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PLAYING);
	if (rc == GST_STATE_CHANGE_FAILURE) {
		//LOGD(__FILE__, "set to playing state failed");
		//LOGD(__FILE__, "rc = %d", rc);
	}
	//LOGD(__FILE__, "add_pjnathsink_to_pipeline done");
}

static void listen_anrdoid_client_connect()
{
	//LOGD(__FILE__, "listen_to_become_master");

	data_for_android_client = g_new0(PjnathHolder, 1);
	establish_stun_with_client(data_for_android_client);
	add_pjnathsink_to_pipeline(data_for_android_client);
}

static void remove_gstreamer_branch_for_androidclient()
{
	//LOGD(__FILE__, "remove_gstreamer_branch_for_androidclient");

	GstElement *queue, *pjnathsink;

	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PAUSED);
	if (!(pjnathsink = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline), "pjnathsink"))) {
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
		if (!strstr(recvBuf, "DESTROYCONN"))
			continue;

		/* Check this message is for me */
		parse_xml_node_content(recvBuf, "to", destination);
		//LOGD(__FILE__, "to: %s", destination);
		if (strcmp(destination, username))
			continue;

		/* Get anroid client id */
		parse_xml_node_content(recvBuf, "from", origin);
		//LOGD(__FILE__, "from: %s", origin);
		if (strcmp(origin, androidClientId))
			continue;
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
	do {
		listen_anrdoid_client_connect();
		listen_android_client_exit();
	} while (mLevel == 1);
}

static void shaking_with_master(RtpSever *rtp_server)
{
	puts("SHAKING_WITH_MASTER");

	char *recBuf;
	char *sendBuf;
	char *destination;
	char *acception;

	recBuf = (char *)calloc(1024, sizeof(char));
	sendBuf = (char *)calloc(1024, sizeof(char));
	destination = (char *)calloc(1024, sizeof(char));
	acception = (char *)calloc(1024, sizeof(char));

	/* Send local ICE */
	sprintf(sendBuf, "<REQUESTCONN>"
		"<from>%s</from>"
		"<to>%s</to>"
		"<message><video>%s</video><audio>%s</audio></message>"
		"</REQUESTCONN>", username, peerIdRpi,
            rtp_server->receive_video_session.local_info,
            rtp_server->receive_audio_session.local_info);

	send(global_socket, sendBuf, strlen(sendBuf), 0);
	printf("\n\n\n\n  username = %s \n", username);
	printf("+++++++++++send: %s\n", sendBuf);

	/* Receive remote ICE */
	while (1) {
		if (recv(global_socket, recBuf, 1024, 0)) {
			printf("+++++++++++receive: %s\n", recBuf);

			/* Destination is me? */
			parse_xml_node_content(recBuf, "to", destination);
			printf("+++++++++++to: %s\n", destination);
			if (strcmp(destination, username))
				continue;

			/* Rpi accept connection? */
			parse_xml_node_content(recBuf, "accept", acception);
			printf("+++++++++++accept: %s\n", acception);
			if (strcmp(acception, "true"))
				continue;

            /* Get client video ice information */
            rtp_server->receive_video_session.remote_info = (char *)calloc(1024, sizeof(char));
            parse_xml_node_content(recBuf, "video", rtp_server->receive_video_session.remote_info);
            printf("\nvideo = %s\n", rtp_server->receive_video_session.remote_info );
        
            /* Get client audio ice infomation */
            rtp_server->receive_audio_session.remote_info = (char *)calloc(1024, sizeof(char));
            parse_xml_node_content(recBuf, "audio", rtp_server->receive_audio_session.remote_info);
            printf("\naudio = %s\n", rtp_server->receive_audio_session.remote_info );
            
            /* Start negotiate */
            start_negotiate(&rtp_server->receive_video_session);
            start_negotiate(&rtp_server->receive_audio_session);
            
			break;
		} else {
			exit(EXIT_SUCCESS);
		}
	}
}

/*
 * Function of android master in level 2
 */
gpointer level_1(gpointer data)
{
	ins_log("level_1");

	pj_status_t rc;
	pj_thread_desc desc;
	pj_thread_t *this_thread;

	rpi_rtp_server = g_new0(RtpSever, 1);
	isPipelineReady = FALSE;

	/* Register pjnath thread */
	if (!pj_thread_is_registered()) {
		rc = pj_thread_register("thread", desc, &this_thread);
		if (rc != PJ_SUCCESS) {
			g_printerr("\nRegister thread failed!\n");
			g_printerr("\nError code = %s\n", strerror(rc - 120000));
		}
	}

	/* Gwt local ICEs */
#ifdef RECEIVE_VIDEO_SESSION
	establish_stun_with_master(&rpi_rtp_server->receive_video_session);
#endif

#ifdef RECEIVE_AUDIO_SESSION
	establish_stun_with_master(&rpi_rtp_server->receive_audio_session);
#endif

#if defined(RECEIVE_VIDEO_SESSION) && defined(RECEIVE_AUDIO_SESSION)
	shaking_with_master(rpi_rtp_server);
#endif

	puts("\n\n\n\n+++++++++++ice rpi init done");

	/* Start play streaming */
	puts("+++++++++++peer Rpi gstreamer");
	init_gstreamer(rpi_rtp_server);

	start_streaming(peerIdRpi);

	puts("done");
	/* Start master listener */
	//master_ownner_listener();
}

/******************************************************************************/
/*						CLIENT
 /******************************************************************************/

static void gstreamer_pipeline_change_to_master_rpi(PjnathHolder * data)
{
	//LOGD (__FILE__, "gstreamer_pipeline_change_to_master_rpi");

	GstElement *pjnathsrc;

	gst_element_set_state(gstreamer_data->pipeline, GST_STATE_PAUSED);

	/* Change pjnathsink element properties */
	if (!(pjnathsrc = gst_bin_get_by_name(GST_BIN(gstreamer_data->pipeline), "pjnathsrc"))) {
		//LOGD (__FILE__, "Couldn't get pjnathsrc");
	}

	g_object_set(pjnathsrc, "icest", data->icest, NULL);
	g_object_set(pjnathsrc, "address", &data->rem.def_addr[0], NULL);
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
////    LOGD(__FILE__, "client_owner_listener");
//      char *recvBuf;
//      char *origin;
//    
//      recvBuf = (char *)calloc(1000, sizeof(char));
//      origin = (char *)calloc(200, sizeof(char));
//    
//      /* Wait master exit? */
//      while(recv(global_socket, recvBuf, 1000, 0)){
////            LOGD(__FILE__, "receive = \"%s\"", recvBuf);
//        
//              /* Check correct format */
//              if(!strstr(recvBuf, "DESTROYCONN")) continue;
//        
//              /* Get anroid master id */
//              parse_xml_node_content(recvBuf, "from", origin);
////            LOGD(__FILE__, "from: %s", origin);
//              if(strcmp(origin, androidMasterId)) continue;
//        
//              break;
//      }
//    
//      /* Delete android master information */
//      memset(androidMasterId,0,strlen(androidMasterId));
//      androidMasterId = NULL;
//    
//      /* Change pipeline to play video from rpi */
//      gstreamer_pipeline_change_to_master_rpi(data_for_rpi);
//    
//      /* Start streaming with rpi */
//      start_streaming(peerIdRpi);
//    
//      /* Now u become master */
//      assert(mLevel == 2);
//      mLevel = 1;
//      master_ownner_listener();
}

/*
 * Function of android client in level 2
 */
gpointer level_2(gpointer data)
{
//      LOGD(__FILE__, "level2");

	pj_status_t rc;
	pj_thread_desc desc;
	pj_thread_t *this_thread;

	/* Register pjnath thread */
//      if (!pj_thread_is_registered()) {
//              LOGD(__FILE__, "\n\n Register thread \n\n");
//        
//              rc = pj_thread_register("thread", desc, &this_thread);
//              if (rc != PJ_SUCCESS) {
//                      LOGE(__FILE__, "\nRegister thread failed!\n");
//                      LOGE(__FILE__, "\nError code = %s\n", strerror(rc-120000));
//              }
//      }

	/* Create data for own pipeline */
	isPipelineReady = FALSE;

	/* ICE to android master */
	data_for_android_master = g_new0(PjnathHolder, 1);
	//establish_stun_with_master(data_for_android_master, androidMasterId);
//      LOGD(__FILE__, "ice anroid peer init done");

	/* Play Gstreamer */
//      LOGD(__FILE__, "peer android gstreamer");
	init_gstreamer(data_for_android_master);
	set_pipeline_to_playing_state();

	/* ICE to Rpi */
	//data_for_rpi = g_new0 (PjnathHolder, 1);
	// establish_stun_with_master (data_for_rpi, peerIdRpi);
//      LOGD(__FILE__, "ice rpi init done");

	/* Listen master status */
	client_owner_listener();
}
