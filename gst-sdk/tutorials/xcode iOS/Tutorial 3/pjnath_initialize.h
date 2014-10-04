#include "core.h"

/**
 * start_negotiate()
 *
 * Start ICE negotiation
 */
void start_negotiate(PjnathHolder *holder);

/**
 * establish_stun_with_master():
 *
 * Get local ICE information
 * @holder: pjnath holder for local ICE information
 */
void establish_stun_with_master (PjnathHolder * holder);
void establish_stun_with_client (PjnathHolder * data);
