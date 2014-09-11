#include "gstpjnathsrc.h"
#include "gstpjnathsink.h"

#define PACKAGE "PJNATH GSTREAMER"
#define PACKAGE_NAME "PJNATH GSTREAMER"

gboolean plugin_init (GstPlugin *plugin)
{
    
    if (!gst_element_register (plugin, "pjnathsink",
                               GST_RANK_NONE, GST_TYPE_PJNATH_SINK))
        return FALSE;
    
    if (!gst_element_register (plugin, "pjnathsrc",
                               GST_RANK_NONE, GST_TYPE_PJNATH_SRC))
        return FALSE;
    
    return TRUE;
}

/*GST_PLUGIN_DEFINE (
 GST_VERSION_MAJOR,
 GST_VERSION_MINOR,
 PLUGIN_NAME,
 "Interactive UDP connectivity establishment",
 plugin_init, "1.0", "LGPL", PACKAGE_NAME,
 "http://telepathy.freedesktop.org/wiki/");
 */