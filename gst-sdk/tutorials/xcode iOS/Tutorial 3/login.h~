/*
 * login.h
 *
 *  Created on: Apr 4, 2014
 *      Author: cxphong
 */

#ifndef LOGIN_H_
#define LOGIN_H_

extern int global_socket;
extern char *username;
extern char *password;
extern char *peerIdRpi;
char *androidMasterId;
char *androidClientId;
extern int mLevel;

int connect_with_timeout(char *host, int port, int timeout_sec,
                         int timeout_usec, char *account);

int login_to_server (char *username, char *password);

char* list_available_session();

int join_into_session (char *sessionId);

#endif /* LOGIN_H_ */

