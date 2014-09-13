#include <gst/gst.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include "core.h"
#include "login.h"

#define BUFFERLEN 200
#define MAX_TAG 20
#define MAX_TAG_LENGTH 50

static pthread_t gst_app_thread;
static GMainLoop *loop;

/* 
 * Thread to init ice & gstreamer
 */
void *app_function (void *userdata)
{
	puts("app_function");
	GThread *videoThread;
	GMainContext *context = NULL;
    
	loop = g_main_loop_new(context, FALSE);
	context = g_main_context_new();
	g_main_context_push_thread_default(context);
    
	/* Create gstreamer data */
	gstreamer_data = g_new0(Gstreamer, 1);
    
    puts("Stop here");
    
	if (mLevel == 1) {
		videoThread = g_thread_new("video thread level 1",
                                   level_1,
                                   NULL);
	} else if (mLevel == 2) {
		videoThread = g_thread_new("video thread level 2",
                                   level_2,
                                   NULL);
	}
    
	g_main_loop_run (loop);
    
	/* Free resource */
	//g_thread_join (videoThread);
	//close_server_socket();
    
	g_main_loop_unref (loop);
	g_main_context_pop_thread_default(context);
	g_main_context_unref (context);
    
	/* receive video */
	free_receive_video_data();
    
	return NULL;
}

/*
 * Call before app exit
 */
void close_server_socket ()
{
	shutdown(global_socket, 2);
	global_socket = 0;
}

/*
 * Call before app exits
 */
void out_of_current_session()
{
	puts("out_of_current_session");
	char *sendBuffer;
    
	sendBuffer = (char *)calloc(1000, sizeof(char));
    
	/* Send out of session signal */
	sprintf(sendBuffer, "<DESTROYCONN>"
            "<from>%s</from>"
            "</DESTROYCONN>", username);
    
	send(global_socket, sendBuffer, strlen(sendBuffer), 0);
	printf("send = %s\nn", sendBuffer);
	puts("App exit here.");
}
