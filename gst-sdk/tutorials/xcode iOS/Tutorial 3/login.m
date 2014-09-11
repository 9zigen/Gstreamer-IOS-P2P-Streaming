#include "xmlparser.h"
#include "login.h"
#include "user_information.h"
#include <sys/socket.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <sys/time.h>
#include <libxml/parser.h>

#define MAX_TAG 20
#define MAX_TAG_LENGTH 50
#define BUFFER_SEND_LEN 200
#define BUFFER_RECV_LEN 1024

#define SERVER "112.213.86.238"
//#define SERVER "10.10.10.121"
#define SERVER_PORT 5555

/* Connect to server return value */
#define WRONG_USERNAME_OR_PASSWORD 0x0
#define SERVER_UNREACHABLE 0x1
#define SUCCESS_LOGIN 0x2
#define XML_NO_ERROR "0"

int global_socket;
char *username;
char *password;
char *peerIdRpi;
char *androidMasterId;
char *androidClientId;
int mLevel;

int getLineAtIndex(const char *source, char *line, int index)
{
#define MAX_LINES 100
#define MAX_LENGTH_SOURCE 1000
    
	char *array[MAX_LINES];
	char *token;
	char copySource[MAX_LENGTH_SOURCE];
	int numLine = 0;
    
	/* Parse @string into single lines */
	if (!source) {
		return 1;
	}
    
	memset(copySource, 0, sizeof(copySource));
	strncpy(copySource, source, strlen(source));
	token = strtok(copySource, ",");
	while(token) {
//		__android_log_print (ANDROID_LOG_DEBUG,
//                             __FILE__, "\n\"%s\"\n", token);
		array[numLine++] = token;
		token = strtok(NULL, ",");
	}
    
	/* Set @line is equal line at @index*/
	if (index > numLine || index < 0) {
		return 1;
	}
	else {
		strncpy(line, array[index - 1], strlen(array[index - 1]));
//		__android_log_print (ANDROID_LOG_DEBUG,
//                             __FILE__, "\n%s\n", line);
		return 0;
	}
}

int connect_with_timeout(char *host,
						 int port,
						 int timeout_sec,
						 int timeout_usec,
						 char *account)
{
	int res;
	int valopt;
	struct sockaddr_in addr;
	long arg;
	fd_set myset;
	struct timeval tv;
	socklen_t lon;
	char *buffer;
	char *result;
	int retValue;
	char *tmp;
    
	lon = sizeof(int);
	buffer = (char *)calloc(BUFFER_SEND_LEN, sizeof(char));
	result = (char *)calloc(BUFFER_RECV_LEN, sizeof(char));
	tmp = (char *)calloc(BUFFER_RECV_LEN, sizeof(char));
    
	// Create socket
	global_socket = socket(AF_INET, SOCK_STREAM, 0);
    
	// Set non-blocking
	arg = fcntl(global_socket, F_GETFL, NULL);
	arg |= O_NONBLOCK;
	fcntl(global_socket, F_SETFL, arg);
    
	// Trying to connect with timeout
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = inet_addr(host);
	res = connect(global_socket, (struct sockaddr *)&addr, sizeof(addr));
    
	/* Set socket's timeout */
	if (res < 0)
	{
		if (errno != EINPROGRESS)
			return SERVER_UNREACHABLE;
        
		tv.tv_sec = timeout_sec;
		tv.tv_usec = timeout_usec;
		FD_ZERO(&myset);
		FD_SET(global_socket, &myset);
        
		if (!select(global_socket+1, NULL, &myset, NULL, &tv) > 0)
			return SERVER_UNREACHABLE;
        
		getsockopt(global_socket, SOL_SOCKET, SO_ERROR, (void*)(&valopt), &lon);
		if (valopt)
			return SERVER_UNREACHABLE;
	}
    
	/* Set socket to blocking mode again */
	arg = fcntl(global_socket, F_GETFL, NULL);
	arg &= (~O_NONBLOCK);
	fcntl(global_socket, F_SETFL, arg);
    
	/* Talking to server */
	send(global_socket,account, strlen(account), 0);
	recv(global_socket, buffer, BUFFER_RECV_LEN, 0);
//	__android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "buffer = \"%s\"",
//                         buffer);
    
	/* Check error code */
    xmlInitParser(); // init only once
	parse_xml_node_content(buffer, "errorCode", result);
//	__android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "error code = \"%s\"",
//                         result);
	/* 0 is successfully */
	if (!strcmp(result, XML_NO_ERROR))
	{
		retValue = SUCCESS_LOGIN;
	}
	else
	{
		retValue = WRONG_USERNAME_OR_PASSWORD;
		/* Close socket */
		shutdown(global_socket, 2);
	}
    
	free(buffer);
	free(result);
    
	return retValue;
}

int login_to_server (char *username, char *password)
{
	char *infoBuf;
	int retValue;
	int timeout_second;
	int timeout_microsecond;
    
	infoBuf = (char *) calloc (BUFFER_SEND_LEN, sizeof(char));
	timeout_second = 5;
	timeout_microsecond = 0;
    
	/* Connect to server */
	sprintf(infoBuf, "<LOGIN>"
            "<devType>APP</devType>"
            "<ID>%s</ID>"
            "<password>%s</password>"
            "</LOGIN>",
            username, password);
    
	retValue = connect_with_timeout(SERVER,
									SERVER_PORT,
									timeout_second,
									timeout_microsecond,
									infoBuf);
	free(infoBuf);
	return retValue;
}

/**
 * List status (online/offline) of all clients
 */
char* list_available_session()
{
    
	char *sender;
	char *receiveBuffer;
	char *session_result;
	char **result;
    
	sender = (char *)calloc (BUFFER_SEND_LEN, sizeof(char));
	receiveBuffer = (char *)calloc (BUFFER_RECV_LEN, sizeof(char));
	session_result = (char *)calloc(BUFFER_RECV_LEN, sizeof(char));
	result = (char **)calloc(1, sizeof(char *));
    
	/* Send request to server */
	sprintf(sender, "<LISTONLINESESSIONS>"
            "</LISTONLINESESSIONS>");
	send(global_socket, sender, strlen(sender), 0);
	recv(global_socket, receiveBuffer, BUFFER_RECV_LEN, 0);
//	__android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "session receive = %s",
//                         receiveBuffer);
    
	/* Check response message from server */
	result = parseDoc(receiveBuffer, "serverRespond", "errorCode");
//    __android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "result = %s",
//                         result[0]);
    if (strcmp(result[0], XML_NO_ERROR))
        return NULL;
    
    /* Get available sessions information */
    session_result = parse_session_attribute(receiveBuffer);
//    __android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "session = %s",
//                         session_result);
    
    free(sender);
    free(receiveBuffer);
    free(result);
    
    return session_result;
}

int join_into_session (char *sessionId)
{
	char *sendBuf;
	char **result;
	char *recvBuf;
	char *peers;
    
	peerIdRpi = (char *)calloc(100, sizeof(char));
	androidMasterId = (char *)calloc(100, sizeof(char));
	peers = (char *)calloc(BUFFER_SEND_LEN, sizeof(char));
	sendBuf = (char *)calloc(BUFFER_SEND_LEN, sizeof(char));
	result = (char **)calloc(1, sizeof(char *));
	recvBuf = (char *)calloc(BUFFER_RECV_LEN, sizeof(char));
    
	sprintf(sendBuf, "<JOINSESSION>"
            "<sessionID>%s</sessionID>"
            "</JOINSESSION>",
            sessionId);
	send(global_socket, sendBuf, strlen(sendBuf), 0);
	recv(global_socket, recvBuf, BUFFER_RECV_LEN, 0);
//	__android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "recvBuf = %s",
//                         recvBuf);
    
	/* Check error code */
	result = parseDoc(recvBuf, "serverRespond", "errorCode");
//	__android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "result = %s",
//                         result[0]);
    if (strcmp(result[0], XML_NO_ERROR))
        return NULL;
    
    /* Get Peers list */
    peers = parse_peer_attribute(recvBuf);
    
    int s;
    for (s = 0; s < strlen(peers); s ++) {
//        __android_log_print (ANDROID_LOG_INFO,
//                             __FILE__,
//                             "%c",
//                             peers[s]);
    }
    
    /* Get peers */
    getLineAtIndex(peers, peerIdRpi, 1);
//    __android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "peerIdRpi = %s",
//                         peerIdRpi);
    
    if (getLineAtIndex(peers, androidMasterId, 2)) {
        androidMasterId = NULL;
        mLevel = 1;
    }
    else {
        mLevel = 2;
    }
    
//    __android_log_print (ANDROID_LOG_INFO,
//                         __FILE__,
//                         "peerIdAndroid = \"%s\"",
//                         androidMasterId);
    
    return peers;
}
