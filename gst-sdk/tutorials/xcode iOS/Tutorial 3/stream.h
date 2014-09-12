#ifndef stream_h
#define stream_h

#include <gst/gst.h>
#include <pjlib.h>
#include <pjlib-util.h>
#include <pjnath.h>
//#include <UIKit/UIView.h>

/* Java class Tutorial3 reference */
extern int isRpiReady;
extern gboolean init_gstreamer_done; // 1: done, 0: not
//extern UIView *ios_ui_video_view;

/*
 * ICE data holder
 */
typedef struct _Holder Holder;

struct _Holder
{
    /* Command line options are stored here */
    struct options
    {
        unsigned    comp_cnt;
        pj_str_t    ns;
        int	        max_host;
        pj_bool_t   regular;
        pj_str_t    stun_srv;
        pj_str_t    turn_srv;
        pj_bool_t   turn_tcp;
        pj_str_t    turn_username;
        pj_str_t    turn_password;
        pj_bool_t   turn_fingerprint;
        const char *log_file;
    } opt;
    
    /* Our global variables */
    pj_caching_pool	 cp;
    pj_pool_t		*pool;
    pj_thread_t		*thread;
    pj_bool_t		 thread_quit_flag;
    pj_ice_strans_cfg	 ice_cfg;
    pj_ice_strans	*icest;
    FILE		*log_fhnd;
    char *local_info;
    char *remote_info;
    int ice_complete;
    
    /* Variables to store parsed remote ICE info */
    struct rem_info
    {
        char		 ufrag[80];
        char		 pwd[80];
        unsigned	 comp_cnt;
        pj_sockaddr	 def_addr[PJ_ICE_MAX_COMP];
        unsigned	 cand_cnt;
        pj_ice_sess_cand cand[PJ_ICE_ST_MAX_CAND];
    } rem;
    
};

void close_server_socket ();
void out_of_current_session();

#endif
